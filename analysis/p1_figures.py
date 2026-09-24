#!/usr/bin/env python3
"""p1_figures.py -- Paper 1 figures (house style: figures4papers).

usage: .venv/bin/python analysis/p1_figures.py rows1.csv [rows2.csv ...] outdir

Rows come from p1_analyze.py (whitespace CSV, one file per results tag).
Multiple row files merge (fig1-3 matrix + fig1-3b/fig1-3c re-runs + smoke).
Duplicated (policy,workload,rate,rep) keys: the LAST file wins (re-runs
supersede). Runs with consumed=0 (the concurrent-driver kill windows) are
dropped here, not in the analyzer.

Style contract (figures4papers-style skill): figstyle.apply_publication_style,
PALETTE, finalize_figure -> PNG+PDF at 300 dpi, frameless legends, spines
top/right off. Asymmetric bootstrap 95% intervals are drawn as errorbars
rather than symmetric bands (3-rep CIs are asymmetric; make_trend's band
API would shift them).

  Fig 1  goodput vs offered/knee, one line per policy (W1), wedge markers
  Fig 2  low-rate round-trip p50/p99 per policy (grouped bars + CI)
  Fig 3  CPU time per packet: thread accounting vs actual core time
"""
import csv, os, random, sys

sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

POL_ORDER = ["P0", "P1", "P0X", "P2", "P3", "P4", "P7"]
POL_LABEL = {"P0": "inline (default)", "P1": "same-core deferral (pre-6.5)",
             "P0X": "inline, app elsewhere", "P2": "thread, app core",
             "P3": "thread, SMT sibling", "P4": "thread, other core",
             "P7": "ladder"}
COLORS = {"P0": PALETTE["blue_main"], "P1": PALETTE["neutral"],
          "P0X": PALETTE["blue_secondary"], "P2": PALETTE["red_strong"],
          "P3": PALETTE["green_3"], "P4": PALETTE["teal"],
          "P7": PALETTE["violet"]}
MARKERS = {"P0": "o", "P1": "s", "P0X": "^", "P2": "D", "P3": "v", "P4": "P",
           "P7": "*"}
LINES = {"P0": "-", "P1": (0, (5, 2)), "P0X": (0, (1, 1.2)),
         "P2": (0, (4, 1.5)), "P3": (0, (6, 2, 1, 2)), "P4": "-.",
         "P7": (0, (3, 1, 1, 1))}
POL_SHORT = {"P0": "inline", "P1": "deferral", "P0X": "inline sep.app",
             "P2": "thr app-core", "P3": "thr sibling", "P4": "thr other",
             "P7": "ladder"}


def fnum(x, d=float("nan")):
    try:
        return float(x)
    except (TypeError, ValueError):
        return d


def read_rows(paths):
    """Merge row files; later files supersede same (policy,work,rate,rep).
    Drops (a) runs with no live consumer summary: the concurrent-driver
    victims leave all-zero rows (goodput=0, sockdrops=0), while wedged
    runs keep their huge sockdrops and stay; (b) the first matrix's W1
    rows for non-P0 policies (the flow-split class -- only fig1-3b/c and
    smoke46 rows may source those cells)."""
    merged = {}
    for path in paths:
        with open(path) as f:
            for r in csv.DictReader(f, delimiter=" "):
                key = (r.get("policy"), r.get("workload"), r.get("rate"),
                       r.get("rep"))
                merged[key] = r
    rows, dropped = [], 0
    for r in merged.values():
        live = fnum(r.get("goodput")) > 0 or fnum(r.get("sockdrops")) > 0
        flowsplit = (r.get("tag") == "fig1-3" and r.get("workload") == "W1"
                     and r.get("policy") != "P0")
        if live and not flowsplit:
            rows.append(r)
        else:
            dropped += 1
    return rows, dropped


def ci(vals, n=10000, seed=7):
    """mean and percentile 95% bootstrap CI (asymmetric)."""
    if not vals:
        return float("nan"), float("nan"), float("nan")
    rng = random.Random(seed)
    means = sorted(sum(vals[rng.randrange(len(vals))] for _ in vals) / len(vals)
                   for _ in range(n))
    return sum(vals) / len(vals), means[int(0.025 * n)], means[int(0.975 * n)]


def collect(rows, pol, work, key, rate=None):
    out = {}
    for r in rows:
        if r["policy"] != pol or r["workload"] != work:
            continue
        if rate is not None and fnum(r["rate"]) != rate:
            continue
        v = fnum(r.get(key))
        if v == v:
            out.setdefault(fnum(r["rate"]), []).append(v)
    return out


def fig1(rows, out, knee):
    fig, ax = create_subplots(figsize=(3.5, 2.7))
    for pol in POL_ORDER:
        pts = collect(rows, pol, "W1", "goodput")
        if not pts:
            continue
        xs, ys, lo, hi = [], [], [], []
        for rate in sorted(pts):
            m, l, h = ci(pts[rate])
            xs.append(rate / knee)
            ys.append(m)
            lo.append(m - l)
            hi.append(h - m)
        ax.errorbar(xs, ys, yerr=[lo, hi], marker=MARKERS[pol], ms=5, lw=1.6,
                    color=COLORS[pol], label=POL_LABEL[pol], capsize=2,
                    linestyle=LINES[pol],
                    markerfacecolor=COLORS[pol], markeredgecolor="white",
                    markeredgewidth=0.6)
        # wedge evidence: offered >> delivered collapses
        j = POL_ORDER.index(pol)
        wedged = [x for x, y in zip(xs, ys) if y < 0.2 * x * knee]
        if wedged:
            ax.scatter(wedged, [(0.015 + 0.012 * j) * knee] * len(wedged),
                       marker="x", color=COLORS[pol], s=28, zorder=4)
    ax.plot([0, 2.6], [0, 2.6 * knee], ":", color="0.55", lw=1.0,
            label="offered")
    ax.set_xlabel("offered rate / knee")
    ax.set_ylabel("goodput (pps)")
    ax.set_ylim(bottom=0)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.22), ncol=3,
              fontsize=7)
    return finalize_figure(fig, os.path.join(out, "fig1"),
                           formats=["png", "pdf"])


def fig2(rows, out):
    """Low-rate W2 round trip (25k rps request/echo): p50 and p99 bars."""
    pols = [p for p in POL_ORDER
            if any(r["policy"] == p and r["workload"] == "W2" for r in rows)]
    if not pols:
        return []
    fig, ax = create_subplots(figsize=(3.5, 2.7))
    w = 0.36
    for j, (key, label) in enumerate([("lat_p50", "p50"), ("lat_p99", "p99")]):
        ys, es = [], []
        for p in pols:
            vals = [v for v in
                    (fnum(r.get(key)) for r in rows
                     if r["policy"] == p and r["workload"] == "W2")
                    if v == v]
            m, l, h = ci(vals)
            ys.append(m)
            es.append((max(m - l, 0), max(h - m, 0)))
        off = (-0.2 + 0.4 * j)
        bars = ax.bar([x + off for x in range(len(pols))], ys, width=w,
                      color=PALETTE["blue_main"] if j == 0 else PALETTE["green_3"],
                      label=label, edgecolor="black", lw=0.6, zorder=3)
        ax.errorbar([x + off for x in range(len(pols))], ys,
                    yerr=list(zip(*es)), fmt="none", ecolor="black", capsize=2,
                    lw=0.8, zorder=4)
    ax.set_xticks(range(len(pols)))
    ax.set_xticklabels([POL_SHORT[p] for p in pols], rotation=15, ha="right",
                       fontsize=8)
    ax.set_ylabel("round trip (us)")
    ax.set_ylim(bottom=0, top=ax.get_ylim()[1] * 1.35)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, 1.06), ncol=2,
              fontsize=8)
    return finalize_figure(fig, os.path.join(out, "fig2"),
                           formats=["png", "pdf"])


def fig3(rows, out, rate=390000.0):
    """CPU ns/pkt at ONE load (390k, full delivery): schedstat-visible
    app-thread time vs real core time (the softirq work the scheduler
    never attributes). Averaging across loads mixes collapsed runs whose
    tiny denominators explode per-packet costs."""
    pols = [p for p in POL_ORDER
            if any(r["policy"] == p and r["workload"] == "W1"
                   and fnum(r["rate"]) == rate for r in rows)]
    if not pols:
        return []
    fig, ax = create_subplots(figsize=(3.5, 2.7))
    app, hidden = [], []
    for p in pols:
        a, h = [], []
        for r in rows:
            if (r["policy"] != p or r["workload"] != "W1"
                    or fnum(r["rate"]) != rate):
                continue
            tot = fnum(r.get("cpu8_busy_s"))
            ap = fnum(r.get("app_ns"))
            pk = fnum(r.get("goodput")) * 60.0
            if tot != tot or ap != ap or not pk:
                continue
            a.append(ap)
            h.append(max(tot * 1e9 / pk - ap, 0))
        app.append(sum(a) / len(a) if a else 0.0)
        hidden.append(sum(h) / len(h) if h else 0.0)
    x = range(len(pols))
    ax.bar(x, app, color=PALETTE["blue_secondary"], edgecolor="black", lw=0.6,
           label="thread-accounted (schedstat)", zorder=3)
    ax.bar(x, hidden, bottom=app, color=PALETTE["red_strong"],
           edgecolor="black", lw=0.6, label="unaccounted on the core",
           zorder=3)
    for xi, (a, h) in enumerate(zip(app, hidden)):
        ax.annotate(f"{a + h:.0f}", xy=(xi, a + h), xytext=(0, 2),
                    textcoords="offset points", ha="center", fontsize=7)
    ax.set_xticks(list(x))
    ax.set_xticklabels([POL_SHORT[p] for p in pols], rotation=15, ha="right",
                       fontsize=8)
    ax.set_ylabel("CPU time per packet (ns)")
    ax.set_ylim(bottom=0, top=max(a + h for a, h in zip(app, hidden)) * 1.2)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, 1.06), ncol=2,
              fontsize=8)
    return finalize_figure(fig, os.path.join(out, "fig3"),
                           formats=["png", "pdf"])


def verify_anchors(rows):
    """Cross-check parsed rows against the numbers recorded in the
    checkpoint notes before anything is plotted (skill rule)."""
    def median_pol(pol, work, rate, key):
        vals = sorted(v for v in
                      (fnum(r.get(key)) for r in rows
                       if r["policy"] == pol and r["workload"] == work
                       and fnum(r["rate"]) == rate) if v == v)
        return vals[len(vals) // 2] if vals else float("nan")

    checks = []
    # checkpoint 2026-09-24-fig1-3-forensics: P0 knee 525-600k at 64B
    # (matrix loads are 130/390/525/790/1050/1300k -- 450k was cal-1 only)
    p0 = {r_: [fnum(r.get("deliv")) for r in rows
               if r["policy"] == "P0" and r["workload"] == "W1"
               and fnum(r["rate"]) == r_] for r_ in (390000.0, 790000.0)}
    ok = (p0[390000.0] and sum(p0[390000.0]) / len(p0[390000.0]) >= 0.95
          and p0[790000.0] and sum(p0[790000.0]) / len(p0[790000.0]) < 0.5)
    checks.append(("P0 knee bracket 390k good / 790k collapsed", ok))
    # smoke46 full-delivery latency nugget: p50 ~11us P0X vs ~108us P0 @130k
    x = median_pol("P0X", "W1", 130000.0, "lat_p50")
    y = median_pol("P0", "W1", 130000.0, "lat_p50")
    if x == x and y == y:
        checks.append((f"low-rate p50 P0X {x:.0f}us < P0 {y:.0f}us", x < y))
    for name, ok in checks:
        print(("VERIFIED " if ok else "MISMATCH ") + name)
    return all(ok for _, ok in checks)


def main():
    paths, out = sys.argv[1:-1], sys.argv[-1]
    rows, dropped = read_rows(paths)
    print(f"merged {len(rows)} rows (dropped {dropped} invalid runs)")
    os.makedirs(out, exist_ok=True)
    apply_publication_style()
    verify_anchors(rows)
    knee = 525000.0
    by_rate = {}
    for r in rows:
        if r["workload"] == "W1" and r["policy"] == "P0":
            by_rate.setdefault(fnum(r["rate"]), []).append(fnum(r["deliv"]))
    for rate in sorted(by_rate):
        if sum(by_rate[rate]) / len(by_rate[rate]) >= 0.95:
            knee = rate
    print(f"knee (P0, W1): {knee:.0f} pps at mean deliv>=0.95")
    for fn in (fig1, fig2, fig3):
        if fn is fig1:
            saved = fn(rows, out, knee)
        else:
            saved = fn(rows, out)
        for p in saved or []:
            print("wrote", p)


if __name__ == "__main__":
    main()
