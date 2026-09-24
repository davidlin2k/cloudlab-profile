#!/usr/bin/env python3
"""wdiageval.py OUTDIR -- wedge onset extraction for survival curves
(PI review: "report time-to-wedge as survival curves, since onset is the
variable"). Reads consumer.err win lines: the onset is the first window
after which delivery stays <5% of the first-five-window median through
the end (a wedge is permanent -- AN-003). Cells without an onset are
censored at their span. Prints one row per cell (arm, rep, onset_s or
censored, span_s) and the arm-level summary the A/B adjudicates on:
misaligned expect onsets, aligned expect 8/8 censored with
aff_change delta ~0 (positive control), unpin is the severity arm.
"""
import re, sys, glob, os

WIN = re.compile(r"\[k2rx-win\] t=(\d+) pkts=(\d+)")


def onset(path):
    win = []
    for ln in open(path, errors="replace"):
        m = WIN.match(ln)
        if m:
            win.append((int(m[1]), int(m[2])))
    if len(win) < 8:
        return None, win
    med = sorted(p for _, p in win[:5])[2]
    for i in range(5, len(win)):
        if win[i][1] < 0.05 * med and all(p < 0.05 * med for _, p in win[i:]):
            return win[i][0], win
    return None, win


def main():
    for out in sys.argv[1:]:
        path = os.path.join(out, "consumer.err")
        if not os.path.exists(path):
            print(f"{out}: no consumer.err")
            continue
        on, win = onset(path)
        span = win[-1][0] if win else 0
        sent = 0
        sp = os.path.join(out, "senders.txt")
        if os.path.exists(sp):
            for m in re.finditer(r"sent=(\d+)", open(sp, errors="replace").read()):
                sent = max(sent, int(m[1]))
        total = sum(p for _, p in win)
        verdict = f"ONSET t={on}s" if on is not None else f"censored at {span}s"
        print(f"{os.path.basename(out):24s} {verdict:18s} "
              f"delivered={total} wins={len(win)}")
    print("\nARM SUMMARY (8 cells/arm target; misaligned = wedge expected,")
    print("aligned = 8/8 censored AND aff_change delta ~0 (positive control),")
    print("unpin = severity). Survival rows above feed the curves directly.")


if __name__ == "__main__":
    main()
