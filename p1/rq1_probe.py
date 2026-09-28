#!/usr/bin/env python3
"""p1/rq1_probe.py -- the readiness probe (specs/p1-CAUSAL.md; the T1a
extension is specs/p1-T1A.md).

Samples at ~1 kHz (the achieved rate is recorded) via /proc/kcore:
  cc (CQ consumer index), the ownership bit of the CQE AT cc,
  rq_stats.packets, ch_stats.events, ch_stats.arm, the napi state
  byte, and the ch7 kthread's current CPU.
T1a v4 adds the comp-EQ state per sample (the EQ consumer index, the
device-written bits of the 4 EQE slots at cons_index, the slot-0
EQE's cqn) and 1 Hz port-counter/affinity columns.
Output CSV: ts_ms,cc,own,phase,owned,packets,events,arm,state,cpu,
arm_sn,adb_sn,eq_ci,eq_devw,eq_cqn0,irq_percpu,irq_aff,rx_phy,rx_oob
"Ready but unserved" (per gap, post-processed): packets flat across a
span while owned==1 at every sample.
Usage: rq1_probe.py <ch_addr_hex> <out_csv> [duration_s] [poll_pid]
                    [eq_addr_hex] [irqn]
"""
import os
import subprocess
import sys
import time

CH = int(sys.argv[1], 16)
OUT = sys.argv[2]
DUR = float(sys.argv[3]) if len(sys.argv) > 3 else 400.0
TPID = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else None
EQ = int(sys.argv[5], 16) if len(sys.argv) > 5 and sys.argv[5] else 0
IRQN = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] else None
IFACE = sys.argv[7] if len(sys.argv) > 7 and sys.argv[7] else "enp195s0np0"
VMLINUX = "/scratch/kbuild/linux/vmlinux"

# offsets: runtime-calibrated from the RUNNING kernel's mlx5_core.ko
# DWARF (6.18.9 moved mcq 56->64, cons_index 96->88, arm_sn 100->92,
# eq 176->168); the fallback constants are the 6.17.8 values the
# DR-012 runs were validated against.
_CQO = dict(mcq=56, arm_db=16, cons=96, arm_sn=100, eq=176,
            cc=32, rstats=256, rcq=320, chstats=13392)

def _calibrate():
    import glob, re
    rel = os.uname().release
    kos = glob.glob(f"/lib/modules/{rel}/kernel/drivers/net/ethernet/"
                    "mellanox/mlx5/core/mlx5_core.ko")
    if not kos:
        return
    def fld(struct, member):
        try:
            out = subprocess.run(
                ["pahole", "-C", struct, kos[0]],
                capture_output=True, text=True, timeout=20).stdout
            m = re.search(
                rf"{re.escape(member)}\b[^;]*;\s*"
                rf"(?:__attribute__\(\([^)]*\)\)\s*)?/\*\s*(\d+)\s+\d+",
                out)
            return int(m.group(1)) if m else None
        except Exception:
            return None
    for st, mem, key in (("mlx5e_cq", "mcq", "mcq"),
                         ("mlx5_core_cq", "arm_db", "arm_db"),
                         ("mlx5_core_cq", "cons_index", "cons"),
                         ("mlx5_core_cq", "arm_sn", "arm_sn"),
                         ("mlx5_core_cq", "eq", "eq"),
                         ("mlx5_cqwq", "cc", "cc"),
                         ("mlx5e_rq", "stats", "rstats"),
                         ("mlx5e_rq", "cq", "rcq"),
                         ("mlx5e_channel", "stats", "chstats"),
                         ("mlx5e_channel", "napi", "napi")):
        v = fld(st, mem)
        if v is not None:
            _CQO[key] = v
    print("calib", os.uname().release, _CQO)

import os
_calibrate()

RQ = CH                    # mlx5e_channel.rq = 0
RQ_STATS_PTR = RQ + _CQO["rstats"]   # mlx5e_rq.stats (POINTER)
CQ = RQ + _CQO["rcq"]      # mlx5e_rq.cq (the mlx5e_cq struct)
M = CQ + _CQO["mcq"]       # mlx5e_cq.mcq (the mlx5_core_cq)
ARM_SN = M + _CQO["arm_sn"]
ARM_DB = M + _CQO["arm_db"]  # the doorbell record:
                           # sn << 28 | cmd | ci, big-endian)
CC = CQ + _CQO["cc"]       # mlx5_cqwq.cc
FBC_SZ_M1 = CQ + 8         # mlx5_frag_buf_ctrl.sz_m1
FBC_FRAGS = CQ + 0         # mlx5_frag_buf_ctrl.frags
FBC_LOGSZ = CQ + 16
FBC_LFS = CQ + 18
NAPI = CH + _CQO.get("napi", 10000)
NAPI_STATE = NAPI + 16
CH_STATS_PTR = CH + _CQO["chstats"]  # mlx5e_channel.stats (POINTER)
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
            # after "comm)": state=idx0 ... processor (field 39) = idx 36
            return int(f.read().rsplit(")", 1)[1].split()[36])
    except Exception:
        return -1

# ---- the T1a comp-EQ block (specs/p1-T1A.md) ----------------------
# DWARF: struct mlx5_eq -- fbc@0 {frags@0,sz_m1@8,frag_sz_m1@12,
# strides_offset@14,log_sz@16,log_stride@17,log_frag_strides@18},
# frag_buf@24 {frags@0}, doorbell@80, cons_index@88, eqn@100.
# (all reads are guarded on EQ; eq_state() returns zeros without one)
EQ_SZ_M1 = EQ + 8
EQ_FRAG_SZ_M1 = EQ + 12
EQ_STRIDES_OFF = EQ + 14
EQ_LOGSZ = EQ + 16
EQ_LOGSTRIDE = EQ + 17
EQ_LOGFRAGSTRIDES = EQ + 18
EQ_FRAGS = EQ + 24
EQ_DOORBELL = EQ + 80
EQ_CONS = EQ + 88
EQ_EQN = EQ + 100


def eqe_addr(ix, fraglist, sz_m1, fsm1, soff, lgfs, lgst):
    # driver.h mlx5_frag_buf_get_wqe: ix += strides_offset;
    # frag = ix >> log_frag_strides; buf + ((frag_sz_m1 & ix) << log_stride)
    ix += soff
    frag = u(fraglist + (ix >> lgfs) * 16, 8)
    return frag + ((fsm1 & ix) << lgst)


def eq_state():
    # returns (eq_ci, devw_bits, cqn0): the owner test per lib/eq.h:61
    # -- ((owner ^ (eq_ci >> log_sz)) & 1) == 0 -> DEVICE-WRITTEN.
    if not EQ:
        return 0, 0, 0
    eq_ci = u(EQ_CONS, 4)
    fraglist = u(EQ_FRAGS, 8)
    sz_m1 = u(EQ_SZ_M1, 4)
    fsm1 = u(EQ_FRAG_SZ_M1, 2)
    soff = u(EQ_STRIDES_OFF, 2)
    lgfs = u(EQ_LOGFRAGSTRIDES, 1)
    lgst = u(EQ_LOGSTRIDE, 1)
    lgzs = u(EQ_LOGSZ, 1)
    devw = 0
    cqn0 = 0
    for i in range(4):
        ix = (eq_ci + i) & sz_m1
        eqe = eqe_addr(ix, fraglist, sz_m1, fsm1, soff, lgfs, lgst)
        # the phase expectation is PER ENTRY: entry e = eq_ci + i is
        # device-written iff (owner_e ^ ((eq_ci+i) >> log_sz)) & 1 == 0
        exp = ((eq_ci + i) >> lgzs) & 1
        owner = u(eqe + 63, 1)
        if (owner ^ exp) & 1 == 0:
            devw |= 1 << i
            if i == 0:
                # ev_data @eqe+32; mlx5_eqe_comp.cqn @ union+24 -> eqe+56
                cqn = int.from_bytes(u(eqe + 56, 4).to_bytes(4, "little"),
                                     "big") & 0xFFFFFF
                cqn0 = cqn
    return eq_ci, devw, cqn0


def irq_percpu():
    # the vector's per-cpu interrupt counts from /proc/interrupts
    try:
        with open("/proc/interrupts") as f:
            for line in f:
                if line.startswith(f"{IRQN}:"):
                    return ";".join(line.split(":")[1].split())
    except Exception:
        return ""
    return ""


def irq_aff():
    try:
        with open(f"/proc/irq/{IRQN}/smp_affinity_list") as f:
            return f.read().strip()
    except Exception:
        return ""


def rx_counters():
    # rx_packets_phy / rx_out_of_buffer (the 1 Hz deviation is
    # pre-registered in specs/p1-T1A.md: ethtool -S is an fw-mailbox
    # ioctl; at 1 kHz it would disturb the cell it measures)
    try:
        out = subprocess.run(["ethtool", "-S", IFACE], capture_output=True,
                             text=True, timeout=2).stdout
        phy = oob = ""
        for line in out.splitlines():
            if "rx_packets_phy" in line:
                phy = line.split(":")[-1].strip()
            elif "rx_out_of_buffer" in line:
                oob = line.split(":")[-1].strip()
        return phy, oob
    except Exception:
        return "", ""

os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
t0 = time.time()
print(f"wall_t0 {t0:.6f} eq={hex(EQ) if EQ else '-'} irqn={IRQN or '-'} "
      f"iface={IFACE}")
n = 0
lat_sum = 0.0
with open(OUT, "w") as f:
    f.write("ts_ms,cc,own,phase,owned,packets,events,arm,state,cpu,"
            "arm_sn,adb_sn,eq_ci,eq_devw,eq_cqn0,"
            "irq_percpu,irq_aff,rx_phy,rx_oob\n")
    logsz = u(FBC_LOGSZ, 1)
    lfs = u(FBC_LFS, 1)
    if EQ:
        print(f"eq: doorbell={hex(u(EQ_DOORBELL, 8))} "
              f"eqn={u(EQ_EQN, 1)} nent={u(EQ_SZ_M1, 4) + 1}")
    while time.time() - t0 < DUR:
        t1 = time.time()
        cc = u(CC, 4)
        arm_sn = u(ARM_SN, 4)
        # the arm doorbell RECORD's sn bits (BE: sn << 28 | cmd | ci).
        # mcq+16 holds the arm_db POINTER (__be32 *); the record lives
        # at *arm_db -- dereference first (the flat read of mcq+16
        # yielded a constant derived from the pointer, caught in the
        # SM-1 smoke).
        adb_ptr = u(ARM_DB, 8)
        adb = u(adb_ptr, 4) if adb_ptr > 0xFF00000000000000 else 0
        adb_sn = (int.from_bytes(adb.to_bytes(4, "little"), "big")
                  >> 28) & 3
        op_own, phase = owned_at_cc(cc, logsz, lfs)
        stats_p = u(RQ_STATS_PTR, 8)
        pkt = u(stats_p, 8) if stats_p > 0xFF00000000000000 else 0
        chst_p = u(CH_STATS_PTR, 8)
        ev = u(chst_p, 8) if chst_p > 0xFF00000000000000 else 0
        arm = u(chst_p + 16, 8) if chst_p > 0xFF00000000000000 else 0
        st = u(NAPI_STATE, 1)
        eq_ci, eq_devw, eq_cqn0 = eq_state()
        onhz = n % 1000 == 0
        ipcpu = irq_percpu() if (onhz and IRQN) else ""
        iaff = irq_aff() if (onhz and IRQN) else ""
        rphy, roob = rx_counters() if onhz else ("", "")
        f.write(f"{(t1 - t0) * 1000:.1f},{cc},{op_own},{phase},"
                f"{op_own & 1 == phase},{pkt},{ev},{arm},{st},"
                f"{thread_cpu()},{arm_sn},{adb_sn},{eq_ci},{eq_devw},"
                f"{eq_cqn0},{ipcpu},{iaff},{rphy},{roob}\n")
        n += 1
        # spin-wait to the next millisecond boundary (sleep granularity
        # is ~50-200 us; the achieved rate is reported on exit)
        while time.time() - t1 < 0.001:
            pass
        lat_sum += time.time() - t1
rate = n / (time.time() - t0)
print(f"probe: {n} samples, achieved rate {rate:.0f} Hz "
      f"(mean sample latency {lat_sum / max(n, 1) * 1e6:.0f} us)")
