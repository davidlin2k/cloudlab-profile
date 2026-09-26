#!/usr/bin/env python3
"""p1/find_napi_thread.py -- identify ch<n>'s REAL poll kthread by
correlation: sample every /proc-visible napi kthread's cumulative
stime/utime (from /proc/<pid>/stat) alongside ch's cc; the thread whose
stime advances exactly when cc advances is the poller. The napi.thread
pointer can be stale on this build (the 32->16->32 preflight dance
recreates channels; the reused-thread comm is all "napi/...-0").
Usage: find_napi_thread.py <ch_addr_hex> [sample_s]
Prints: PID <pid> (plus the runner-up table).
"""
import os
import sys
import time

CH = int(sys.argv[1], 16)
SECS = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
CC = CH + 320 + 32

import drgn
prog = drgn.program_from_kernel()
try:
    prog.load_debug_info(["/scratch/kbuild/linux/vmlinux"], main=False)
except Exception:
    pass

def u(a, n):
    return int.from_bytes(bytes(prog.read(a, n)), "little")

# the /proc-visible napi kthreads
pids = []
for p in os.listdir("/proc"):
    if not p.isdigit():
        continue
    try:
        if open(f"/proc/{p}/comm").read().strip().startswith("napi/"):
            pids.append(int(p))
    except Exception:
        continue
if not pids:
    sys.exit("no /proc-visible napi threads")
print(f"candidates: {len(pids)} napi threads")

def stat_fields(pid):
    with open(f"/proc/{pid}/stat") as f:
        parts = f.read().rsplit(")", 1)[1].split()
    # after comm: state=3.. ; utime=14, stime=15 (1-indexed) -> idx 11,12
    return int(parts[11]), int(parts[12])

prev_stime = {p: stat_fields(p)[1] for p in pids}
prev_cc = u(CC, 4)
acc = {p: 0 for p in pids}
n = 0
t0 = time.time()
while time.time() - t0 < SECS:
    time.sleep(0.05)
    cc = u(CC, 4)
    if cc == prev_cc:
        continue
    dcc = cc - prev_cc
    prev_cc = cc
    n += 1
    for p in pids:
        s = stat_fields(p)[1]
        ds = s - prev_stime[p]
        prev_stime[p] = s
        if ds > 0:
            acc[p] += ds
    if n > 600:
        break

if n < 5:
    sys.exit(f"too few cc advances ({n}) -- is there traffic?")
ranked = sorted(acc.items(), key=lambda kv: -kv[1])
print(f"cc advances sampled: {n}")
for p, s in ranked[:4]:
    print(f"  pid {p}: stime_ticks_at_cc_advance {s} comm "
          f"{open(f'/proc/{p}/comm').read().strip()}")
print(f"PID {ranked[0][0]}")
