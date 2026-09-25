#!/usr/bin/env python3
"""t4_eval.py -- DR-005 task 4 results: wedge rates per arm with the
pre-registered outcome rules (specs/p1-RINGSIZE.md, specs/p1-STRIDING.md).

usage: python3 t4_eval.py [METASTAB_ROOT]   (default /root/p1/metastab)

Cells are the task 1 M158 cells named M1-t4-<arm>-<i>: a cell counts
as wedged iff its cell.env carries WEDGE (and not NO-WEDGE). Reports
x/8 per arm with the exact 95% binomial interval (Clopper-Pearson via
the beta quantiles from statistics-free bisection on the binomial CDF),
then applies the frozen rules.
"""
import os, re, sys, math

def binom_ci(k, n, alpha=0.05):
    """Clopper-Pearson exact interval, bisection on the binomial CDF"""
    def cdf_to(j, p):
        if j < 0: return 0.0
        return sum(math.comb(n, i) * p**i * (1-p)**(n-i) for i in range(j + 1))
    def cdf(p):
        return cdf_to(k, p)
    def solve(f, target):
        lo, hi = 0.0, 1.0
        for _ in range(80):
            mid = (lo + hi) / 2
            if f(mid) > target: lo = mid
            else: hi = mid
        return (lo + hi) / 2
    lo = 0.0 if k == 0 else solve(lambda p: cdf_to(k - 1, p), 1 - alpha / 2)
    hi = 1.0 if k == n else solve(cdf, alpha / 2)   # CP: lower from cdf(k-1), upper from cdf(k)
    return lo, hi

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "/root/p1/metastab"
    arms = {}
    for cell in sorted(os.listdir(root)):
        m = re.match(r"M1-t4-(ring-default|ring-8192|striding-off)-(\d+)$", cell)
        if not m: continue
        envp = os.path.join(root, cell, "cell.env")
        if not os.path.exists(envp): continue
        env = open(envp, errors="replace").read()
        if "PROBE-" not in env:
            status = "incomplete"
        elif re.search(r"^WEDGE ", env, re.M):
            status = "wedged"
        elif "NO-WEDGE" in env:
            status = "no-wedge"
        else:
            status = "unknown"
        arms.setdefault(m.group(1), []).append((int(m.group(2)), status))
    rates = {}
    for arm, cells in sorted(arms.items()):
        cells.sort()
        n = len(cells)
        k = sum(1 for _, s in cells if s == "wedged")
        lo, hi = binom_ci(k, n)
        rates[arm] = k / n if n else 0
        print(f"{arm}: {k}/{n} wedged  rate={k/n:.2f}  95% CI [{lo:.2f}, {hi:.2f}]")
        print("   " + ", ".join(f"{i}:{s}" for i, s in cells))
    print()
    # the frozen rules
    d, e = rates.get("ring-default"), rates.get("ring-8192")
    if d is not None and e is not None:
        if e == 0:
            ratio = "inf" if d else "0"
        else:
            ratio = f"{d/e:.1f}"
        holds = (e == 0 and d > 0) or (e > 0 and d / e >= 4)
        print(f"ring size: default {d:.2f} vs 8192 {e:.2f}, ratio {ratio} -> "
              + ("prediction HOLDS (>=4x)" if holds else "prediction FAILS (<4x)"))
    s = rates.get("striding-off")
    if s is not None:
        print(f"striding off: {s:.2f} wedged -- descriptive only (the spec registered "
              "no direction); compare against the default arm above.")
    print("\n(rules: specs/p1-RINGSIZE.md and specs/p1-STRIDING.md, frozen 2026-09-25)")

if __name__ == "__main__":
    main()
