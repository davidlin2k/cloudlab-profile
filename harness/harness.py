"""Replay harness: traces through policies over an LRU fleet.

Usage: python3 harness.py <replay.jsonl> [n_engines] [cap_blocks] [subset]
Prints one result line per policy: hit rate, wasted prefill tokens,
load max/mean, decisions. Run twice (P4 events come from the same
engine events the ground truth produces — each policy replays the
trace against its own fleet instance).
"""

import json
import sys

from engines import Fleet
from policies import RoundRobin, BoundedAffinity, ApproxTree, ExactIndex


def replay(pol, reqs, n, cap):
    ev_seen = {"n": 0}

    def on_event(eid, kind, blocks):
        ev_seen["n"] += 1
        if isinstance(pol, ExactIndex):
            pol.on_event(eid, kind, blocks)

    fleet = Fleet(n, cap, on_event)
    tot_blocks = 0
    hit_blocks = 0
    wasted = 0
    per_engine = [0] * n
    for req in reqs:
        e = pol.route(req, fleet)
        hit, miss = fleet.engines[e].serve(req["blocks"])
        pol.observe(req, e, hit, miss)
        tot_blocks += len(req["blocks"])
        hit_blocks += hit
        wasted += miss * req.get("bs", 512)
        per_engine[e] += 1
    return {
        "policy": pol.name(),
        "hit_rate": round(hit_blocks / tot_blocks, 4) if tot_blocks else 0.0,
        "wasted_prefill_tokens": wasted,
        "load_max_over_mean": round(max(per_engine) / (sum(per_engine) / n), 3)
        if sum(per_engine) else 0.0,
        "events": ev_seen["n"],
    }


def main():
    path = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 20000
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    reqs = []
    with open(path) as f:
        for line in f:
            r = json.loads(line)
            if r.get("blocks"):
                reqs.append(r)
            if limit and len(reqs) >= limit:
                break
    reqs.sort(key=lambda r: r["ts"])
    print(f"# trace={path} n_engines={n} cap_blocks={cap} reqs={len(reqs)}")
    for pol in (RoundRobin(n), BoundedAffinity(n), ApproxTree(n),
                ExactIndex(n)):
        print(json.dumps(replay(pol, reqs, n, cap)))


if __name__ == "__main__":
    main()
