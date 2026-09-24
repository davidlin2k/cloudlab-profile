#!/usr/bin/env python3
"""p1_fig6.py -- Fig 6: goodput under SLO and p99 against load, the
ladder (P7) against every static policy (skeleton row: "Goodput under
SLO and p99 against load, the ladder against every static policy" --
claim C1/D2: "Within 10% of the best static rung at every load").

usage: .venv/bin/python analysis/p1_fig6.py OUTDIR ROWS_CSV...
Rows: p1_analyze.py tidy rows (tag cell policy workload rate plen rep
gates_ok offered goodput deliv lat_p50 lat_p90 lat_p99 lat_p999
under_slo ... snd_full). Goodput under SLO = goodput * under_slo.

Verify-before-plot: rows are filtered and COUNTED (generator-budget:
0.95 <= offered/rate <= 1.05; sender full-span: snd_full == 5; zero
goodput rows dropped) and later tags supersede earlier (policy, work,
rate, rep). The claim check prints per-load gaps and a verdict --
WITHIN 10% or the violating loads named. Never silently asserted.
"""
import csv, sys
from collections import defaultdict

sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

POLICIES = ["P0", "P2", "P3", "P4", "P7"]
COLORS = {"P0": PALETTE["blue_main"], "P2": PALETTE["red_strong"],
          "P3": PALETTE["amber"], "P4": PALETTE["teal"],
          "P7": PALETTE["violet"]}


def read_rows(paths):
    merged = {}
    for path in paths:
        for r in csv.DictReader(open(path), delimiter=" "):
            merged[(r["policy"], r["workload"], r["rate"], r["rep"])] = r
    kept, dropped = [], defaultdict(int)
    for r in merged.values():
        try:
            rate = float(r["rate"])
            offered = float(r["offered"])
            goodput = float(r["goodput"])
            under = float(r["under_slo"])
            p99 = float(r["lat_p99"])
            snd_full = int(r.get("snd_full", 5))
        except (ValueError, KeyError):
            dropped["parse"] += 1
            continue
        if snd_full < 5:
            dropped["snd_full"] += 1
            continue
        if not (0.95 <= offered / rate <= 1.05):
            dropped["generator-budget"] += 1
            continue
        if goodput <= 0:
            dropped["zero-goodput"] += 1
            continue
        kept.append(dict(policy=r["policy"], work=r["workload"], rate=rate,
                         goodput=goodput, gu_slo=goodput * under,
                         under=under, p99=p99))
    print(f"rows kept {len(kept)} dropped {dict(dropped)}")
    return kept


def main():
    outdir = sys.argv[1]
    rows = read_rows(sys.argv[2:])
    if not rows:
        print("no rows -- figure skipped")
        return
    works = ["W1", "W2"]
    apply_publication_style()
    fig, axes = create_subplots(len(works), 2, figsize=(7.2, 5.4))
    for rw, work in enumerate(works):
        ax1, ax2 = axes[rw]
        by = defaultdict(list)
        for r in rows:
            if r["work"] == work:
                by[r["policy"]].append(r)
        for pol in POLICIES:
            pts = sorted(by.get(pol, []), key=lambda r: r["rate"])
            if not pts:
                continue
            xs = [p["rate"] for p in pts]
            ax1.plot(xs, [p["gu_slo"] for p in pts], "o-", ms=3,
                     color=COLORS.get(pol, "0.4"),
                     lw=2.0 if pol == "P7" else 1.0, label=pol)
            ax2.plot(xs, [p["p99"] for p in pts], "o-", ms=3,
                     color=COLORS.get(pol, "0.4"),
                     lw=2.0 if pol == "P7" else 1.0, label=pol)
        ax1.set_title(f"{work}: goodput under SLO vs load", fontsize=8)
        ax1.set_ylabel("packets/s under SLO")
        ax2.set_title(f"{work}: p99 vs load", fontsize=8)
        ax2.set_ylabel("p99 (us)")
        ax2.set_yscale("log")
        for ax in (ax1, ax2):
            ax.set_xlabel("offered load (packets/s)")
        # claim check: P7 within 10% of the best static at EVERY load
        loads = sorted({r["rate"] for r in rows if r["work"] == work})
        bad = []
        for ld in loads:
            def best(pol):
                pts = [r["gu_slo"] for r in rows
                       if r["work"] == work and r["policy"] == pol
                       and r["rate"] == ld]
                return sum(pts) / len(pts) if pts else None
            statics = [best(p) for p in ("P0", "P2", "P3", "P4")]
            statics = [s for s in statics if s is not None]
            p7 = best("P7")
            if not statics or p7 is None:
                continue
            b = max(statics)
            gap = (b - p7) / b if b else float("nan")
            verdict = "ok" if gap <= 0.10 else "MISS"
            print(f"CLAIM {work} load={ld:.0f}: best-static {b:.0f} "
                  f"P7 {p7:.0f} gap={gap*100:.1f}% {verdict}")
            if gap > 0.10:
                bad.append(ld)
        print(f"CLAIM VERDICT {work}: " +
              ("WITHIN 10% at every load" if not bad else
               f"violates at loads {bad}"))
    axes[0][0].legend(fontsize=7, ncol=5)
    for p in finalize_figure(fig, f"{outdir}/fig6", formats=["png", "pdf"]):
        print("wrote", p)


if __name__ == "__main__":
    main()
