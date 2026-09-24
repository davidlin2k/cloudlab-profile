#!/usr/bin/env python3
"""p1_wedge_ab.py -- AN-003 wedge A/B classifier (tags wedge-m0/m1).

usage: python3 p1_wedge_ab.py rows-wedge-m0.csv rows-wedge-m1.csv
A cell WEDGED when delivered fraction < 0.2 with socket/ring drops > half
the offered budget (the AN-003 signature: ring never drained), healthy
otherwise (P2-style capped delivery counts as healthy). Prints the
placement x pin x rep table and the verdict: does PIN_IDLE (C-state
pinning) change wedge probability?
"""
import csv, sys

def fnum(x, d=float("nan")):
    try:
        return float(x)
    except (TypeError, ValueError):
        return d

rows = []
for path in sys.argv[1:]:
    rows += [r for r in csv.DictReader(open(path), delimiter=" ")]

cells = {}
for r in rows:
    pin = 0 if r.get("tag", "").endswith("m0") else 1
    key = (pin, r["policy"], int(fnum(r["rep"])))
    d = fnum(r.get("deliv")); s = fnum(r.get("sockdrops")); o = fnum(r.get("offered"))
    wedged = (d == d and d < 0.2 and s == s and s > 0.5 * o * 63)
    cells[key] = (d, s, wedged)

print("pin policy rep deliv sockdrops verdict")
counts = {}
for (pin, pol, rep), (d, s, w) in sorted(cells.items()):
    print(f"  {pin}    {pol}    {rep}   {d:.2f}  {s:.0f}  {'WEDGED' if w else 'healthy'}")
    counts.setdefault((pin, pol), [0, 0])
    counts[(pin, pol)][1] += 1
    counts[(pin, pol)][0] += 1 if w else 0

print("\n== wedge rate by (pin, policy)")
for (pin, pol), (w, n) in sorted(counts.items()):
    print(f"  pin={pin} {pol}: {w}/{n} wedged")

p1 = sum(w for (pin, pol), (w, n) in counts.items() if pin == 1)
p0 = sum(w for (pin, pol), (w, n) in counts.items() if pin == 0)
n1 = sum(n for (pin, pol), (w, n) in counts.items() if pin == 1)
n0 = sum(n for (pin, pol), (w, n) in counts.items() if pin == 0)
print(f"\nC-state pin ON (pin=1): {p1}/{n1}   OFF (pin=0): {p0}/{n0}")
print("VERDICT:", "PIN_IDLE changes wedge probability -- C-state trigger CONFIRMED"
      if (p1 == 0) != (p0 == 0) else
      "no clean separation by C-state pinning" if p1 and p0 else
      "wedge absent in both halves -- trigger is order/affinity-history, not C-state")
