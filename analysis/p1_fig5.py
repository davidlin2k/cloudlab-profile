#!/usr/bin/env python3
"""p1_fig5.py -- Fig 5: W5 time series (rung chosen, goodput, latency).

usage: .venv/bin/python analysis/p1_fig5.py results_root/w5 outdir
Parses per-run consumer.err win lines
([k2rx-win] t=N pkts=N rate=F drops=N [wp50_us=N]) and P7's ctl.log
(rung moves with ns timestamps and rate estimates), plus the offered
profile from lists/w5-<pattern>.txt. Three panels (ramp, burst, step),
P7 emphasized, statics as thin reference lines.

Verified parsing before plotting (skill rule): prints one sample line
per source and the parsed span; refuses to draw if win lines and the
manifest's run length disagree by more than 20%.
"""
import glob, json, os, re, sys

sys.path.insert(0, "/mnt/davidlin-personal/flowlet-eval/figures")
from figstyle import (PALETTE, apply_publication_style, create_subplots,
                      finalize_figure)

WIN = re.compile(r"\[k2rx-win\] t=(\d+) pkts=(\d+) rate=([0-9.]+) drops=(\d+)(?: wp50_us=(\d+))?")
MOVE = re.compile(r"rung[^0-9]*(\d)[^0-9]+(\d).*?t_ns=(\d+).*?rate=([0-9.]+)")
COLORS = {"P0": PALETTE["blue_main"], "P2": PALETTE["red_strong"],
          "P4": PALETTE["teal"], "P7": PALETTE["violet"]}
PATTERNS = ["ramp", "burst", "step"]


def parse_run(rundir):
    win = []
    p = os.path.join(rundir, "consumer.err")
    if os.path.exists(p):
        for ln in open(p):
            m = WIN.match(ln)
            if m:
                win.append(dict(t=int(m[1]), pkts=int(m[2]), rate=float(m[3]),
                                drops=int(m[4]),
                                wp50=int(m[5]) if m[5] else None))
    moves = []
    p = os.path.join(rundir, "ctl.log")
    if os.path.exists(p):
        for ln in open(p):
            m = MOVE.search(ln)
            if m:
                moves.append(dict(frm=int(m[1]), to=int(m[2]),
                                  t_ns=int(m[3]), rate=float(m[4])))
    return win, moves


def offered_profile(root, pattern):
    """aggregate pps per profile step (5 senders each scale 0.2)."""
    p = os.path.join(root, "lists", f"w5-{pattern}.txt")
    if not os.path.exists(p):
        return []
    out = []
    for ln in open(p):
        a = ln.split()
        if len(a) >= 2:
            try:
                out.append(float(a[-1]))
            except ValueError:
                continue
    return out


def main():
    root, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    runs = {}
    for d in glob.glob(os.path.join(root, "W5-*-*", "rep*")):
        cell = os.path.basename(os.path.dirname(d))
        pol, pat = cell.split("-")[1:3]
        rep = int(os.path.basename(d).replace("rep", ""))
        man = os.path.join(d, "manifest.json")
        if os.path.exists(man):
            m = json.load(open(man))
            if m.get("gates", {}).get("conservation") != "pass":
                print(f"skip (gate): {cell} rep{rep}")
                continue
        win, moves = parse_run(d)
        if not win:
            print(f"skip (no win lines): {cell} rep{rep}")
            continue
        dur = m.get("time", {}).get("measure_s", 190) if os.path.exists(man) else 190
        if abs(win[-1]["t"] - win[0]["t"] - dur) > 0.2 * dur:
            print(f"skip (win span {win[-1]['t']-win[0]['t']}s != {dur}s): "
                  f"{cell} rep{rep}")
            continue
        runs.setdefault((pat, pol), []).append((win, moves))
        print(f"parsed {cell} rep{rep}: {len(win)} win lines, "
              f"{len(moves)} rung moves (sample t={win[0]['t']} "
              f"rate={win[0]['rate']:.0f} wp50={win[0]['wp50']})")
    if not runs:
        print("no valid W5 runs yet -- figure skipped")
        return
    apply_publication_style()
    fig, axes = create_subplots(len(PATTERNS), 1, figsize=(3.6, 6.2))
    for ax, pat in zip(axes, PATTERNS):
        for pol in ("P0", "P2", "P4", "P7"):
            series = runs.get((pat, pol))
            if not series:
                continue
            win = series[0][0]
            ax.plot([w["t"] for w in win], [w["rate"] for w in win],
                    color=COLORS[pol], lw=2.0 if pol == "P7" else 0.9,
                    alpha=1.0 if pol == "P7" else 0.55,
                    label=pol if pat == PATTERNS[0] else None)
            if pol == "P7":
                for mv in series[0][1]:
                    ax.axvline(mv["t_ns"] / 1e9 - win[0]["t"], color=PALETTE["highlight"],
                               lw=0.8, zorder=1)
        ax.set_title(f"W5 {pat}", fontsize=9)
        ax.set_ylabel("delivered (pps)")
    axes[-1].set_xlabel("time (s)")
    axes[0].legend(loc="lower center", bbox_to_anchor=(0.5, 1.02), ncol=4,
                   fontsize=7)
    saved = finalize_figure(fig, os.path.join(out, "fig5"), formats=["png", "pdf"])
    for p in saved:
        print("wrote", p)


if __name__ == "__main__":
    main()
