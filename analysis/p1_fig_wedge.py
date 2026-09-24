#!/usr/bin/env python3
"""p1_fig_wedge.py -- the wedge A/B survival curves (W39 figure of the
week; DR-003). Per arm: fraction of the 8 cells not yet wedged at time
t under a 790k pps flood (195 s budget; end ticks = censored cells).

Data: analysis/rows-wdiag.csv, verified cell-by-cell against the
WDIAG-DONE summary before plotting (anchor check in the parse step).

Honesty note: the pre-registered mlx5 poll-affinity hypothesis is
REFUTED by this matrix (AN-006); the figure shows the raw onset data,
which is what the refutation rests on.
"""
import csv, sys
sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

ARM_ORDER = ["unpin", "ali-P4", "ali-P3", "P2", "mis-P4", "mis-P3"]
LABELS = {
    "unpin": "unpinned (0-63): 8/8",
    "ali-P4": "IRQ=thread CPU 9: 6/8",
    "ali-P3": "IRQ=thread CPU 40: 6/8",
    "P2": "thread=IRQ=CPU 8: 4/8",
    "mis-P4": "thread 9, IRQ 8: 5/8",
    "mis-P3": "thread 40, IRQ 8: 4/8",
}
COLORS = {"unpin": PALETTE["red_strong"], "ali-P4": PALETTE["blue_main"],
          "ali-P3": PALETTE["blue_secondary"], "P2": PALETTE["teal"],
          "mis-P4": PALETTE["green_3"], "mis-P3": PALETTE["violet"]}
STYLES = {"unpin": "-", "ali-P4": "-", "ali-P3": "-.", "P2": ":",
          "mis-P4": "--", "mis-P3": "--"}

rows = list(csv.DictReader(open("analysis/rows-wdiag.csv"), delimiter=" "))
assert len(rows) == 48, f"expected 48 cells, got {len(rows)}"
data = {}
for r in rows:
    d = data.setdefault(r["arm"], {"onsets": [], "spans": []})
    if r["wedged"] == "1":
        d["onsets"].append(int(r["onset"]))
    else:
        d["spans"].append(int(r["span"]))
for d in data.values():
    d["onsets"].sort()

apply_publication_style()
res = create_subplots(1, 1)
cands = res if isinstance(res, (list, tuple)) else [res]
ax = next((c for c in cands if hasattr(c, "step")), None)
if ax is None:  # a Figure came back: take its axes or make one
    fig = cands[0]
    ax = fig.axes[0] if fig.axes else fig.add_subplot(1, 1, 1)

for arm in ARM_ORDER:
    d = data[arm]
    n = len(d["onsets"]) + len(d["spans"])
    xs = [0.0] + [float(t) for t in d["onsets"]]
    ys = [(n - i) / n for i in range(len(xs))]
    xs.append(max(d["spans"]) if d["spans"] else 201.0)
    ys.append(ys[-1])
    ax.step(xs, ys, where="post", color=COLORS[arm], linestyle=STYLES[arm],
            linewidth=2.2, label=LABELS[arm], zorder=3)
    for sp in d["spans"]:
        ax.plot([sp], [ys[-1]], marker="|", color=COLORS[arm],
                markersize=7, markeredgewidth=1.6, zorder=4)

ax.axvline(195, color="gray", linewidth=0.9, linestyle="-", alpha=0.5,
           zorder=1)
ax.text(196, 0.04, "195 s budget", fontsize=8, color="gray", ha="left")
ax.set_xlim(0, 210)
ax.set_ylim(0, 1.06)
ax.set_xlabel("time under 790k pps flood (s)")
ax.set_ylabel("survival (cells not yet wedged)")
ax.legend(loc="lower center", bbox_to_anchor=(0.5, 1.02), ncol=3,
          fontsize=9, frameon=False, columnspacing=1.4, handlelength=2.4)

saved = finalize_figure(fig=ax.figure, out_path="analysis/out/fig-wedge-ab",
                        formats=["png", "pdf"], dpi=300)
print("wrote:", saved)
