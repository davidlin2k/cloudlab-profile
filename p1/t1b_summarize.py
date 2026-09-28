#!/usr/bin/env python3
"""t1b_summarize.py -- per-arm tally from the two pairs' results CSVs.

Usage: t1b_summarize.py <results-P1.csv> <results-P2.csv>
Prints the frozen decision-rule view (specs/p1-T1B.md):
  per arm: cells, stranded verdicts, max strand, packet conservation.
"""
import csv
import sys

rows = []
for p in sys.argv[1:3]:
    with open(p) as f:
        for r in csv.DictReader(f):
            if r["cell"].startswith("P"):
                r["pair"] = r["cell"][1]
                rows.append(r)

if not rows:
    sys.exit("no cell rows yet")

print("%-12s %5s %9s %7s %12s %12s %6s" % (
    "arm", "cells", "stranded", "max_str", "pkts_delta", "sent", "drops"))
for arm in "ABCD":
    a = [r for r in rows if r["arm"] == arm]
    if not a:
        continue
    strands = sum(1 for r in a if r["verdict"] != "none")
    ms = max(float(r["max_strand_ms"] or 0) for r in a)
    good = sum(1 for r in a if r["pkts_delta"] == r["sent"] and
               int(r["drops_delta"] or 0) == 0)
    print("%-12s %5d %9d %7.1f %12s %12s %6s (conserved %d/%d)" % (
        arm, len(a), strands, ms,
        sum(int(r["pkts_delta"]) for r in a),
        sum(int(r["sent"]) for r in a),
        sum(int(r["drops_delta"] or 0) for r in a), good, len(a)))

cells_per_arm = {arm: sum(1 for r in rows if r["arm"] == arm)
                 for arm in "ABCD"}
strands_per_arm = {arm: sum(1 for r in rows if r["arm"] == arm
                            and r["verdict"] != "none")
                   for arm in "ABCD"}
print()
print("cells per arm so far:", cells_per_arm)
print("decision rule: any arm >=3/8 stranded with DD confirmed -> stop,"
      " tell PI; all <=1/8 -> not reproduced on i40e; else inconclusive")
bad = [arm for arm in "ABCD"
       if cells_per_arm[arm] >= 3 and strands_per_arm[arm] >= 3]
clean = [arm for arm in "ABCD"
         if cells_per_arm[arm] >= 3 and strands_per_arm[arm] <= 1]
if bad:
    print("VERDICT SO FAR: strands in arms %s -- >=3/8 rule hit" % bad)
elif all(cells_per_arm[a] >= 3 for a in "ABCD") and clean:
    print("VERDICT SO FAR: all arms <=1/8")
else:
    print("VERDICT SO FAR: pending (inconclusive until 8 cells/arm)")