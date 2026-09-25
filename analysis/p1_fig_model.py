#!/usr/bin/env python3
"""p1_fig_model.py -- the workshop paper's Fig. 2 (DR-004 task 5, section 4):
the hidden share, and the knee model with and without the correction.

usage: .venv/bin/python analysis/p1_fig_model.py analysis/rows-fig1-3.csv outdir

Panel (a): hidden share of per-packet CPU at 390k (0.89x knee) on the
co-located app core -- the receive work that per-thread accounting cannot
see. Two instruments are shown: the schedstat derivation from rows-fig1-3
(anchors: P0 range 25.0-40.3%, mean 32.2%, n=3) and C-006's independent
measurement (/p1/pmudrain + /p1/softirq_poll: 26-42%, mean 33%) plotted
as the band -- the agreement is the point (the re-grade's h = 0.33
calibration came from the independent measurement).
Panel (b): predicted vs measured knee with and without the (1-h) correction.
Anchors (checkpoints/2026-09-24-recovery-and-knee-regrade.md):
  P0 no correction: 669.0k predicted vs 438.6k measured (53% miss);
  P0 F'=(1-0.33)F: 448.2k (2%); P0X split form: 894.3k vs ~818k (9%).
"""
import csv, os, sys
sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

def fnum(x):
    try: return float(x)
    except (TypeError, ValueError): return float("nan")

def unwrap(res, n=1):
    if isinstance(res, tuple):
        fig, a = res[0], res[1]
    elif hasattr(res, "savefig"):
        fig, a = res, list(res.axes)[:n]
    elif hasattr(res, "plot"):
        fig, a = res.figure, [res]
    else:
        raise TypeError(type(res))
    axs = a if hasattr(a, "__len__") else [a]
    return fig, list(axs)

SHORT = {"P0": "inline\n(co-loc)", "P0X": "inline\n(sep)", "P2": "thread\n(app core)",
         "P3": "thread\n(SMT)", "P4": "thread\n(other)"}

def main():
    # rows-fig1-3.csv is WHITESPACE-separated (p1_analyze.py output)
    lines = open(sys.argv[1]).read().splitlines()
    hdr = lines[0].split()
    rows = [dict(zip(hdr, ln.split())) for ln in lines[1:] if ln.strip()]
    out = sys.argv[2]
    RATE = 390000.0
    # C-006's independent measurement (literals from the claim row; the
    # same pattern as p1_figures.py fig2-knee-cdf carrying C-012's tier
    # constants)
    C006_LO, C006_HI, C006_MEAN = 26.0, 42.0, 33.0

    # ---- panel (a) data: hidden share at 390k, co-located app core ----
    reps, shares = [], []
    for r in rows:
        if (r["workload"] != "W1" or fnum(r["rate"]) != RATE
                or fnum(r["plen"]) != 64 or r["policy"] != "P0"):
            continue
        app, net = fnum(r.get("app_ns")), fnum(r.get("c_net_ns"))
        if app != app or net != net or (app + net) <= 0:
            continue
        reps.append(int(r["rep"]))
        shares.append(100.0 * net / (app + net))
    order = sorted(range(len(reps)), key=lambda i: reps[i])
    reps = [reps[i] for i in order]
    shares = [shares[i] for i in order]
    lo, hi, mean = min(shares), max(shares), sum(shares) / len(shares)
    ok = abs(lo - 25.0) <= 1.5 and abs(hi - 40.3) <= 1.5 and abs(mean - 32.2) <= 1.0
    print(f"anchor hidden share (rows, P0 390k, n={len(shares)}): "
          f"{lo:.1f}-{hi:.1f}% mean {mean:.1f}% (expect 25.0-40.3, mean 32.2) "
          f"{'OK' if ok else 'MISMATCH'}")
    print(f"anchor C-006 independent band: {C006_LO:.0f}-{C006_HI:.0f}% "
          f"mean {C006_MEAN:.0f}% (claim literals)")

    # ---- panel (b) data: the re-grade's with/without points ----
    pts = [("P0, F (no correction)", 438.6, 669.0, 53, PALETTE["red_strong"], "X",
            (-50, 4)),
           ("P0, F' = (1-h)F", 438.6, 448.2, 2, PALETTE["blue_main"], "o", (11, -5)),
           ("P0X, 1e9/max form", 818.0, 894.3, 9, PALETTE["teal"], "^", (-40, 2))]
    for nm, meas, pred, miss, c, m, off in pts:
        print(f"anchor model {nm}: predicted {pred} vs measured {meas} ({miss}% miss)")

    apply_publication_style()
    res = create_subplots(2, 1, figsize=(3.5, 4.4))
    fig, axs = unwrap(res, 2)

    # (a) hidden share: rows points over the independent band
    ax = axs[0]
    ax.axhspan(C006_LO, C006_HI, color=PALETTE["red_strong"], alpha=0.13, zorder=1)
    ax.axhline(C006_MEAN, linestyle=(0, (5, 2)), color=PALETTE["red_strong"],
               linewidth=1.2, zorder=2)
    ax.annotate(f"independent measurement: {C006_LO:.0f}-{C006_HI:.0f}%, "
                f"mean {C006_MEAN:.0f}% (C-006)",
                xy=(3.35, C006_HI), xytext=(0, 3), textcoords="offset points",
                ha="right", fontsize=6, color=PALETTE["red_strong"])
    ax.plot(reps, shares, "o", color=PALETTE["blue_main"], markersize=5, zorder=4)
    ax.plot([min(reps) - 0.25, max(reps) + 0.25], [mean, mean], "-",
            color=PALETTE["blue_main"], linewidth=1.8, zorder=3)
    ax.annotate(f"schedstat derivation: mean {mean:.1f}%",
                xy=(min(reps) - 0.28, 18.0), ha="left", fontsize=6,
                color=PALETTE["blue_main"])
    ax.set_xticks(reps)
    ax.set_xticklabels([f"rep {i}" for i in reps], fontsize=7)
    ax.set_xlim(min(reps) - 0.4, max(reps) + 0.4)
    ax.set_ylabel("hidden share (%)")
    ax.set_ylim(15, 55)
    ax.set_title("(a) hidden receive work on the app core (390k pps)", fontsize=8, pad=5)
    ax.grid(True, alpha=0.25, linewidth=0.6)

    # (b) model with/without correction
    ax = axs[1]
    ax.fill_between([350, 950], [350 / 1.25, 950 / 1.25], [350 * 1.25, 950 * 1.25],
                    color=PALETTE["neutral"], alpha=0.15, zorder=1)
    ax.plot([350, 950], [350, 950], "--", color=PALETTE["neutral"],
            linewidth=1.0, zorder=2)
    for nm, meas, pred, miss, c, m, off in pts:
        ax.plot([meas], [pred], m, color=c, markersize=6, zorder=5, label=nm)
        ax.annotate(f"{miss}%", xy=(meas, pred), xytext=off,
                    textcoords="offset points", fontsize=6.5, color=c)
    ax.annotate("y = x", xy=(905, 905), xytext=(-14, 4), textcoords="offset points",
                fontsize=6.5, color=PALETTE["neutral"])
    ax.annotate("+/-25%", xy=(880, 620), xytext=(0, 0), textcoords="offset points",
                fontsize=6.5, color=PALETTE["neutral"])
    ax.set_xlim(350, 950)
    ax.set_ylim(350, 950)
    ax.set_xlabel("measured knee (kQPS)")
    ax.set_ylabel("predicted knee (kQPS)")
    ax.set_title("(b) the model with and without the correction", fontsize=8, pad=5)
    ax.grid(True, alpha=0.25, linewidth=0.6)
    # the lower-right of the scatter (below the tolerance band) is empty
    axs[1].legend(loc="lower right", frameon=False, fontsize=6.5,
                  handlelength=1.2, labelspacing=0.3, borderaxespad=0.35)
    fig.subplots_adjust(hspace=0.45, left=0.20, right=0.97, top=0.93, bottom=0.13)
    print(finalize_figure(fig, os.path.join(out, "fig2-hiddenmodel"),
                          formats=["png", "pdf"], dpi=300))

if __name__ == "__main__":
    main()
