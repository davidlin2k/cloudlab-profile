#!/usr/bin/env python3
"""p1_figures.py -- Paper 1 figures from p1_analyze.py tidy rows.

usage: .venv/bin/python analysis/p1_figures.py rows.csv outdir [slo_us]
Input: the whitespace rows printed by p1_analyze.py (header first).
Bootstrap 95% CIs over reps (10 resamples of the mean are NOT enough:
10k resamples, seeded). Emits PNG+PDF per figure.

  Fig 1  goodput vs offered/knee, one line per policy (W1)
  Fig 2  low-rate W2 round-trip p50/p99 per policy (bar + CI)
  Fig 3  CPU time per packet: core vs thread accounting per policy
"""
import csv, random, sys, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

POL_ORDER = ["P0", "P1", "P0X", "P2", "P3", "P4", "P7"]
POL_LABEL = {"P0": "inline (default)", "P1": "same-core deferral (pre-6.5)",
             "P0X": "inline, app elsewhere", "P2": "thread, app core",
             "P3": "thread, SMT sibling", "P4": "thread, other core",
             "P7": "ladder"}
COLORS = {"P0": "#000000", "P1": "#888888", "P0X": "#bbbbbb",
          "P2": "#d55e00", "P3": "#0072b2", "P4": "#009e73", "P7": "#cc79a7"}

def read_rows(path):
    rows = []
    with open(path) as f:
        rd = csv.DictReader(f, delimiter=" ")
        for r in rd:
            rows.append(r)
    return rows

def ci(vals, n=10000, seed=7):
    if not vals:
        return (float("nan"),) * 3
    rng = random.Random(seed)
    means = []
    for _ in range(n):
        s = [vals[rng.randrange(len(vals))] for _ in vals]
        means.append(sum(s) / len(s))
    means.sort()
    m = sum(vals) / len(vals)
    return m, means[int(0.025 * n)], means[int(0.975 * n)]

def fnum(x, d=float("nan")):
    try:
        return float(x)
    except (TypeError, ValueError):
        return d

def fig1(rows, out, knee):
    plt.rcParams.update({"font.size": 9})
    fig, ax = plt.subplots(figsize=(3.4, 2.6))
    for pol in POL_ORDER:
        pts = {}
        for r in rows:
            if r["policy"] != pol or r["workload"] != "W1":
                continue
            pts.setdefault(fnum(r["rate"]), []).append(fnum(r["goodput"]))
        if not pts:
            continue
        xs, ys, es = [], [], []
        for rate in sorted(pts):
            m, lo, hi = ci(pts[rate])
            xs.append(rate / knee)
            ys.append(m)
            es.append((m - lo, hi - m))
        ax.errorbar(xs, ys, yerr=list(zip(*es)), marker="o", ms=3, lw=1.2,
                    color=COLORS[pol], label=POL_LABEL[pol], capsize=2)
    ax.plot([0, 2.6], [0, 2.6 * knee], ":", color="0.6", lw=0.8,
            label="offered")
    ax.set_xlabel("offered rate / knee")
    ax.set_ylabel("goodput (pps)")
    ax.legend(fontsize=6.5, frameon=False)
    ax.grid(alpha=0.25)
    fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(os.path.join(out, f"fig1.{ext}"))
    plt.close(fig)

def fig2(rows, out):
    fig, ax = plt.subplots(figsize=(3.4, 2.6))
    pols = [p for p in POL_ORDER
            if any(r["policy"] == p and r["workload"] == "W2" for r in rows)]
    xs = range(len(pols))
    for j, (key, label, hatch) in enumerate([("lat_p50", "p50", ""),
                                             ("lat_p99", "p99", "//")]):
        ys, es = [], []
        for p in pols:
            vals = [fnum(r[key]) for r in rows
                    if r["policy"] == p and r["workload"] == "W2"]
            vals = [v for v in vals if v == v]
            m, lo, hi = ci(vals)
            ys.append(m)
            es.append((m - lo, hi - m))
        off = -0.2 + 0.4 * j
        ax.bar([x + off for x in xs], ys, width=0.36, yerr=list(zip(*es)),
               capsize=2, color=COLORS[p] if j else "0.7", hatch=hatch,
               label=label, edgecolor="k", lw=0.4)
    ax.set_xticks(list(xs))
    ax.set_xticklabels([POL_LABEL[p] for p in pols], rotation=25, ha="right",
                       fontsize=6.5)
    ax.set_ylabel("round trip (us)")
    ax.legend(fontsize=7, frameon=False)
    ax.grid(alpha=0.25, axis="y")
    fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(os.path.join(out, f"fig2.{ext}"))
    plt.close(fig)

def fig3(rows, out):
    """CPU ns/pkt split: app thread (schedstat) vs everything else on the
    app core (the softirq work the scheduler does not see)."""
    fig, ax = plt.subplots(figsize=(3.4, 2.6))
    pols = [p for p in POL_ORDER
            if any(r["policy"] == p and r["workload"] == "W1" for r in rows)]
    xs = range(len(pols))
    app, hidden = [], []
    for p in pols:
        a, h = [], []
        for r in rows:
            if r["policy"] != p or r["workload"] != "W1":
                continue
            tot = fnum(r["cpu8_busy_s"])
            ap = fnum(r["app_ns"])
            if tot != tot or ap != ap:
                continue
            pk = fnum(r["goodput"]) * 60.0 or 1.0
            a.append(ap)
            h.append(max(tot * 1e9 / pk - ap, 0))
        if a:
            app.append(sum(a) / len(a))
            hidden.append(sum(h) / len(h) if h else 0)
        else:
            app.append(0); hidden.append(0)
    ax.bar(xs, app, color="0.65", label="app thread (schedstat)", edgecolor="k", lw=0.4)
    ax.bar(xs, hidden, bottom=app, color="#d55e00", label="hidden softirq work",
           edgecolor="k", lw=0.4)
    ax.set_xticks(list(xs))
    ax.set_xticklabels([POL_LABEL[p] for p in pols], rotation=25, ha="right",
                       fontsize=6.5)
    ax.set_ylabel("CPU time per packet (ns)")
    ax.legend(fontsize=7, frameon=False)
    ax.grid(alpha=0.25, axis="y")
    fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(os.path.join(out, f"fig3.{ext}"))
    plt.close(fig)

def main():
    rows = read_rows(sys.argv[1])
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    w1 = [fnum(r["goodput"]) / fnum(r["rate"]) for r in rows
          if r["workload"] == "W1" and r["policy"] == "P0"]
    knee = 525000.0
    # knee = highest offered rate with mean delivery >= 0.95 (P0, W1)
    by_rate = {}
    for r in rows:
        if r["workload"] == "W1" and r["policy"] == "P0":
            by_rate.setdefault(fnum(r["rate"]), []).append(fnum(r["deliv"]))
    for rate in sorted(by_rate):
        if sum(by_rate[rate]) / len(by_rate[rate]) >= 0.95:
            knee = rate
    print(f"knee (P0, W1): {knee:.0f} pps at deliv>=0.95")
    fig1(rows, out, knee)
    fig2(rows, out)
    fig3(rows, out)
    print("figures written to", out)

if __name__ == "__main__":
    main()
