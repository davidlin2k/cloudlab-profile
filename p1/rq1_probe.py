#!/usr/bin/env python3
"""p1/rq1_probe.py -- the readiness probe (specs/p1-CAUSAL.md).

Samples at ~1 kHz (the achieved rate is recorded) via /proc/kcore:
  cc (CQ consumer index), the ownership bit of the CQE AT cc,
  rq_stats.packets, ch_stats.events, ch_stats.arm, the napi state
  byte, and the ch7 kthread's current CPU.
Output CSV: ts_ms,cc,own,phase,owned,packets,events,arm,state,cpu
"Ready but unserved" (per gap, post-processed): packets flat across a
span while owned==1 at every sample.
Usage: rq1_probe.py <ch_addr_hex> <out_csv> [duration_s]
"""
import os
import sys
import time

CH = int(sys.argv[1], 16)
OUT = sys.argv[2]
DUR = float(sys.argv[3]) if len(sys.argv) > 3 else 400.0
TPID = int(sys.argv[4]) if len(sys.argv) > 4 else None
VMLINUX = "/scratch/kbuild/linux/vmlinux"

# offsets (pahole-DWARF on the build tree, proven in b2_dump.py)
RQ = CH                    # mlx5e_channel.rq = 0
RQ_STATS_PTR = RQ + 256    # mlx5e_rq.stats = mlx5e_rq_stats* (POINTER)
CQ = RQ + 320              # mlx5e_rq.cq
CC = CQ + 32               # mlx5_cqwq.cc
FBC_SZ_M1 = CQ + 8         # mlx5_frag_buf_ctrl.sz_m1
FBC_FRAGS = CQ + 0         # mlx5_frag_buf_ctrl.frags
FBC_LOGSZ = CQ + 16
FBC_LFS = CQ + 18
NAPI = CH + 10000
NAPI_STATE = NAPI + 16
CH_STATS_PTR = CH + 13392  # mlx5e_channel.stats = mlx5e_channel_stats* (POINTER)
# NOTE: napi_struct.thread (+352) reads a DANGLING task pointer on this
# build (the reused-thread/recreation dance) -- the cpu column comes
# from /proc/<pid>/stat of the correlation-identified poll thread.

import drgn
prog = drgn.program_from_kernel()
try:
    prog.load_debug_info([VMLINUX], main=False)
except Exception:
    pass

def u(addr, n):
    return int.from_bytes(bytes(prog.read(addr, n)), "little")

LFS_MASK = (u(FBC_SZ_M1, 4) >> u(FBC_LFS, 1))  # frag-array bound

def owned_at_cc(cc, logsz, lfs):
    # cc is the free-running consumer counter; the frag index is
    # (cc >> lfs) masked by the array bound (b2_dump's convention)
    frags = u(FBC_FRAGS, 8)
    frag = u(frags + ((cc >> lfs) & LFS_MASK) * 16, 8)
    idx = cc & ((1 << lfs) - 1)
    op_own = u(frag + idx * 64 + 63, 1)
    return op_own, (cc >> logsz) & 1

def thread_cpu():
    # the REAL poll thread's current cpu from /proc/<pid>/stat (field 39)
    if TPID is None:
        return -1
    try:
        with open(f"/proc/{TPID}/stat") as f:
            return int(f.read().rsplit(")", 1)[1].split()[37])
    except Exception:
        return -1

os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
t0 = time.time()
n = 0
lat_sum = 0.0
with open(OUT, "w") as f:
    f.write("ts_ms,cc,own,phase,owned,packets,events,arm,state,cpu\n")
    logsz = u(FBC_LOGSZ, 1)
    lfs = u(FBC_LFS, 1)
    while time.time() - t0 < DUR:
        t1 = time.time()
        cc = u(CC, 4)
        op_own, phase = owned_at_cc(cc, logsz, lfs)
        stats_p = u(RQ_STATS_PTR, 8)
        pkt = u(stats_p, 8) if stats_p > 0xFF00000000000000 else 0
        chst_p = u(CH_STATS_PTR, 8)
        ev = u(chst_p, 8) if chst_p > 0xFF00000000000000 else 0
        arm = u(chst_p + 16, 8) if chst_p > 0xFF00000000000000 else 0
        st = u(NAPI_STATE, 1)
        f.write(f"{(t1 - t0) * 1000:.1f},{cc},{op_own},{phase},"
                f"{op_own & 1 == phase},{pkt},{ev},{arm},{st},{thread_cpu()}\n")
        n += 1
        # spin-wait to the next millisecond boundary (sleep granularity
        # is ~50-200 us; the achieved rate is reported on exit)
        while time.time() - t1 < 0.001:
            pass
        lat_sum += time.time() - t1
rate = n / (time.time() - t0)
print(f"probe: {n} samples, achieved rate {rate:.0f} Hz "
      f"(mean sample latency {lat_sum / max(n, 1) * 1e6:.0f} us)")
