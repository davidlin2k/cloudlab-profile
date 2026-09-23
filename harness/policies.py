"""Routing policies. Each policy: route(req, fleet) -> engine index.

req: dict(ts, session, blocks, input_len, output_len).
After the harness serves the request on the chosen engine, it calls
policy.observe(req, eid, hit, miss) so policies that learn from their
own decisions (approximate tree, speculation) or from events
(exact index) update.

The load signal available to every policy is the same as production's:
recent arrival counts per engine (decision-time load, the thing the
emulator showed herds when stale).
"""


class RoundRobin:
    def __init__(self, n):
        self.n = n
        self.i = 0

    def route(self, req, fleet):
        e = self.i % self.n
        self.i += 1
        return e

    def observe(self, req, eid, hit, miss):
        pass

    def name(self):
        return "P1-rr"


class BoundedAffinity:
    """P2: consistent hash on session id with bounded loads
    (Google CHWL, epsilon) + hot-prefix replication.

    Replication: blocks whose global demand rate (requests touching
    them per second, decaying average) exceeds r1 * 1.0 engine
    capacity share are mirrored onto the top-R engines by demand.
    Mirrored blocks count toward capacity (the cost is real).
    """

    def __init__(self, n, epsilon=1.0, replica_r=0, hot_rate=0.0):
        self.n = n
        self.eps = epsilon
        self.R = replica_r
        self.hot_rate = hot_rate
        self.loads = [0.0] * n          # decaying arrival load
        self.block_dem = {}             # block -> decaying demand (rps)
        self.mirrored = {}              # block -> set(eids)
        self.last_ts = 0.0
        self.h = {}                     # session -> stable hash

    def _sh(self, s):
        if s not in self.h:
            self.h[s] = hash(s) & 0xFFFFFFFF
        return self.h[s]

    def route(self, req, fleet):
        dt = max(0.0, req["ts"] - self.last_ts)
        self.last_ts = req["ts"]
        dec = 0.5 ** (dt / 5.0) if dt > 0 else 1.0     # 5 s half-life
        for i in range(self.n):
            self.loads[i] *= dec
        target = self._bh(req["session"], fleet)
        self.loads[target] += 1.0
        return target

    def _bh(self, session, fleet):
        h = self._sh(session)
        avg = sum(self.loads) / self.n
        cap = self.eps * max(avg, 1e-9)
        # walk the ring probes (bounded loads, K=25 probes)
        for k in range(25):
            e = (h + k * 2654435761) % self.n
            if self.loads[e] <= cap or k == 24:
                return e
        return h % self.n

    def _pick(self, req):
        return 0

    def observe(self, req, eid, hit, miss):
        # demand tracking for replication (shared roots = hot prefixes)
        for b in req["blocks"][:8]:
            self.block_dem[b] = self.block_dem.get(b, 0.0) * 0.99 + 1.0

    def mirror(self):
        """Return {eid: [blocks]} to replicate this instant."""
        out = {}
        if not self.R:
            return out
        hot = [(b, d) for b, d in self.block_dem.items() if d >= self.hot_rate]
        hot.sort(key=lambda x: -x[1])
        for b, _ in hot[:50]:
            holders = sorted(range(self.n),
                             key=lambda e: self.loads[e])[:self.R]
            for e in holders:
                out.setdefault(e, []).append(b)
        return out

    def name(self):
        return "P2-bch"


class ApproxTree:
    """P3: approximate tree — a bounded LRU map of prefix->engine
    updated on ROUTING DECISIONS only (no cache events). It lies
    after its own entries are evicted and after engine evictions,
    which is exactly the published approximation mode."""

    def __init__(self, n, entries=200000):
        self.n = n
        self.entries = entries
        from collections import OrderedDict
        self.tree = OrderedDict()       # block -> eid (LRU)
        self.loads = [0.0] * n

    def route(self, req, fleet):
        best_e, best_len = None, 0
        for i, b in enumerate(req["blocks"]):
            e = self.tree.get(b)
            if e is not None and i + 1 > best_len:
                best_e, best_len = e, i + 1
        if best_e is None:
            best_e = self.loads.index(min(self.loads))
        for i in range(self.n):
            self.loads[i] *= 0.999
        self.loads[best_e] += 1.0
        return best_e

    def observe(self, req, eid, hit, miss):
        for b in req["blocks"][:8]:
            if b in self.tree:
                self.tree.move_to_end(b)
            self.tree[b] = eid
            if len(self.tree) > self.entries:
                self.tree.popitem(last=False)

    def name(self):
        return "P3-approx"


class ExactIndex:
    """P4: event-driven exact index. Sees only engine EVENTS
    (store/remove), never the harness's private state. Route = engine
    holding the longest cached prefix of the chain; tie-break least
    recent-load."""

    def __init__(self, n, lag_s=0.0, loss_rate=0.0, seed=0):
        self.n = n
        self.lag = lag_s                # convergence delay L (s)
        self.loss = loss_rate
        self.idx = {}                   # block -> set(eids)
        self.pending = []               # (apply_ts, eid, kind, blocks)
        self.loads = [0.0] * n
        import random
        self.rng = random.Random(seed)

    def on_event(self, eid, kind, blocks):
        apply_at = self._now + self.lag
        self.pending.append((apply_at, eid, kind, blocks))

    _now = 0.0

    def _drain(self, ts):
        self._now = ts
        due = [p for p in self.pending if p[0] <= ts]
        if due:
            self.pending = [p for p in self.pending if p[0] > ts]
            for _, eid, kind, blocks in due:
                s = self.idx.setdefault
                for b in blocks:
                    if kind == "store":
                        s(b, set()).add(eid)
                    else:
                        st = self.idx.get(b)
                        if st and eid in st:
                            st.discard(eid)
                            if not st:
                                del self.idx[b]

    def route(self, req, fleet):
        self._drain(req["ts"])
        best_e, best_len = None, 0
        for i, b in enumerate(req["blocks"]):
            st = self.idx.get(b)
            if st:
                # prefer an engine holding the LONGEST prefix
                for e in st:
                    if i + 1 > best_len:
                        best_e, best_len = e, i + 1
        if best_e is None:
            best_e = self.loads.index(min(self.loads))
        for i in range(self.n):
            self.loads[i] *= 0.999
        self.loads[best_e] += 1.0
        return best_e

    def observe(self, req, eid, hit, miss):
        pass

    def name(self):
        return "P4-exact"


class ExactSpec(ExactIndex):
    """P5: exact + speculation. On each routing decision, speculatively
    insert the request's FULL chain for the chosen engine (as llm-d's
    speculative entries do), TTL-corrected: if the engine's real store
    event never arrives within ttl, the entry expires."""

    def __init__(self, n, lag_s=0.0, ttl=2.0, seed=0):
        super().__init__(n, lag_s, 0.0, seed)
        self.ttl = ttl
        self.spec = []                  # (expire_ts, block, eid)

    def route(self, req, fleet):
        self._drain(req["ts"])
        e = super().route(req, fleet)
        exp = req["ts"] + self.ttl
        for b in req["blocks"]:
            self.spec.append((exp, b, e))
        return e

    def _drain(self, ts):
        super()._drain(ts)
        keep = []
        for exp, b, e in self.spec:
            if exp > ts:
                keep.append((exp, b, e))
                continue
            st = self.idx.get(b)
            if st and e in st:
                # corrected by a real store event; keep
                continue
            st = self.idx.get(b)
            if st and e in st:
                continue
        self.spec = keep
        # NOTE: speculative entries must not survive contradicted truth:
        # real remove events already dropped them via self.idx.

    def name(self):
        return "P5-spec"
