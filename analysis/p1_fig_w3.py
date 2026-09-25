#!/usr/bin/env python3
"""p1_fig_w3.py -- Fig. 7 first rows (W3): goodput under SLO vs offered load
for memcached under mutilate, three placements (DR-004 W3; spec p1-W3MEMC).

usage: .venv/bin/python analysis/p1_fig_w3.py rows-w3-full.csv outdir

Contract (paper1-skeleton.md): Fig. 7 = "memcached: goodput under SLO against
load, every policy plus IRQ suspension and busy polling". The x axis is pinned
to the contract's knee multiples (0.25, 0.5, 1.0, 1.5, 2.0 x the P0 knee =
190k QPS per spec v3). Goodput under SLO = achieved x SLO-frac, SLO = 10x the
idle p99 = 1.05 ms. 3 reps; asymmetric bootstrap 95% intervals as errorbars
(the figs 1-3 pattern).
"""
import csv, os, random, sys

sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

KNEE = 190000.0  # P0 saturation knee (spec v3)
ARM_ORDER = ["P0", "P0X", "BP"]
ARM_LABEL = {"P0": "inline (default)",
             "P0X": "inline, app elsewhere",
             "BP": "busy polling"}
COLORS = {"P0": PALETTE["blue_main"], "P0X": PALETTE["blue_secondary"],
          "BP": PALETTE["teal"]}
MARKERS = {"P0": "o", "P0X": "^", "BP": "s"}
LINES = {"P0": "-", "P0X": (0, (1, 1.2)), "BP": (0, (5, 2))}

def unwrap(res):
    if hasattr(res, "plot") and hasattr(res, "figure"):
        return res.figure, res          # bare Axes
    if isinstance(res, tuple):
        return res[0], res[1]           # (fig, ax)
    if hasattr(res, "savefig"):
        return res, res.axes[0]         # bare Figure
    raise TypeError(f"create_subplots returned {type(res)}")

def boot_ci(vals, iters=4000, seed=7):
    if len(vals) == 1:
        return vals[0], vals[0], vals[0]
    rng = random.Random(seed)
    meds = []
    for _ in range(iters):
        s = [vals[rng.randrange(len(vals))] for _ in vals]
        meds.append(sorted(s)[len(s) // 2])
    meds.sort()
    return sorted(vals)[len(vals) // 2], meds[int(0.025 * iters)], meds[int(0.975 * iters)]

def load_rows(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            if r["src"] != "main":
                continue
            ach = float(r["achieved"]); sl = float(r["slo_frac"])
            rows.append(dict(arm=r["arm"], target=int(r["target"]),
                             rep=int(r["rep"]), gus=ach * sl, ach=ach))
    return rows

def fig7(rows, out):
    apply_publication_style()
    res = create_subplots(figsize=(3.5, 2.7))
    fig, ax = unwrap(res)
    for arm in ARM_ORDER:
        xs, ys, lo, hi = [], [], [], []
        for tgt in sorted({r["target"] for r in rows if r["arm"] == arm}):
            vals = [r["gus"] for r in rows if r["arm"] == arm and r["target"] == tgt]
            m, l, h = boot_ci(vals)
            xs.append(tgt / KNEE); ys.append(m / 1000.0)
            lo.append((m - l) / 1000.0); hi.append((h - m) / 1000.0)
        ax.errorbar(xs, ys, yerr=[lo, hi], label=ARM_LABEL[arm],
                    color=COLORS[arm], marker=MARKERS[arm], linestyle=LINES[arm],
                    linewidth=1.6, markersize=5, capsize=2.5, elinewidth=1.0)
    ax.set_xlabel("offered load (x knee)")
    ax.set_ylabel("goodput under SLO (kQPS)")
    ax.set_xlim(0.15, 2.12)
    ax.set_ylim(0, 420)
    leg = ax.legend(loc="lower center", bbox_to_anchor=(0.5, 1.02), ncol=3,
                    frameon=False, fontsize=8, handlelength=1.6,
                    columnspacing=1.0, borderaxespad=0.0)
    ax.grid(True, alpha=0.25, linewidth=0.6)
    return finalize_figure(fig, os.path.join(out, "fig7-w3"),
                           formats=["png", "pdf"], dpi=300)

def main():
    rows = load_rows(sys.argv[1])
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    # verify-before-plot: one known x-mapping + the contract number
    chk = [r for r in rows if r["arm"] == "P0X" and r["target"] == 285000]
    assert chk, "P0X 285k rows missing"
    gus = sorted(r["gus"] for r in chk)
    print(f"verify P0X @1.5x knee: goodput-under-SLO {gus[0]/1000:.1f}-"
          f"{gus[-1]/1000:.1f} kQPS over {len(chk)} reps (claims text: SLO frac "
          f"0.999 at 285k delivered 285.0k -> expect ~284-285 kQPS)")
    print(fig7(rows, out))

if __name__ == "__main__":
    main()
