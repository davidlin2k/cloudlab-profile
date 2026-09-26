#!/usr/bin/env python3
"""p1/e2_sampler.py -- DR-008 E2 per-second manipulation logger.

argv: <ch7_addr_hex> <outdir> -- 1 Hz CSV of:
  ts, ch7_napi_thread_Cpus_allowed_list, irq312_effective_affinity_list,
  ch7_ch_stats_aff_change (kcore read, raw counter), ch7_stats_events
Runs until SIGTERM. Facts only.
"""
import os
import re
import subprocess
import sys
import time

CH = int(sys.argv[1], 16)
OUT = sys.argv[2]
VMLINUX = "/scratch/kbuild/linux/vmlinux"
NETDEV = "enp195s0np0"
NAPI_OFF = 10000          # pahole mlx5e_channel.napi
NAPI_ID_OFF = 380         # pahole napi_struct.napi_id (vmlinux DWARF)
STATS_OFF = 13392         # pahole mlx5e_channel.stats
AFF_CHANGE_OFF = 24       # pahole mlx5e_ch_stats.aff_change

import drgn
prog = drgn.program_from_kernel()
try:
    prog.load_debug_info([VMLINUX], main=False)
except Exception:
    pass

def rd(addr, n):
    return bytes(prog.read(addr, n))

def u(addr, n):
    return int.from_bytes(rd(addr, n), "little")

napi_id = u(CH + NAPI_OFF + NAPI_ID_OFF, 4)
stats_ptr = u(CH + STATS_OFF, 8)
comm = f"napi/{NETDEV}-{napi_id}"

pid = None
out = subprocess.run(["pgrep", "-f", f"^{re.escape(comm)}$"],
                     capture_output=True, text=True).stdout.split()
if out:
    pid = out[0]
else:  # comm match via /proc scan
    for p in subprocess.run(["bash", "-c", "ls /proc | grep -E '^[0-9]+$'"],
                            capture_output=True, text=True).stdout.split():
        try:
            c = open(f"/proc/{p}/comm").read().strip()
            if c == comm:
                pid = p
                break
        except Exception:
            continue
if not pid:
    sys.exit(f"no thread with comm {comm!r}")

def irq_aff():
    try:
        return open("/proc/irq/312/effective_affinity_list").read().strip()
    except Exception:
        return "?"

def thread_mask():
    try:
        for line in open(f"/proc/{pid}/status"):
            if line.startswith("Cpus_allowed_list"):
                return line.split("\t")[1].strip()
    except Exception:
        return "?"
    return "?"

os.makedirs(OUT, exist_ok=True)
path = f"{OUT}/e2-sampler.csv"
print(f"sampler: ch=0x{CH:x} napi_id={napi_id} pid={pid} stats=0x{stats_ptr:x} -> {path}", flush=True)
prev = u(stats_ptr + AFF_CHANGE_OFF, 8)
with open(path, "w") as f:
    f.write("ts,thread_mask,irq312_eff,aff_change,events\n")
    while True:
        try:
            ac = u(stats_ptr + AFF_CHANGE_OFF, 8)
            ev = u(stats_ptr, 8)
            f.write(f"{time.strftime('%H:%M:%S')},{thread_mask()},{irq_aff()},{ac},{ev}\n")
            f.flush()
        except Exception as e:
            print(f"sampler read fault: {e}", flush=True)
            break
        time.sleep(1)
