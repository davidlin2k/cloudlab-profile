#!/usr/bin/env python3
"""wdiageval3.py OUTDIR | --summary OUTDIR... -- onset + aff_change with
the pre-registered grades (DR-002, fixed 2026-09-24; operationalization
appended same day before the matrix restart).

Onset: win-line based when the consumer emitted windows; instant-wedge
cells (wedged before any window: consumer wins < 3 AND wire > 1e6 AND
processed < 1e5) score ONSET t=0 -- a wedged queue emits no windows,
which is the phenomenon, not missing data.
"""
import re, sys, os

WIN = re.compile(r"\[k2rx-win\] t=(\d+) pkts=(\d+)")
AFF = re.compile(r"ch7_aff_change:\s*(\d+)")
PLL = re.compile(r"ch7_poll:\s*(\d+)")
WIR = re.compile(r"rx_packets_phy:\s*(\d+)")


def grab(path, pat):
    if not os.path.exists(path):
        return None
    m = pat.search(open(path, errors="replace").read())
    return int(m[1]) if m else None


def cell_stats(out):
    path = os.path.join(out, "consumer.err")
    win = []
    if os.path.exists(path):
        for ln in open(path, errors="replace"):
            m = WIN.match(ln)
            if m:
                win.append((int(m[1]), int(m[2])))
    pre = os.path.join(out, "counters-pre.txt")
    post = os.path.join(out, "counters-post.txt")
    a0, a1 = grab(pre, AFF), grab(post, AFF)
    p0, p1 = grab(pre, PLL), grab(post, PLL)
    w0, w1 = grab(pre, WIR), grab(post, WIR)
    wire = (w1 - w0) if w0 is not None and w1 is not None else 0
    proc = (p1 - p0) if p0 is not None and p1 is not None else 0
    if len(win) < 3 and wire > 1000000 and proc < 100000:
        on, ref, span = 0, 0, 1
    elif len(win) >= 3:
        ref = max(p for _, p in win)
        span = win[-1][0] or 1
        thr = 0.05 * ref
        on = None
        for i in range(len(win)):
            if win[i][1] < thr and all(p < thr for _, p in win[i:]):
                on = win[i][0]
                break
    else:
        return dict(arm=os.path.basename(out).split("-rep")[0].replace("wdiag-", ""),
                    onset=None, span=1, rate_act=None, wedged=False,
                    wire=wire, proc=proc, invalid=(wire < 100000))
    active = max(1, min(on if on is not None else span, 30, span))
    rate_act = (a1 - a0) / active if a0 is not None and a1 is not None else None
    arm = os.path.basename(out).split("-rep")[0].replace("wdiag-", "")
    return dict(arm=arm, onset=on, span=span, rate_act=rate_act,
                wedged=on is not None, wire=wire, proc=proc,
                invalid=(wire < 100000))


def main():
    if sys.argv[1] == "--summary":
        cells = [c for c in (cell_stats(d) for d in sys.argv[2:]) if c]
        by = {}
        for c in cells:
            by.setdefault(c["arm"], []).append(c)
        for arm, cs in sorted(by.items()):
            good = [c for c in cs if not c["invalid"]]
            w = sum(c["wedged"] for c in good)
            acts = [c["rate_act"] for c in good if c["rate_act"] is not None]
            r = sum(acts) / len(acts) if acts else float("nan")
            ons = sorted(c["onset"] for c in good if c["onset"] is not None)
            print(f"{arm:8s} n={len(good)} (invalid={len(cs)-len(good)}) "
                  f"wedged={w}/{len(good)} aff_active={r:.0f}/s onsets={ons}")
            if arm.startswith("mis"):
                ok = (w >= 7 and r > 1e5)
                print(f"  PRE-REG mis (>=7/8 wedge AND active aff>1e5/s): "
                      f"{'CONFIRMED' if ok else 'NOT MET'}")
            if arm.startswith("ali"):
                print(f"  PRE-REG ali (<=1/8 wedge, aff near zero): "
                      f"{'MET' if w <= 1 else 'VIOLATED'} (aff_active={r:.0f}/s)")
        ali = [c for a, cs in by.items() if a.startswith("ali")
               for c in cs if not c["invalid"]]
        ali_w = sum(c["wedged"] for c in ali)
        rates = [c["rate_act"] for c in ali if c["rate_act"] is not None]
        if ali and ali_w >= 4 and rates and max(rates) < 1e3:
            print("REFUTATION RULE FIRES: hypothesis DEAD. DR-003 decision 3:"
                  " stop, no patch, no new theory tonight; AN-005 raw facts;"
                  " ftrace tomorrow (napi_schedule, poll entry/exit, IRQ re-enable).")
        return
    for out in sys.argv[1:]:
        c = cell_stats(out)
        v = (f"ONSET t={c['onset']}s" if c["wedged"] else f"censored at {c['span']}s")
        ra = f"{c['rate_act']:.0f}/s" if c.get("rate_act") is not None else "n/a"
        flag = " INVALID(sender)" if c["invalid"] else ""
        print(f"{os.path.basename(out):22s} {v:20s} aff_active={ra} "
              f"wire={c['wire']} proc={c['proc']}{flag}")


if __name__ == "__main__":
    main()
