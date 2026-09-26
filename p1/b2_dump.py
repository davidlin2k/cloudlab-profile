#!/usr/bin/env python3
"""p1/b2_dump.py -- DR-007 Task B2: dead-vs-healthy receive-queue state dump.

Reads the live kernel through drgn (DWARF from the v6.17.8 build in
/scratch/kbuild). Prints, FACTS ONLY:

  1. the struct definitions it reads (never assume a field name),
  2. per-channel napi.state decoded against the kernel's own
     NAPI_STATE_* definitions (parsed from the build tree source),
  3. full RQ / CQ / ICOSQ detail for the wedged channel and a healthy
     channel -- every candidate field by capability, missing paths
     printed as absent rather than guessed,
  4. the whole extraction twice, 5 s apart, so deltas show what moves.

usage: sudo <python-with-drgn> b2_dump.py <iface> [wedged_ch] [healthy_ch]
"""
import os
import re
import sys
import time

import drgn

IFACE = sys.argv[1] if len(sys.argv) > 1 else "enp195s0np0"
WEDGE_CH = int(sys.argv[2]) if len(sys.argv) > 2 else 7
HEALTH_CH = int(sys.argv[3]) if len(sys.argv) > 3 else 0
VMLINUX = "/scratch/kbuild/linux/vmlinux"
MLX5KO = ("/scratch/kbuild/linux/drivers/net/ethernet/mellanox/"
          "mlx5/core/mlx5_core.ko")
SRC_NETDEV = "/scratch/kbuild/linux/include/linux/netdevice.h"

prog = drgn.program_from_kernel()
try:
    prog.load_debug_info([VMLINUX, MLX5KO], main=False, default=False,
                         modifiers=False)
except TypeError:
    prog.load_debug_info([VMLINUX, MLX5KO])

TYPES = ["struct net_device", "struct mlx5e_priv", "struct mlx5e_channels",
         "struct mlx5e_channel", "struct mlx5e_rq", "struct mlx5e_mpwqe",
         "struct mlx5e_icosq", "struct mlx5e_cq", "struct mlx5_core_cq",
         "struct mlx5_cqwq", "struct mlx5_wq_cyc", "struct mlx5_wq_ll",
         "struct mlx5_frag_buf", "struct mlx5_frag_buf_ctrl"]
have = {}
for t in TYPES:
    try:
        have[t] = prog.type(t)
    except Exception as e:
        print(f"TYPE-FAIL {t}: {e}")
print("== struct definitions (offsets in bytes)")
for t, ty in have.items():
    print(f"--- {t} (size {ty.size})")
    try:
        for name, member in ty.members:
            print(f"    {name}: {member.type.type_name()} @ {member.offset}")
    except Exception as e:
        print(f"    <members unavailable: {e}>")

# NAPI_STATE_* from the kernel's own source, never hard-coded
print("== NAPI_STATE_* (from include/linux/netdevice.h)")
napi_bits = {}
try:
    txt = open(SRC_NETDEV).read()
    for m in re.finditer(r"#define\s+(NAPI_STATE_\w+)\s+BIT\((\d+)\)", txt):
        napi_bits[m.group(1)] = 1 << int(m.group(2))
        print(f"    {m.group(1)} = BIT({m.group(2)})")
    comp = re.findall(r"#define\s+(NAPISTATE_\w+)\s+\(BIT\((\d+)\)\s*\|\s*"
                      r"BIT\((\d+)\)\)", txt)
    for nm, a, b in comp:
        napi_bits[nm] = (1 << int(a)) | (1 << int(b))
        print(f"    {nm} = BIT({a})|BIT({b})")
except Exception as e:
    print(f"    <source parse failed: {e}>")

def decode(state):
    val = int(state)
    set_bits = [nm for nm, bit in napi_bits.items() if bit & val]
    return f"0x{val:x} = {','.join(set_bits) if set_bits else 'none-of-the-above'}"

from drgn.helpers.linux.net import get_netdev_by_name  # noqa: E402
dev = get_netdev_by_name(prog, IFACE)
off = (int(prog.type("struct net_device").size) + 31) // 32 * 32
priv = drgn.cast("struct mlx5e_priv *", drgn.cast("char *", dev) + off)
nch = int(priv.channels.num)
print(f"== netdev {IFACE}: priv at dev+{off}, {nch} channels")

def get(obj, *path):
    """walk a field path by capability; return (ok, value-or-error)."""
    cur = obj
    for p in path:
        try:
            cur = getattr(cur, p)
        except Exception as e:
            return False, f"{type(e).__name__}"
    try:
        return True, int(cur)
    except Exception:
        return True, str(cur)

CANDIDATES = {
    "rq": [
        ("state", ("state",)),
        ("wq.sz", ("wq", "sz")),
        ("wq.wqe_ctr", ("wq", "wqe_ctr")),
        ("wq.cur_sz", ("wq", "cur_sz")),
        ("wq.pc", ("wq", "pc")),
        ("wq.cc", ("wq", "cc")),
        ("mpwqe.num_strides", ("mpwqe", "num_strides")),
        ("mpwqe.log_stride_sz", ("mpwqe", "log_stride_sz")),
        ("mpwqe.pages_per_wqe", ("mpwqe", "pages_per_wqe")),
        ("mpwqe.umr_headroom", ("mpwqe", "umr_headroom")),
        ("mpwqe.log_num_strides", ("mpwqe", "log_num_strides")),
        ("stats", ("stats",)),
    ],
    "cq": [
        ("cq.cons_index", ("cq", "cons_index")),
        ("cq.cqn", ("cq", "cqn")),
        ("cq.arm_db", ("cq", "arm_db")),
        ("cq.ci_pa", ("cq", "ci_pa")),
        ("wq.cc", ("wq", "cc")),
        ("wq.wqe_cnt", ("wq", "wqe_cnt")),
        ("wq.fbc", ("wq", "fbc", "fragments", "0")),
    ],
    "icosq": [
        ("pc", ("pc",)),
        ("cc", ("cc",)),
        ("sqn", ("sqn",)),
        ("wq.pc", ("wq", "pc")),
        ("wq.cc", ("wq", "cc")),
        ("wq.sz", ("wq", "sz")),
        ("stopped", ("stopped",)),
        ("umr_in_progress", ("umr_in_progress",)),
    ],
    "napi": [
        ("state", ("state",)),
        ("list_owner", ("list_owner",)),
        ("poll_owner", ("poll_owner",)),
        ("thread", ("thread",)),
    ],
}

def dump_ch(idx, tag):
    ch = priv.channels.c[idx]
    print(f"== ch{idx} ({tag})")
    for label, path in CANDIDATES["napi"]:
        ok, v = get(ch.napi, *path)
        line = f"    napi.{label} = {v if ok else f'<absent: {v}>'}"
        if label == "state" and ok:
            line += f"  ({decode(v)})"
        print(line)
    for sub in ("rq", "cq", "icosq"):
        obj = getattr(ch, sub)
        print(f"    -- {sub}")
        for label, path in CANDIDATES[sub]:
            ok, v = get(obj, *path)
            print(f"    {sub}.{label} = {v if ok else f'<absent: {v}>'}")

for snap in (1, 2):
    if snap == 2:
        time.sleep(5)
    print(f"\n######## SNAPSHOT {snap} t={time.strftime('%H:%M:%S')} "
          f"mono={time.monotonic():.3f}")
    print("== all channels napi.state (decoded)")
    for i in range(nch):
        try:
            st = int(priv.channels.c[i].napi.state)
            print(f"    ch{i}: {decode(st)}")
        except Exception as e:
            print(f"    ch{i}: <error {type(e).__name__}>")
    dump_ch(WEDGE_CH, "WEDGED")
    dump_ch(HEALTH_CH, "healthy comparison")
print("\n== done (facts only; interpretation held for the PI)")
