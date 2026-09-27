#!/usr/bin/env python3
"""p1/hop_gap_analyze.py -- the p1-MIGRATE v2 decisive statistic
(specs/p1-MIGRATE.md v2): for every stranded gap, is it a
MIGRATION-MOMENT gap (it starts within HOP_MS of an observed cpu
change) or a RESIDENCE gap (it falls inside one cpu's residence)?
The cpu changes are read from the probe's own cpu column
(self-calibrated -- no cross-process offset), cross-checked against
the hopper's log when provided.

Usage: hop_gap_analyze.py <probe.csv> [hops.csv] [HOP_MS]
Prints per-gap lines + the summary.
"""
import csv
import sys

probe_csv = sys.argv[1]
hops_csv = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "-" else None
HOP_MS = float(sys.argv[3]) if len(sys.argv) > 3 else 50.0

rows = []
with open(probe_csv) as f:
    for r in csv.DictReader(f):
        rows.append(dict(ts=float(r["ts_ms"]) / 1000.0, cc=int(r["cc"]),
                         owned=r["owned"] == "True",
                         pkt=int(r["packets"]), cpu=int(r["cpu"])))

# observed cpu-change moments in the probe's own timebase
changes = []
for i in range(1, len(rows)):
    if rows[i]["cpu"] != rows[i - 1]["cpu"] and rows[i - 1]["cpu"] in (10, 46):
        changes.append(rows[i]["ts"])
hops = []
if hops_csv:
    with open(hops_csv) as f:
        for r in csv.DictReader(f):
            hops.append(float(r["ts_ms"]) / 1000.0)
print(f"{len(rows)} samples; observed cpu changes: {len(changes)}; "
      f"hopper log entries: {len(hops)}")

gaps = []
start = 0
for i in range(1, len(rows)):
    if rows[i]["pkt"] != rows[i - 1]["pkt"]:
        if rows[i]["ts"] - rows[start]["ts"] >= 0.2:
            gaps.append((start, i))
        start = i
if rows and rows[-1]["ts"] - rows[start]["ts"] >= 0.2:
    gaps.append((start, len(rows) - 1))

stranded = [(a, b) for a, b in gaps if all(r["owned"] for r in rows[a:b])]
mig, res46, res10, resmix = 0, 0, 0, 0
hist = {0: 0, 1: 0, 2: 0, 5: 0, 10: 0, 25: 0, 50: 0, 100: 0}
MOMENT_MS = 2.0
print("gap# t_start dur_s t_since_hop_s residence verdict")
for k, (a, b) in enumerate(stranded, 1):
    t0 = rows[a]["ts"]
    dur = rows[b]["ts"] - t0
    seg = rows[a:b]
    mix = {c: sum(1 for r in seg if r["cpu"] == c) for c in (10, 46)}
    dom = max(mix, key=mix.get)
    prior = [c for c in changes if c <= t0]
    tsh = (t0 - prior[-1]) * 1000 if prior else float("inf")
    for edge in sorted(hist):
        if tsh < edge:
            hist[edge] += 1
            break
    else:
        hist[100] += 1
    if tsh <= MOMENT_MS:
        verdict = "MIGRATION-MOMENT"
        mig += 1
    elif mix[46] > 0.8 * len(seg):
        verdict = "RESIDENCE-46"
        res46 += 1
    elif mix[10] > 0.8 * len(seg):
        verdict = "RESIDENCE-10"
        res10 += 1
    else:
        verdict = "RESIDENCE-MIX"
        resmix += 1
    tshs = f"{tsh:.0f}ms" if tsh != float("inf") else "n/a"
    print(f"{k} {t0:.1f} {dur:.1f} {tshs} "
          f"46={mix[46] / len(seg) * 100:.0f}% "
          f"10={mix[10] / len(seg) * 100:.0f}% "
          f"{verdict}")
print(f"SUMMARY stranded={len(stranded)} migration-moment(<=2ms)={mig} "
      f"residence46={res46} residence10={res10} residence-mix={resmix}")
print("t_since_hop histogram (ms, cumulative upper edge): "
      + ", ".join(f"<{e}:{v}" for e, v in sorted(hist.items()))
      + f"  [uniform-over-100ms expectation per bin: "
      f"{len(stranded) * (sorted(hist)[1] - sorted(hist)[0]) / 100.0:.1f}]")
