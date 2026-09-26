#!/usr/bin/env python3
"""p1/rq1_summarize.py -- per-cell RQ1 table (counts only).

Iterates /root/p1/rq1/<cell>/probe.csv + the metastab verdicts and
prints one line per cell: wedged?, probe verdict, gaps, gaps with
ready CQE throughout, ready-unserved sample-seconds, the kthread cpu
distribution. Usage: rq1_summarize.py <cell-glob>  e.g. 'A-*'
"""
import csv
import glob
import os
import sys
import collections

pat = sys.argv[1] if len(sys.argv) > 1 else "*"
min_gap = float(sys.argv[2]) if len(sys.argv) > 2 else 200.0

print("cell wedged probe gaps owned_gaps ready_unserved_s cpu_top")
for d in sorted(glob.glob(f"/root/p1/rq1/{pat}")):
    cell = os.path.basename(d)
    csvp = os.path.join(d, "probe.csv")
    env = f"/root/p1/metastab/M1-{cell}/cell.env"
    wedged, probe = "?", "?"
    if os.path.exists(env):
        txt = open(env).read()
        wedged = "YES" if "WEDGE mono" in txt and "NO-WEDGE" not in txt else "no"
        for line in txt.splitlines():
            if line.startswith("PROBE-"):
                probe = line.split()[0]
    if not os.path.exists(csvp):
        print(f"{cell} {wedged} {probe} no-probe")
        continue
    rows = []
    with open(csvp) as f:
        for r in csv.DictReader(f):
            rows.append(dict(ts=float(r["ts_ms"]), cc=int(r["cc"]),
                             owned=r["owned"] == "True",
                             pkt=int(r["packets"]), ev=int(r["events"]),
                             cpu=int(r["cpu"])))
    gaps = []
    start = 0
    for i in range(1, len(rows)):
        if rows[i]["pkt"] != rows[i - 1]["pkt"]:
            if rows[i]["ts"] - rows[start]["ts"] >= min_gap:
                gaps.append((start, i))
            start = i
    if rows and rows[-1]["ts"] - rows[start]["ts"] >= min_gap:
        gaps.append((start, len(rows)))
    og = 0
    rus = 0.0
    for a, b in gaps:
        seg = rows[a:b]
        if all(r["owned"] for r in seg):
            og += 1
            rus += (seg[-1]["ts"] - seg[0]["ts"]) / 1000.0
    cpus = collections.Counter(r["cpu"] for r in rows)
    top = ",".join(f"{c}x{n}" for c, n in cpus.most_common(3))
    print(f"{cell} {wedged} {probe} {len(gaps)} {og} {rus:.1f} {top}")
