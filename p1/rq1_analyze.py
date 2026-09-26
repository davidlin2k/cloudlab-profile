#!/usr/bin/env python3
"""p1/rq1_analyze.py -- per-gap stranded-work analysis (specs/p1-CAUSAL.md).

Reads a probe.csv (ts_ms,cc,own,phase,owned,packets,events,arm,state,cpu)
and reports, per gap (a span with packets flat):
  gap# start end duration owned_throughout cpu events_delta arm_delta
Counts: gaps, gaps-with-ready-CQE-throughout, ready-unserved sample
seconds. Also validates the probe (a healthy queue: zero such spans).
Usage: rq1_analyze.py <probe.csv> [min_gap_ms]
"""
import csv
import sys

path = sys.argv[1]
min_gap = float(sys.argv[2]) if len(sys.argv) > 2 else 200.0  # ms

rows = []
with open(path) as f:
    for r in csv.DictReader(f):
        rows.append(dict(ts=float(r["ts_ms"]), cc=int(r["cc"]),
                         own=int(r["own"]), owned=r["owned"] == "True",
                         pkt=int(r["packets"]), ev=int(r["events"]),
                         arm=int(r["arm"]), st=int(r["state"]),
                         cpu=int(r["cpu"])))
if len(rows) < 10:
    sys.exit("probe csv too short")

# gaps = maximal spans with packets flat; spans shorter than min_gap ms
# are dropped (the flood phase has normal inter-poll jitter)
gaps = []
start = 0
for i in range(1, len(rows)):
    if rows[i]["pkt"] != rows[i - 1]["pkt"]:
        if rows[i]["ts"] - rows[start]["ts"] >= min_gap:
            gaps.append((start, i))
        start = i
if rows[-1]["ts"] - rows[start]["ts"] >= min_gap:
    gaps.append((start, len(rows)))

n_ready_throughout = 0
ready_sample_seconds = 0.0
print(f"== {path}: {len(rows)} samples, {len(gaps)} gaps >= {min_gap:.0f} ms")
print("gap# t_start t_end dur_s owned_throughout cc_range cpu events_d arm_d")
for k, (a, b) in enumerate(gaps, 1):
    seg = rows[a:b]
    owned_all = all(r["owned"] for r in seg)
    evd = seg[-1]["ev"] - seg[0]["ev"]
    armd = seg[-1]["arm"] - seg[0]["arm"]
    if owned_all:
        n_ready_throughout += 1
        ready_sample_seconds += (seg[-1]["ts"] - seg[0]["ts"]) / 1000.0
    ccs = sorted({r["cc"] for r in seg})
    print(f"{k} {seg[0]['ts']:.0f} {seg[-1]['ts']:.0f} "
          f"{(seg[-1]['ts'] - seg[0]['ts']) / 1000:.1f} {owned_all} "
          f"{ccs[0]}..{ccs[-1]} {seg[0]['cpu']} {evd} {armd}")
print(f"SUMMARY gaps={len(gaps)} owned_throughout={n_ready_throughout} "
      f"ready_unserved_sample_s={ready_sample_seconds:.1f}")
