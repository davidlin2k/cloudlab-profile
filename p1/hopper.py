#!/usr/bin/env python3
"""p1/hopper.py -- the forced-migration arm (DR-011 item 2).

Pins the poll thread and hops it between two CPUs on a fixed schedule
(default 100 ms), logging every hop. The hop log is joined with the
readiness probe and the wake trace at analysis.
Usage: hopper.py <pid> <cpuA> <cpuB> [period_ms] [duration_s] [out_csv]
"""
import os
import sys
import time

pid = int(sys.argv[1])
A, B = int(sys.argv[2]), int(sys.argv[3])
period = float(sys.argv[4]) / 1000.0 if len(sys.argv) > 4 else 0.1
dur = float(sys.argv[5]) if len(sys.argv) > 5 else 400.0
out = sys.argv[6] if len(sys.argv) > 6 else ""

os.sched_setaffinity(pid, {A})
cur = A
t0 = time.time()
n = 0
fh = open(out, "w") if out else None
if fh:
    fh.write("ts_ms,cpu\n")
try:
    while time.time() - t0 < dur:
        time.sleep(period)
        nxt = B if cur == A else A
        os.sched_setaffinity(pid, {nxt})
        cur = nxt
        n += 1
        if fh:
            fh.write(f"{(time.time() - t0) * 1000:.1f},{cur}\n")
finally:
    if fh:
        fh.close()
print(f"hopper: {n} hops ({A}<->{B} @ {period * 1000:.0f} ms) over "
      f"{time.time() - t0:.1f} s")
