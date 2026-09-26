#!/usr/bin/env python3
"""p1_fig_model.py -- the workshop paper's Fig. 2 (DR-005 decisions 2+4):
the standard metric is blind, and corrected costs make the knee predictable.

usage: .venv/bin/python analysis/p1_fig_model.py analysis/rows-fig13-merged.csv outdir

v2 (2026-09-25, DR-005): the "hidden share" framing is retired ("Replace
'hidden share' throughout"). The message is now: the standard metric is
blind; correct metrics make the knee predictable within 3-6%; the model
fails on TCP, where cost depends on load.

Panel (a): what each metric sees of the real per-packet receive cost at
390k pps / 64 B. Anchors (FINDINGS p1-LADDER.4, task1b, 3 reps/placement):
  real (PMU-basis) per-packet system CPU 2026-2935 ns across placements;
  app thread schedstat 906-1407 ns -> the thread sees 43-55% (the claim's
  recorded range; per-placement means 44.7-50.2%);
  /proc/stat sees 0.6% of receive work on an interrupt-only core
  (AN-007: 0.22 s stat against 36.53 s PMU = 0.60%).
Panel (b): predicted vs measured knee from the corrected per-packet costs.
Anchors (FINDINGS p1-LADDER.4; W3 notes/p1-W3.md):
  P0 (co-located) 451.0k predicted vs 438.6k measured (2.8% miss);
  P0X (separated) 767k vs 818k (6.2% miss); both UDP 64 B, no fitted
  constant. TCP (C-017, Refuted): predicted 62.0k/82.4k vs measured
  190k/260k (3.06x/3.16x) -- TCP per-request cost falls with load.
"""
import os, sys
for _p in ("/home/david/workspace/flowlet-eval/figures",
           "/mnt/davidlin-personal/flowlet-eval/figures"):
    if os.path.isdir(_p):
        sys.path.insert(0, _p)
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
    # rows-fig13-merged.csv is WHITESPACE-separated (p1_analyze.py output)
    lines = open(sys.argv[1]).read().splitlines()
    hdr = lines[0].split()
    rows = [dict(zip(hdr, ln.split())) for ln in lines[1:] if ln.strip()]
    out = sys.argv[2]
    RATE = 390000.0

    # ---- panel (a) data: the task1b corrected costs at 390k/64B ----
    pols, agg = [], {}
    for r in rows:
        if (r["tag"] != "task1b" or fnum(r["rate"]) != RATE
                or fnum(r["plen"]) != 64):
            continue
        app, net = fnum(r.get("app_ns")), fnum(r.get("c_net_ns"))
        if app != app or net != net or (app + net) <= 0:
            continue
        agg.setdefault(r["policy"], []).append((app, net))
    pols = [p for p in ["P0", "P0X", "P2", "P3", "P4"] if p in agg]
    means = {p: (sum(a for a, _ in v) / len(v), sum(n for _, n in v) / len(v))
             for p, v in agg.items()}
    app_lo = min(a for a, _ in means.values())
    app_hi = max(a for a, _ in means.values())
    tot_lo = min(a + n for a, n in means.values())
    tot_hi = max(a + n for a, n in means.values())
    shares = [100.0 * a / (a + n) for p in pols for a, n in agg[p]]
    ok = (abs(app_lo - 906) <= 2 and abs(app_hi - 1407) <= 2
          and abs(tot_lo - 2026) <= 3 and abs(tot_hi - 2935) <= 3)
    print(f"anchor task1b 390k: app {app_lo:.0f}-{app_hi:.0f} (expect 906-1407), "
          f"real {tot_lo:.0f}-{tot_hi:.0f} (expect 2026-2935) {'OK' if ok else 'MISMATCH'}")
    print(f"anchor thread share: per-placement means "
          f"{min(100*a/(a+n) for a,n in means.values()):.1f}-"
          f"{max(100*a/(a+n) for a,n in means.values()):.1f}%, per-rep "
          f"{min(shares):.1f}-{max(shares):.1f}% (claim range 43-55%)")
    stat_pct = 100.0 * 0.22 / 36.53
    print(f"anchor /proc/stat share: {stat_pct:.2f}% (expect 0.6, AN-007)")

    # ---- panel (b) data: the corrected-cost model ----
    pts = [("P0, UDP 64 B", 438.6, 451.0, "2.8%", PALETTE["blue_main"], "o", (8, -12)),
           ("P0X, UDP 64 B", 818.0, 767.0, "6.2%", PALETTE["teal"], "^", (-8, -16)),
           ("P0, TCP", 190.0, 62.0, "3.06x", PALETTE["red_strong"], "X", (8, -4)),
           ("P0X, TCP", 260.0, 82.4, "3.16x", PALETTE["red_strong"], "X", (8, -4))]
    for nm, meas, pred, miss, c, m, off in pts:
        print(f"anchor model {nm}: predicted {pred} vs measured {meas} ({miss})")

    apply_publication_style()
    res = create_subplots(2, 1, figsize=(3.5, 4.9))
    fig, axs = unwrap(res, 2)

    # (a) what each metric sees
    ax = axs[0]
    metrics = [("/proc/stat (this kernel)", stat_pct, PALETTE["red_strong"]),
               ("thread accounting (schedstat)", 47.5, PALETTE["blue_main"]),
               ("PMU busy (corrected metric)", 100.0, PALETTE["teal"])]
    for i, (lab, val, col) in enumerate(metrics):
        if lab.startswith("thread"):
            ax.barh(i, 55 - 43, left=43, color=col, edgecolor="black",
                    lw=0.6, height=0.5, zorder=3)
            ax.annotate("43-55%", xy=(55, i), xytext=(3, 0),
                        textcoords="offset points", va="center", fontsize=6.5)
        else:
            ax.barh(i, val, color=col, edgecolor="black", lw=0.6,
                    height=0.5, zorder=3)
            ax.annotate(f"{val:.1f}%".replace(".0%", "%"), xy=(val, i),
                        xytext=(3, 0), textcoords="offset points",
                        va="center", fontsize=6.5)
    ax.set_yticks(range(len(metrics)))
    ax.set_yticklabels([m[0] for m in metrics], fontsize=6.5)
    ax.set_xlim(0, 118)
    ax.set_xlabel("share of real per-packet cost seen (%)")
    ax.set_title("(a) the standard metric is blind (390k pps, 64 B)", fontsize=8, pad=5)
    ax.grid(True, axis="x", alpha=0.25, linewidth=0.6)

    # (b) predicted vs measured knee, corrected costs
    ax = axs[1]
    ax.fill_between([40, 1000], [32, 800], [50, 1250],
                    color=PALETTE["neutral"], alpha=0.15, zorder=1)
    ax.plot([40, 1000], [40, 1000], "--", color=PALETTE["neutral"],
            linewidth=1.0, zorder=2)
    for nm, meas, pred, miss, c, m, off in pts:
        ax.plot([meas], [pred], m, color=c, markersize=6, zorder=5, label=nm)
        ax.annotate(miss, xy=(meas, pred), xytext=off,
                    textcoords="offset points", fontsize=6.5, color=c)
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(40, 1100)
    ax.set_ylim(40, 1200)
    ax.set_xticks([50, 100, 200, 1000])
    ax.set_yticks([50, 100, 200, 1000])
    ax.get_xaxis().set_major_formatter(lambda v, p: f"{int(v)}")
    ax.get_yaxis().set_major_formatter(lambda v, p: f"{int(v)}")
    from matplotlib.ticker import NullFormatter
    ax.xaxis.set_minor_formatter(NullFormatter())
    ax.yaxis.set_minor_formatter(NullFormatter())
    ax.set_xlabel("measured knee (kQPS)")
    ax.set_ylabel("predicted knee (kQPS)")
    ax.set_title("(b) corrected costs predict the knee -- UDP only", fontsize=8, pad=5)
    ax.grid(True, alpha=0.25, linewidth=0.6, which="both")
    # the tolerance band's lower-right triangle is empty on a log-log plot
    ax.legend(loc="upper left", frameon=False, fontsize=6.5,
              handlelength=1.2, labelspacing=0.3, borderaxespad=0.35)
    ax.annotate("+/-25% of measured", xy=(1050, 270), ha="right",
                fontsize=6, color=PALETTE["neutral"])
    fig.subplots_adjust(hspace=0.78, left=0.30, right=0.97, top=0.95, bottom=0.10)
    print(finalize_figure(fig, os.path.join(out, "fig2-metricmodel"),
                          formats=["png", "pdf"], dpi=300))

if __name__ == "__main__":
    main()
