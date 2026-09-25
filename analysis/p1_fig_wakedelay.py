#!/usr/bin/env python3
"""p1_fig_wakedelay.py -- the workshop paper's Fig. 3 (DR-004 task 5,
section 5): wake-delay distributions, co-located against separated.

usage: .venv/bin/python analysis/p1_fig_wakedelay.py analysis/wakedelay outdir

Data: perf sched timehist wait-time columns (scheduler wait between wakeup
and running) for the app's request thread. UDP = k2_rx at 0.25x knee (130k,
adaptive-rx on/off, decision-8 runs); TCP = mc-worker at 0.25x knee (47.5k,
the W3 sched pair). Anchors (must reproduce before plotting; the recorded pairs are
mean/max of the sch-delay column):
  UDP P0-on 59.2/1242, P0-off 33.8/3502, P0X-on 1.7/906, P0X-off 2.1/892 us
  (decision-8 recorded 60/1.24ms, 34/3.50ms, 4/0.91ms, 4/0.89ms).
  TCP P0 47.0/791, P0X 3.2/1088 us (perf sched latency recorded 50/0.792ms,
  4/1.089ms; W3 note addendum).
Column provenance: timehist col 3 = sleep time (rejected: means 374 us etc.),
col 4 = scheduler wait after wakeup = the wake delay (reproduces every
anchor including all four UDP maxima to 3 significant figures).
"""
import os, sys
import numpy as np

sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

D = sys.argv[1] if len(sys.argv) > 2 else "analysis/wakedelay"
OUT = sys.argv[2] if len(sys.argv) > 2 else "analysis/out"

def waits(path):
    xs = []
    with open(path) as f:
        for line in f:
            t = line.split()
            if len(t) >= 4:
                try:
                    xs.append(float(t[4]))  # sch delay = wake delay (col 3 is sleep time)
                except ValueError:
                    continue
    return np.array(xs) * 1000.0  # ms -> us

def unwrap(res, n=1):
    if isinstance(res, tuple):
        fig, a = res[0], res[1]
    elif hasattr(res, "savefig"):
        fig, a = res, list(res.axes)[:n]
    elif hasattr(res, "plot"):
        fig, a = res.figure, [res]
    else:
        raise TypeError(type(res))
    axs = a if isinstance(a, (list, tuple)) or hasattr(a, "__len__") else [a]
    return fig, list(axs)

CURVES = {
    "udp": [("udp-P0-on.txt",  "co-located, adaptive-rx on",  "-",  "o"),
            ("udp-P0-off.txt", "co-located, adaptive-rx off", ":",  "o"),
            ("udp-P0X-on.txt", "separated, adaptive-rx on",   "-",  "^"),
            ("udp-P0X-off.txt","separated, adaptive-rx off",  ":",  "^")],
    "tcp": [("tcp-P0.txt",  "co-located", "-", "o"),
            ("tcp-P0X.txt", "separated",  "-", "^")],
}
COLORS = {"co-located, adaptive-rx on": PALETTE["blue_main"],
          "co-located, adaptive-rx off": PALETTE["blue_secondary"],
          "separated, adaptive-rx on": PALETTE["teal"],
          "separated, adaptive-rx off": PALETTE["green_3"],
          "co-located": PALETTE["blue_main"],
          "separated": PALETTE["teal"]}

def main():
    data = {}
    for panel in ("udp", "tcp"):
        for fn, lab, ls, mk in CURVES[panel]:
            data[lab] = waits(os.path.join(D, fn))

    # ---- anchor checks (verify-before-plot) ----
    anchors = [("co-located, adaptive-rx on", 59.2, 1242), ("co-located, adaptive-rx off", 33.8, 3502),
               ("separated, adaptive-rx on", 1.7, 906), ("separated, adaptive-rx off", 2.1, 892),
               ("co-located", 47.0, 791), ("separated", 3.2, 1088)]
    ok = True
    for lab, emean, emax in anchors:
        x = data[lab]
        m, mx = float(x.mean()), float(x.max())
        good = abs(m - emean) <= max(0.15 * emean, 2.0) and abs(mx - emax) <= 0.05 * emax
        print(f"anchor {lab}: mean {m:.1f} (expect {emean}), max {mx:.0f} (expect {emax}) "
              f"{'OK' if good else 'MISMATCH'}")
        ok = ok and good
    if not ok:
        print("ANCHOR MISMATCH -- not plotting")
        sys.exit(2)

    apply_publication_style()
    res = create_subplots(2, 1, figsize=(3.5, 4.8))
    fig, axs = unwrap(res, 2)
    for ax, panel, title in ((axs[0], "udp", "UDP request path (0.25x knee)"),
                             (axs[1], "tcp", "memcached worker (0.25x knee)")):
        for fn, lab, ls, mk in CURVES[panel]:
            x = np.sort(data[lab])
            y = np.arange(1, len(x) + 1) / len(x)
            ax.plot(x, y, label=lab, color=COLORS[lab], linestyle=ls,
                    linewidth=1.5, marker=mk, markevery=max(1, len(x) // 9),
                    markersize=3.5)
        ax.set_xscale("log")
        ax.set_xlim(0.8, 20000)
        ax.set_ylim(0, 1.02)
        ax.set_title(title, fontsize=8.5, pad=6)
        ax.grid(True, alpha=0.25, linewidth=0.6)
    axs[0].tick_params(labelbottom=False)
    axs[0].set_xlabel("")
    axs[0].set_ylabel("fraction of wakeups")
    axs[1].set_ylabel("fraction of wakeups")
    axs[1].set_xlabel("scheduler wait after wakeup (us)")
    fig.subplots_adjust(hspace=0.42, left=0.16, right=0.97, top=0.93, bottom=0.24)
    # the separated CDFs rise at the left edge and the co-located ones cross
    # the middle: no in-panel corner is free, so the legend sits below the
    # figure (2x2, outside every axes)
    h, l = axs[0].get_legend_handles_labels()
    leg = fig.legend(h, l, loc="lower center", bbox_to_anchor=(0.5, 0.01),
                     ncol=2, frameon=False, fontsize=7, handlelength=1.5,
                     columnspacing=1.0, labelspacing=0.35)
    print(finalize_figure(fig, os.path.join(OUT, "fig3-wakedelay"),
                          formats=["png", "pdf"], dpi=300))

if __name__ == "__main__":
    main()
