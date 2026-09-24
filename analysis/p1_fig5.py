#!/usr/bin/env python3
"""p1_fig5.py -- Fig 5: rung chosen, goodput, latency over W5 patterns
(skeleton row: "Time series under a ramp and under bursts: rung chosen,
goodput, latency" -- claim: "The ladder moves before the knee without
flapping"; D2: recovers a burst or a step in < 100 ms and wastes < 10%
of the unattainable rate").

usage: .venv/bin/python analysis/p1_fig5.py results_root/<TAG> outdir
where results_root/<TAG> holds W5-<POL>-<PAT>/rep<k>/ run dirs with
  consumer.err  -- [k2rx-win] t=%.0f pkts=%llu rate=%.0f drops=%llu
                   wp50_us=%llu [wp99_us=%llu]  (wp99 needs the quiet-
                   window k2_rx rebuild; older runs parse without it)
  ctl.log       -- "<wall> rate=<f> rung=<n> knee=<f> [t_rel=<f>]"
                   periodic lines (p1ctl, 0.2 s); rung moves are derived
                   from rung CHANGES in this series (5 Hz -- finer than
                   the 1 s win bins). t_rel is preferred; without it the
                   series is rebased to its first line (alignment to the
                   consumer start is then +/-2 s -- caveat recorded).
Offered overlay: <results_root>/../lists/w5-<pat>.txt "t rate" points,
aggregate pps (5 senders each --scale 0.2).

Verified parsing before plotting (figure skill): one sample line per
source + parsed span is printed; runs are dropped and named when gates
fail, win lines are absent, or the win span disagrees with the manifest
duration by >20%. Claim numbers (recovery ms per profile edge, waste
ratio) are PRINTED, never silently asserted.
"""
import glob, json, math, os, re, sys

sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

WIN = re.compile(r"\[k2rx-win\] t=(\d+) pkts=(\d+) rate=([0-9.]+) "
                 r"drops=(\d+)(?: wp50_us=(\d+))?(?: wp99_us=(\d+))?")
CTL = re.compile(r"^([0-9.]+) rate=([0-9.]+) rung=(\d+) knee=([0-9.]+)"
                 r"(?: t_rel=([0-9.]+))?")
COLORS = {"P0": PALETTE["blue_main"], "P2": PALETTE["red_strong"],
          "P4": PALETTE["teal"], "P7": PALETTE["violet"]}
PATTERNS = ["ramp", "burst", "step"]


def parse_run(rundir):
    win = []
    p = os.path.join(rundir, "consumer.err")
    if os.path.exists(p):
        for ln in open(p, errors="replace"):
            m = WIN.match(ln)
            if m:
                win.append(dict(t=int(m[1]), pkts=int(m[2]), rate=float(m[3]),
                                drops=int(m[4]),
                                wp50=int(m[5]) if m[5] else None,
                                wp99=int(m[6]) if m[6] else None))
    ctl = []
    p = os.path.join(rundir, "ctl.log")
    if os.path.exists(p):
        raw = []
        for ln in open(p, errors="replace"):
            m = CTL.match(ln)
            if m:
                raw.append(dict(ts=float(m[1]), rate=float(m[2]),
                                rung=int(m[3]), knee=float(m[4]),
                                t_rel=float(m[5]) if m[5] else None))
        if raw:
            base = raw[0]["ts"]
            for e in raw:
                e["t_rel"] = e["t_rel"] if e["t_rel"] is not None \
                    else e["ts"] - base
            ctl = raw
    return win, ctl


def load_offered(profiles_dir, pattern):
    p = os.path.join(profiles_dir, f"w5-{pattern}.txt")
    pts = []
    if os.path.exists(p):
        for ln in open(p):
            a = ln.split()
            if len(a) == 2:
                try:
                    pts.append((float(a[0]), float(a[1])))
                except ValueError:
                    pass
    return pts


def rate_at(prof, t):
    if not prof:
        return 0.0
    if t <= prof[0][0]:
        return prof[0][1]
    for (t0, r0), (t1, r1) in zip(prof, prof[1:]):
        if t <= t1:
            f = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return r0 + f * (r1 - r0)
    return prof[-1][1]


def claim_math(pat, prof, p7_win, static_win):
    """D2 numbers: recovery after each profile edge and the waste ratio.
    Recovery = time after the edge until P7 delivers >=90% of the best
    static arm at the same second for 3 consecutive windows. Waste =
    integral of (best_static - P7)+ over [edge-1, edge+2] s divided by
    the unattainable demand integral (offered - best_static)+ there.
    1 s win bins bound the recovery resolution: values below 1 s report
    as "<=1000 ms (bin-limited)" only when the 3-window run starts in
    the first bin -- otherwise the measured crossing time is printed."""
    edges = [(t1, r1) for (t0, r0), (t1, r1) in zip(prof, prof[1:])
             if r1 >= 1.2 * r0 or r1 <= 0.8 * r0]

    def best(t):
        for w in static_win:
            if w["t"] == t:
                return w["rate"]
        return 0.0

    for t_edge, r_after in edges:
        rec = None
        okrun = 0
        for w in p7_win:
            if w["t"] < t_edge:
                continue
            tgt = 0.9 * min(rate_at(prof, w["t"]), best(w["t"]))
            ok = tgt > 0 and w["rate"] >= tgt
            okrun = okrun + 1 if ok else 0
            if okrun >= 3:
                rec = w["t"] - 2 - t_edge
                break
        waste = unattain = 0.0
        for w in p7_win:
            if t_edge - 1 <= w["t"] <= t_edge + 2:
                b = best(w["t"])
                waste += max(0.0, b - w["rate"])
                unattain += max(0.0, rate_at(prof, w["t"]) - b)
        ratio = waste / unattain if unattain > 0 else float("nan")
        recs = ("<=%d ms (bin-limited)" % ((rec + 1) * 1000) if rec is not None
                and rec <= 0 else
                ("%.0f ms" % (rec * 1000) if rec is not None else ">window"))
        print(f"CLAIM {pat} edge t={t_edge:.2f}s r->{r_after:.0f}: "
              f"recovery={recs}  waste/unattainable={ratio:.3f}")


def main():
    root, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    profiles_dir = os.path.join(os.path.dirname(root.rstrip("/")), "lists")
    runs = {}
    for d in sorted(glob.glob(os.path.join(root, "W5-*-*", "rep*"))):
        cell = os.path.basename(os.path.dirname(d))
        parts = cell.split("-")
        pol, pat = parts[1], parts[2]
        rep = int(os.path.basename(d).replace("rep", ""))
        m = {}
        man = os.path.join(d, "manifest.json")
        if os.path.exists(man):
            m = json.load(open(man))
            if m.get("gates", {}).get("conservation") != "pass":
                print(f"skip (gate): {cell} rep{rep}")
                continue
        win, ctl = parse_run(d)
        if not win:
            print(f"skip (no win lines): {cell} rep{rep}")
            continue
        dur = m.get("secs", 190) or 190
        span = win[-1]["t"] - win[0]["t"]
        if abs(span - dur) > 0.2 * dur:
            print(f"skip (win span {span}s != {dur}s): {cell} rep{rep}")
            continue
        runs.setdefault((pat, pol), []).append((win, ctl))
        sample = f"t={win[0]['t']} rate={win[0]['rate']:.0f} wp50={win[0]['wp50']}"
        print(f"parsed {cell} rep{rep}: {len(win)} wins, {len(ctl)} ctl "
              f"samples (sample {sample})")
    if not runs:
        print("no valid W5 runs yet -- figure skipped")
        return

    apply_publication_style()
    fig, axes = create_subplots(len(PATTERNS), 2, figsize=(7.2, 6.2))
    for r, pat in enumerate(PATTERNS):
        ax, axl = axes[r]
        prof = load_offered(profiles_dir, pat)
        if prof:
            ts = [t0 + i * 0.5 for t0, _ in prof[:1]
                  for i in range(int((prof[-1][0] - t0) / 0.5) + 1)]
            ax.plot(ts, [rate_at(prof, t) for t in ts], color="0.55",
                    lw=0.9, ls="--", label="offered")
        for pol in ("P0", "P2", "P4", "P7"):
            series = runs.get((pat, pol))
            if not series:
                continue
            win, ctl = series[0]
            ax.plot([w["t"] for w in win], [w["rate"] for w in win],
                    color=COLORS[pol], lw=2.0 if pol == "P7" else 0.9,
                    alpha=1.0 if pol == "P7" else 0.55,
                    label=pol if pat == PATTERNS[0] else None)
            if ctl and pol == "P7":
                ax2 = ax.twinx()
                ax2.step([e["t_rel"] for e in ctl],
                         [e["rung"] for e in ctl], where="post",
                         color=PALETTE["highlight"], lw=0.8, alpha=0.8)
                ax2.set_ylim(-0.3, 2.3)
                ax2.set_yticks([0, 1, 2])
                ax2.set_ylabel("rung", fontsize=7, color=PALETTE["highlight"])
                ax2.tick_params(labelsize=6)
            p99 = [(w["t"], w["wp99"] or w["wp50"]) for w in win
                   if w["wp99"] or w["wp50"]]
            if p99:
                axl.plot([t for t, _ in p99], [v for _, v in p99],
                         color=COLORS[pol], lw=2.0 if pol == "P7" else 0.9,
                         alpha=1.0 if pol == "P7" else 0.55,
                         label=pol if pat == PATTERNS[0] else None)
        ax.set_title(f"W5 {pat}: delivered vs offered", fontsize=8)
        ax.set_ylabel("packets/s")
        axl.set_title(f"W5 {pat}: window p99 (wp99, else p50)", fontsize=8)
        axl.set_ylabel("us (log)")
        axl.set_yscale("log")
        axl.set_xlabel("time (s)")
        # claim math: P7 vs the best static arm (rep 1 series each)
        if (pat, "P7") in runs:
            p7w = runs[(pat, "P7")][0][0]
            statics = [runs[(pat, p)][0][0]
                       for p in ("P0", "P2", "P4") if (pat, p) in runs]
            if statics:
                best = [max(s[i]["rate"] for s in statics if i < len(s))
                        for i in range(len(p7w))]
                merged = [dict(t=p7w[i]["t"], rate=best[i])
                          for i in range(len(p7w))]
                claim_math(pat, prof, p7w, merged)
    axes[0][0].legend(loc="lower center", bbox_to_anchor=(0.5, 1.05), ncol=5,
                      fontsize=7)
    saved = finalize_figure(fig, os.path.join(out, "fig5"),
                            formats=["png", "pdf"])
    for p in saved:
        print("wrote", p)


if __name__ == "__main__":
    main()
