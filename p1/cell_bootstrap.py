#!/usr/bin/env python3
"""p1/cell_bootstrap.py -- DR-012 step 5: cell-level bootstrap statistics.

The units are CELLS, not gaps (gaps within a cell are non-independent).
Two statistics, percentile bootstrap (B=10000, seed fixed):

  1. wedge-rate difference between two arms from per-cell 0/1 wedge
     indicators.
  2. migration-moment onset fraction (the HOP statistic): per cell the
     fraction of that cell's stranded gaps starting <= 2 ms of an
     observed cpu change; the bootstrap CI is over cells; the null
     rate 2/100 (the 100 ms hop period) is reported alongside, with a
     per-cell sign test against it.

Usage:
  cell_bootstrap.py wedges <armA:n_wedged:n_cells> <armB:...> [B]
  cell_bootstrap.py onsets <csv: cell,onset_frac,n_gaps> [null] [B]

Facts only; the script prints the point estimates, the CI, and the
per-cell data it was fed.
"""
import random
import sys

mode = sys.argv[1]
B = int(sys.argv[-1]) if len(sys.argv) > 3 and sys.argv[-1].isdigit() else 10000
rng = random.Random(20260927)


def pct(xs, q):
    xs = sorted(xs)
    return xs[int(q * (len(xs) - 1))]


if mode == "wedges":
    arms = []
    for a in sys.argv[2:-1] if sys.argv[-1].isdigit() else sys.argv[2:]:
        name, w, n = a.split(":")
        w, n = int(w), int(n)
        cells = [1] * w + [0] * (n - w)
        arms.append((name, cells))
        print(f"{name}: {w}/{n} wedged ({w / n:.3f})")
    if len(arms) != 2:
        sys.exit("need exactly two arms")
    (_, ca), (_, cb) = arms
    diffs = []
    for _ in range(B):
        ra = [rng.choice(ca) for _ in ca]
        rb = [rng.choice(cb) for _ in cb]
        diffs.append(sum(ra) / len(ra) - sum(rb) / len(rb))
    point = sum(ca) / len(ca) - sum(cb) / len(cb)
    print(f"diff (A-B) = {point:+.3f}  95% CI [{pct(diffs, 0.025):+.3f}, {pct(diffs, 0.975):+.3f}]  (B={B} over cells)")

elif mode == "onsets":
    null = float(sys.argv[3]) if len(sys.argv) > 3 and not sys.argv[3].isdigit() else 0.02
    rows = []
    for line in open(sys.argv[2]):
        cell, frac, n = line.strip().split(",")
        rows.append((cell, float(frac), int(n)))
        print(f"{cell}: onset_frac={float(frac):.3f} n_gaps={n}")
    fracs = [r[1] for r in rows]
    point = sum(fracs) / len(fracs)
    boots = []
    for _ in range(B):
        s = [rng.choice(fracs) for _ in fracs]
        boots.append(sum(s) / len(s))
    print(f"mean onset fraction = {point:.3f}  95% CI [{pct(boots, 0.025):.3f}, {pct(boots, 0.975):.3f}]"
          f"  null rate = {null:.3f}  (B={B} over {len(rows)} cells)")
    above = sum(1 for f in fracs if f > null)
    n = len(rows)
    # two-sided binomial sign test: P(X >= above or X <= n-above | p=0.5)
    from math import comb
    tail = sum(comb(n, k) for k in range(max(above, n - above), n + 1)) / 2 ** n
    p_two = min(1.0, 2 * tail)
    print(f"cells above the null rate: {above}/{n} (sign test p_two = {p_two:.4f})")
else:
    sys.exit("mode must be 'wedges' or 'onsets'")
