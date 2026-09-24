#!/usr/bin/env python3
"""p1_fig4.py -- Fig 4: predicted vs measured knee (model form F).

usage: .venv/bin/python analysis/p1_fig4.py rows1.csv [rows2.csv ...] outdir

Model (specs/p1-LADDER.md v2, form F; falsified by >25% miss):
    knee_pred(P0/P2) = 1e9 / (c_app + c_net)          one logical CPU
    knee_pred(P3)    = (2/s) * 1e9 / (c_app + c_net)  one physical core
    knee_pred(P4)    = 1e9 / max(c_app, c_net)        two cores
with per-packet costs (ns/pkt) measured in-situ at each placement's own
low-load full-delivery cells (the rows' app_ns and c_net_ns columns),
per packet size (64 / 512 / 1400 B), and s = the measured SMT slowdown
(calsmt.sh; default 1.24).

Measured knee: the highest offered rate sustaining mean delivered
fraction >= 0.95 (deliv), linearly interpolated across the bracketing
load points. Wedged reps count as failures at their rate (the wedge is a
real capacity collapse -- see AN-003; the model does not predict it).

Figure: scatter predicted vs measured with the y=x line and the +/-25%
falsification band. Rows are the p1_analyze.py tidy rows.
"""
import csv, math, os, random, sys

sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

POLICIES = ["P0", "P3", "P4"]
MARKERS = {"P0": "o", "P3": "v", "P4": "P"}
COLORS = {"P0": PALETTE["blue_main"], "P3": PALETTE["green_3"],
          "P4": PALETTE["teal"]}
PLEN_COLOR = {64: PALETTE["blue_main"], 512: PALETTE["green_3"],
              1400: PALETTE["red_strong"]}
SMT = float(os.environ.get("SMT", "1.24"))
DELIV_PASS = 0.95


def fnum(x, d=float("nan")):
    try:
        return float(x)
    except (TypeError, ValueError):
        return d


def read_rows(paths):
    merged = {}
    for path in paths:
        with open(path) as f:
            for r in csv.DictReader(f, delimiter=" "):
                merged[(r["policy"], r["workload"], r["rate"], r["rep"],
                        r["plen"])] = r
    rows = []
    for r in merged.values():
        live = fnum(r.get("goodput")) > 0 or fnum(r.get("sockdrops")) > 0
        if live:
            rows.append(r)
    return rows


def mean_deliv(rows, pol, plen, rate):
    vals = [fnum(r.get("deliv")) for r in rows
            if r["policy"] == pol and r["workload"] == "W1"
            and int(fnum(r["plen"])) == plen and fnum(r["rate"]) == rate
            and fnum(r.get("deliv")) == fnum(r.get("deliv"))]
    return (sum(vals) / len(vals)) if vals else None


def measured_knee(rows, pol, plen):
    """highest rate with mean deliv >= DELIV_PASS, interpolated."""
    rates = sorted({fnum(r["rate"]) for r in rows
                    if r["policy"] == pol and int(fnum(r["plen"])) == plen})
    if not rates:
        return None
    best = None
    for a, b in zip(rates, rates[1:]):
        da, db = mean_deliv(rows, pol, plen, a), mean_deliv(rows, pol, plen, b)
        if da is None or db is None:
            continue
        if da >= DELIV_PASS > db:  # crossing between a and b
            t = (da - DELIV_PASS) / (da - db)
            return a + t * (b - a)
        if da >= DELIV_PASS:
            best = a
    last = rates[-1]
    dl = mean_deliv(rows, pol, plen, last)
    if dl is not None and dl >= DELIV_PASS:
        return last  # knee above the grid: censored (marked hollow)
    return best


def costs(rows, pol, plen):
    """in-situ c_app, c_net (ns/pkt): mean over full-delivery low-load
    cells of this placement and size."""
    app, net = [], []
    for r in rows:
        if (r["policy"] != pol or r["workload"] != "W1"
                or int(fnum(r["plen"])) != plen):
            continue
        if fnum(r.get("deliv")) < DELIV_PASS:
            continue
        a, n = fnum(r.get("app_ns")), fnum(r.get("c_net_ns"))
        if a == a and n == n and a > 0 and n > 0:
            app.append(a)
            net.append(n)
    if not app:
        return None, None
    return sum(app) / len(app), sum(net) / len(net)


def knee_pred(pol, c_app, c_net):
    if pol in ("P0", "P2"):
        return 1e9 / (c_app + c_net)
    if pol == "P3":
        return (2.0 / SMT) * 1e9 / (c_app + c_net)
    if pol == "P4":
        return 1e9 / max(c_app, c_net)
    return float("nan")


def main():
    paths, out = sys.argv[1:-1], sys.argv[-1]
    rows = read_rows(paths)
    os.makedirs(out, exist_ok=True)
    apply_publication_style()
    fig, ax = create_subplots(figsize=(3.5, 2.9))
    pts = []
    for plen in (64, 512, 1400):
        for pol in POLICIES:
            mk = measured_knee(rows, pol, plen)
            c_app, c_net = costs(rows, pol, plen)
            if mk is None or c_app is None:
                print(f"pending: plen={plen} pol={pol} "
                      f"(knee {'ok' if mk else 'missing'}, "
                      f"costs {'ok' if c_app else 'missing'})")
                continue
            pred = knee_pred(pol, c_app, c_net)
            err = abs(pred - mk) / mk
            pts.append((plen, pol, mk, pred, err))
            print(f"plen={plen} {pol}: measured {mk:.0f}  pred {pred:.0f}  "
                  f"err {100 * err:.0f}%  (c_app {c_app:.0f}, c_net "
                  f"{c_net:.0f}, s={SMT})")
    if not pts:
        print("no complete cells yet -- figure skipped")
        return
    for plen, pol, mk, pred, err in pts:
        ax.scatter([pred], [mk], marker=MARKERS[pol], s=55,
                   color=PLEN_COLOR[plen], edgecolors="black", linewidths=0.5,
                   zorder=3,
                   label=f"{plen} B" if pol == "P0" else None)
    lo = min(min(p[2], p[3]) for p in pts) * 0.6
    hi = max(max(p[2], p[3]) for p in pts) * 1.6
    ax.plot([lo, hi], [lo, hi], "-", color="0.4", lw=1.0, zorder=2)
    ax.fill_between([lo, hi], [v / 1.25 for v in (lo, hi)],
                    [v * 1.25 for v in (lo, hi)], color=PALETTE["neutral"],
                    alpha=0.25, linewidth=0, zorder=1,
                    label="model +-25%")
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(lo, hi)
    ax.set_ylim(lo, hi)
    ax.set_xlabel("predicted knee (pps)")
    ax.set_ylabel("measured knee (pps)")
    ax.legend(loc="upper left", fontsize=7)
    falsified = [p for p in pts if p[4] > 0.25]
    for plen, pol, mk, pred, err in falsified:
        ax.annotate(f"{pol}/{plen}B +{100 * (pred / mk - 1):.0f}%",
                    xy=(pred, mk), xytext=(4, -8), textcoords="offset points",
                    fontsize=6, color=PALETTE["red_strong"])
    verdict = ("FORM F FALSIFIED: " +
               ", ".join(f"{p[1]}/{p[0]}B {100 * p[4]:.0f}%" for p in falsified)
               ) if falsified else "form F holds (all within 25%)"
    print("verdict:", verdict)
    saved = finalize_figure(fig, os.path.join(out, "fig4"),
                            formats=["png", "pdf"])
    for p in saved:
        print("wrote", p)


if __name__ == "__main__":
    main()
