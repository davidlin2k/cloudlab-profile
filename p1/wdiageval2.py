#!/usr/bin/env python3
"""wdiageval2.py OUTDIR | --summary OUTDIR... -- onset + aff_change rates
with the pre-registered grades (DR-002, fixed 2026-09-24).

Onset definition (handles instant wedges): reference = the max per-
window consumption ever seen in the cell. If even that is < 5% of the
offered 790k, the queue was wedged from the first window (onset = t of
win[0]); otherwise onset = the first window after which consumption
never recovers above 5% of the reference (AN-003's permanent-death
definition; censored at span otherwise).

aff_change rate: reported both over the whole span and over the ACTIVE
window (first min(onset, 30 s)) -- the pre-registration's >1e5/s and
near-zero criteria are graded on the ACTIVE rate, since a wedged queue
polls nothing and dilutes any whole-cell average. Operationalization
recorded in DR-002 before the matrix restarted; the predictions are
untouched.
"""
import re, sys, os

WIN = re.compile(r"\[k2rx-win\] t=(\d+) pkts=(\d+)")
AFF = re.compile(r"ch7_aff_change:\s*(\d+)")
OFFERED = 790000


def onset(path):
    win = []
    for ln in open(path, errors="replace"):
        m = WIN.match(ln)
        if m:
            win.append((int(m[1]), int(m[2])))
    if len(win) < 3:
        return None, win, 0
    ref = max(p for _, p in win)
    if ref < 0.05 * OFFERED:
        return win[0][0], win, ref
    thr = 0.05 * ref
    for i in range(len(win)):
        if win[i][1] < thr and all(p < thr for _, p in win[i:]):
            return win[i][0], win, ref
    return None, win, ref


def cell_stats(out):
    path = os.path.join(out, "consumer.err")
    if not os.path.exists(path):
        return None
    on, win, ref = onset(path)
    span = win[-1][0] if win else 1
    pre = post = None
    for name, slot in (("counters-pre.txt", "pre"), ("counters-post.txt", "post")):
        p = os.path.join(out, name)
        if os.path.exists(p):
            m = AFF.search(open(p, errors="replace").read())
            if m:
                if slot == "pre":
                    pre = int(m[1])
                else:
                    post = int(m[1])
    active = min(on if on is not None else span, 30, span)
    active = max(active, 1)
    rate_all = (post - pre) / span if pre is not None and post is not None else None
    rate_act = (post - pre) / active if pre is not None and post is not None else None
    arm = os.path.basename(out).split("-rep")[0].replace("wdiag-", "")
    return dict(arm=arm, onset=on, span=span, ref=ref,
                rate_all=rate_all, rate_act=rate_act,
                wedged=on is not None)


def main():
    if sys.argv[1] == "--summary":
        cells = [c for c in (cell_stats(d) for d in sys.argv[2:]) if c]
        by = {}
        for c in cells:
            by.setdefault(c["arm"], []).append(c)
        for arm, cs in sorted(by.items()):
            w = sum(c["wedged"] for c in cs)
            acts = [c["rate_act"] for c in cs if c["rate_act"] is not None]
            r = sum(acts) / len(acts) if acts else float("nan")
            ons = sorted(c["onset"] for c in cs if c["onset"] is not None)
            print(f"{arm:8s} n={len(cs)} wedged={w}/{len(cs)} "
                  f"aff_active={r:.0f}/s onsets={ons}")
            if arm.startswith("mis"):
                ok = (w >= 7 and r > 1e5)
                print(f"  PRE-REG mis (>=7/8 wedge AND active aff>1e5/s): "
                      f"{'CONFIRMED' if ok else 'NOT MET'}")
            if arm.startswith("ali"):
                print(f"  PRE-REG ali (<=1/8 wedge, aff near zero): "
                      f"{'MET' if w <= 1 else 'VIOLATED'} (aff_active={r:.0f}/s)")
        ali = [c for a, cs in by.items() if a.startswith("ali") for c in cs]
        ali_w = sum(c["wedged"] for c in ali)
        rates = [c["rate_act"] for c in ali if c["rate_act"] is not None]
        if ali and ali_w >= 4 and rates and max(rates) < 1e3:
            print("REFUTATION RULE FIRES: hypothesis DEAD. DR-003 decision 3:"
                  " stop, no patch, no new theory tonight; AN-005 raw facts;"
                  " ftrace tomorrow (napi_schedule, poll entry/exit, IRQ re-enable).")
        return
    for out in sys.argv[1:]:
        c = cell_stats(out)
        if not c:
            print(f"{out}: no data")
            continue
        v = f"ONSET t={c['onset']}s" if c["wedged"] else f"censored at {c['span']}s"
        ra = f"{c['rate_act']:.0f}/s" if c["rate_act"] is not None else "n/a"
        print(f"{os.path.basename(out):22s} {v:20s} aff_active={ra} peak_win={c['ref']}")


if __name__ == "__main__":
    main()
