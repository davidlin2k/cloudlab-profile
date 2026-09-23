"""LRU block-cache engine simulation.

Engine = an LRU set of block hash ids with capacity in blocks. Reuse
follows prefix semantics: a request reuses the longest run of its
chain's leading blocks that are all present. Stored blocks are the
miss blocks plus the hit tail re-touch. Events (store/evict) are
emitted to subscribers — the exact-index policy consumes them, which
is what an event-driven router sees.
"""

from collections import OrderedDict


class Engine:
    def __init__(self, eid, capacity_blocks, on_event=None):
        self.eid = eid
        self.cap = capacity_blocks
        self.cache = OrderedDict()          # block_id -> None (LRU)
        self.on_event = on_event            # fn(eid, kind, blocks)

    def _store(self, b):
        if b in self.cache:
            self.cache.move_to_end(b)
            return False
        self.cache[b] = None
        while len(self.cache) > self.cap:
            old, _ = self.cache.popitem(last=False)
            if self.on_event:
                self.on_event(self.eid, "remove", [old])
        if self.on_event:
            self.on_event(self.eid, "store", [b])
        return True

    def serve(self, chain):
        """Return (hit_blocks, miss_blocks). Mutates cache state."""
        hit = 0
        for b in chain:
            if b in self.cache:
                hit += 1
            else:
                break
        # vLLM/llm-d semantics: the cached prefix stays; the MISS tail
        # (and only it) is computed and stored. Re-touch hit blocks for LRU.
        for b in chain[:hit]:
            self.cache.move_to_end(b)
        miss = chain[hit:]
        for b in miss:
            self._store(b)
        return hit, len(miss)


class Fleet:
    def __init__(self, n_engines, capacity_blocks, on_event=None):
        self.engines = [Engine(i, capacity_blocks, on_event)
                        for i in range(n_engines)]

    def state(self):
        return self.engines
