#!/usr/bin/env python3
"""p1/b2_dump.py -- DR-007 Task B2: dead-vs-healthy receive-queue state dump.

FACTS ONLY. Address discovery is runtime (bpftrace kprobes -> napi or
completion-event -> channel -> priv); every struct offset is taken from
the DWARF of the mlx5_core.ko built for this kernel (pahole, recorded
below and printed at runtime as provenance); kernel-side offsets
(napi_struct.state) come from the built vmlinux DWARF via drgn types.
Memory is read through /proc/kcore.

The vmlinux symbol ADDRESSES from our rebuild do NOT match the running
kernel's link layout, so no kernel symbol is ever dereferenced --
drgn supplies types and raw memory reads only.

usage: sudo python3 b2_dump.py [wedged_ix] [healthy_ix] [snapshot_gap_s]
"""
import collections
import re
import subprocess
import sys
import time

import drgn

WEDGE_IX = int(sys.argv[1]) if len(sys.argv) > 1 else 7
HEALTH_IX = int(sys.argv[2]) if len(sys.argv) > 2 else 0
GAP_S = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
IFACE = "enp195s0np0"

VMLINUX = "/scratch/kbuild/linux/vmlinux"
KO = ("/scratch/kbuild/linux/drivers/net/ethernet/mellanox/"
      "mlx5/core/mlx5_core.ko")
EN_H = "/scratch/kbuild/linux/drivers/net/ethernet/mellanox/mlx5/core/en.h"
NETDEV_H = "/scratch/kbuild/linux/include/linux/netdevice.h"

# ---- offsets from pahole -F dwarf on the built mlx5_core.ko (2026-09-26)
OFF = {
    "mlx5e_priv.channels": 1600,
    "mlx5e_priv.netdev": 2240,
    "mlx5e_channels.c": 0,
    "mlx5e_channels.num": 16,
    "mlx5e_channel.rq": 0,
    "mlx5e_channel.icosq": 9344,
    "mlx5e_channel.async_icosq": 12736,
    "mlx5e_channel.napi": 10000,
    "mlx5e_channel.priv": 13400,
    "mlx5e_channel.state": 13424,
    "mlx5e_channel.ix": 13432,
    "mlx5e_channel.cpu": 13444,
    "mlx5e_channel.stats": 13392,
    "mlx5e_rq.union_wq": 0,          # mlx5_wq_ll (mpwqe arm) / mlx5_wq_cyc
    "mlx5e_rq.mpwqe.umr_mkey_be": 192,
    "mlx5e_rq.mpwqe.num_strides": 196,
    "mlx5e_rq.mpwqe.actual_wq_head": 198,
    "mlx5e_rq.mpwqe.log_stride_sz": 200,
    "mlx5e_rq.mpwqe.umr_in_progress": 201,
    "mlx5e_rq.mpwqe.umr_last_bulk": 202,
    "mlx5e_rq.mpwqe.umr_completed": 203,
    "mlx5e_rq.mpwqe.min_wqe_bulk": 204,
    "mlx5e_rq.mpwqe.pages_per_wqe": 206,
    "mlx5e_rq.mpwqe.umr_wqebbs": 207,
    "mlx5e_rq.mpwqe.umr_mode": 209,
    "mlx5e_rq.stats": 256,
    "mlx5e_rq.cq": 320,
    "mlx5e_rq.icosq_ptr": 912,
    "mlx5e_rq.state": 960,
    "mlx5e_rq.ix": 968,
    "mlx5e_rq.rqn": 1240,
    "mlx5e_rq.wq_type": 1236,
    "mlx5e_cq.wq": 0,                # mlx5_cqwq
    "mlx5e_cq.napi": 48,
    "mlx5e_cq.mcq": 56,
    "mlx5_cqwq.fbc": 0,
    "mlx5_cqwq.cc": 32,
    "mlx5_frag_buf_ctrl.frags": 0,
    "mlx5_frag_buf_ctrl.sz_m1": 8,
    "mlx5_frag_buf_ctrl.frag_sz_m1": 12,
    "mlx5_frag_buf_ctrl.strides_offset": 14,
    "mlx5_frag_buf_ctrl.log_sz": 16,
    "mlx5_frag_buf_ctrl.log_stride": 17,
    "mlx5_frag_buf_ctrl.log_frag_strides": 18,
    "mlx5_core_cq.cqn": 0,
    "mlx5_core_cq.cqe_sz": 4,
    "mlx5_core_cq.set_ci_db": 8,
    "mlx5_core_cq.arm_db": 16,
    "mlx5_core_cq.cons_index": 96,
    "mlx5_core_cq.arm_sn": 100,
    "mlx5_wq_ll.fbc": 0,
    "mlx5_wq_ll.db": 24,
    "mlx5_wq_ll.tail_next": 32,
    "mlx5_wq_ll.head": 40,
    "mlx5_wq_ll.wqe_ctr": 42,
    "mlx5_wq_ll.cur_sz": 44,
    "mlx5_wq_cyc.fbc": 0,
    "mlx5_wq_cyc.sz": 32,
    "mlx5_wq_cyc.wqe_ctr": 34,
    "mlx5_wq_cyc.cur_sz": 36,
    "mlx5e_icosq.cc": 0,
    "mlx5e_icosq.pc": 2,
    "mlx5e_icosq.cq": 64,
    "mlx5e_icosq.db_wqe_info": 448,
    "mlx5e_icosq.wq": 456,
    "mlx5e_icosq.sqn": 504,
    "mlx5e_icosq.state": 512,
    "mlx5_buf_list.buf": 0,
    "mlx5_buf_list.size": 16,
    "mlx5e_rq_stats.packets": 0,
    "mlx5e_rq_stats.wqe_err": 184,
    "mlx5e_rq_stats.mpwqe_filler_cqes": 192,
    "mlx5e_rq_stats.mpwqe_filler_strides": 200,
    "mlx5e_rq_stats.buff_alloc_err": 216,
    "mlx5e_rq_stats.congst_umr": 240,
    "mlx5e_ch_stats.events": 0,
    "mlx5e_ch_stats.poll": 8,
    "mlx5e_ch_stats.arm": 16,
    "mlx5e_ch_stats.eq_rearm": 40,
}
RQ_STATE_NAMES = ["ENABLED", "RECOVERING", "DIM", "NO_CSUM_COMPLETE",
                  "CSUM_FULL", "MINI_CQE_HW_STRIDX", "SHAMPO",
                  "MINI_CQE_ENHANCED", "XSK"]
CALIB = {}

print("== provenance: offsets from pahole -F dwarf mlx5_core.ko "
      "(v6.17.8 build, same config as running 6.17.8-061708-generic)")
for k in sorted(OFF):
    print(f"    {k} = {OFF[k]}")

# ---- drgn: kernel types only (napi_struct.state offset), kcore reads
prog = drgn.program_from_core_dump("/proc/kcore")
try:
    prog.load_debug_info([VMLINUX])
except drgn.MissingDebugInfoError:
    pass  # expected: module enumeration is unsupported on 6.17 by drgn 0.0.25
napi_state_off = next(m.offset for m in
                      prog.type("struct napi_struct").members
                      if m.name == "state")
print(f"== provenance: napi_struct.state offset {napi_state_off} "
      "(vmlinux DWARF)")

def rd(addr, n):
    return prog.read(addr, n)

def u(addr, n):
    return int.from_bytes(rd(addr, n), "little")

def s64(addr):
    return int.from_bytes(rd(addr, 8), "little", signed=True)

# ---- NAPI_STATE_* from the kernel's own source (enum in 6.17)
napi_bits = {}
_enum_txt = open(NETDEV_H).read()
_m = re.search(r"enum\s*\{([^}]*NAPI_STATE_SCHED[^}]*)\}", _enum_txt, re.S)
if _m:
    _v = 0
    for line in _m.group(1).splitlines():
        mm = re.match(r"\s*(NAPI_STATE_\w+)\s*(?:=\s*(\d+))?\s*,", line)
        if mm:
            _v = int(mm.group(2)) if mm.group(2) else _v
            napi_bits[mm.group(1)] = 1 << _v
            _v += 1
print("== NAPI_STATE_*:", ", ".join(f"{k}=0x{v:x}" for k, v in
                                    sorted(napi_bits.items())))

def decode_bits(val, names):
    on = [nm for nm, bit in names.items() if bit & val]
    return f"0x{val:x} [{','.join(on) if on else 'none'}]"

# ---- runtime address discovery: bpftrace while the probe floods
print("== discovery: bpftrace kprobe mlx5e_napi_poll + "
      "mlx5e_completion_event, 10k pps probe from 10.10.1.10")
BT = ("kprobe:mlx5e_napi_poll { printf(\"napi %lu\\n\", arg0); } "
      "kprobe:mlx5e_completion_event { printf(\"comp %lu\\n\", arg0); }")
bt = subprocess.Popen(["bpftrace", "-e", BT],
                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                      text=True)
time.sleep(2)
subprocess.run(["ssh", "-n", "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=8", "davidlin@10.10.1.10",
                "sudo", "bash", "-c",
                "nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 "
                "--sport 32704 --dport 7777 --rate 10000 --secs 8 "
                "--plen 64 --core 4 > /tmp/b2-probe.txt 2>&1 </dev/null &"],
               check=False, timeout=30)
try:
    out, _ = bt.communicate(timeout=14)
except subprocess.TimeoutExpired:
    bt.kill()
    out, _ = bt.communicate()

ch_addrs = set()
n_lines = comp_lines = 0
for line in out.splitlines():
    parts = line.split()
    if len(parts) != 2:
        continue
    kind, a = parts[0], int(parts[1])
    if kind == "napi":
        n_lines += 1
        ch_addrs.add(a - OFF["mlx5e_channel.napi"])
    elif kind == "comp":
        comp_lines += 1
        cq = a - OFF["mlx5e_cq.mcq"]          # mlx5_core_cq* -> mlx5e_cq*
        try:
            napi = u(cq + OFF["mlx5e_cq.napi"], 8)
            if 0xFFFF000000000000 > napi > 0xFFFF800000000000:
                ch_addrs.add(napi - OFF["mlx5e_channel.napi"])
        except Exception:
            pass
print(f"    bpftrace lines: napi={n_lines} comp={comp_lines} "
      f"-> {len(ch_addrs)} distinct channels")

priv_votes = collections.Counter()
for ch in ch_addrs:
    try:
        priv_votes[u(ch + OFF["mlx5e_channel.priv"], 8)] += 1
    except Exception:
        continue
if not priv_votes:
    sys.exit("no priv address discovered")
name_off = next(m.offset for m in prog.type("struct net_device").members
                if m.name == "name")
print("== priv candidates (netdev name read from memory):")
chosen = None
for p, votes in priv_votes.most_common():
    try:
        nd = u(p + OFF["mlx5e_priv.netdev"], 8)
        nm = rd(nd + name_off, 16).split(b"\x00")[0].decode()
    except Exception as e:
        nm = f"<unreadable {e}>"
    print(f"    0x{p:x} votes={votes} netdev={nm!r}")
    if nm == IFACE:
        chosen = p
if chosen is None:
    sys.exit(f"no priv candidate resolves to {IFACE}")
priv = chosen
print(f"    priv = 0x{priv:x} (netdev name match: {IFACE})")

cptr = u(priv + OFF["mlx5e_priv.channels"] + OFF["mlx5e_channels.c"], 8)
nch = u(priv + OFF["mlx5e_priv.channels"] + OFF["mlx5e_channels.num"], 4)
netdev = u(priv + OFF["mlx5e_priv.netdev"], 8)
print(f"    channels: c=0x{cptr:x} num={nch} priv.netdev=0x{netdev:x}")
chs = {}
for i in range(nch):
    a = u(cptr + 8 * i, 8)
    if a == 0:
        continue
    ix = s64(a + OFF["mlx5e_channel.ix"]) & 0xFFFFFFFF
    chs[ix] = a
    if ix != i:
        print(f"    WARNING c[{i}]=0x{a:x} but ix={ix}")
print(f"    channel ix map: {sorted(chs)}")
for want in (WEDGE_IX, HEALTH_IX):
    if want not in chs:
        sys.exit(f"channel {want} not present")

def icosq_line(tag, sq, ch_a):
    cc = u(sq + OFF["mlx5e_icosq.cc"], 2)
    pc = u(sq + OFF["mlx5e_icosq.pc"], 2)
    sqn = u(sq + OFF["mlx5e_icosq.sqn"], 4)
    wq = sq + OFF["mlx5e_icosq.wq"]
    sz = u(wq + OFF["mlx5_wq_cyc.sz"], 2)
    cur = u(wq + OFF["mlx5_wq_cyc.cur_sz"], 2)
    wctr = u(wq + OFF["mlx5_wq_cyc.wqe_ctr"], 2)
    st = u(sq + OFF["mlx5e_icosq.state"], 8)
    rel = ("channel.icosq" if sq == ch_a + OFF["mlx5e_channel.icosq"]
           else "channel.async_icosq"
           if sq == ch_a + OFF["mlx5e_channel.async_icosq"] else "other")
    print(f"    {tag}: sq=0x{sq:x} ({rel}) cc={cc} pc={pc} "
          f"outstanding(pc-cc)={pc - cc} sqn={sqn} wq.sz={sz} "
          f"wq.cur_sz={cur} wq.wqe_ctr={wctr} state=0x{st:x}")

def rq_line(tag, rq):
    print(f"    {tag} rq @ 0x{rq:x}:")
    st = u(rq + OFF["mlx5e_rq.state"], 8)
    bits = [RQ_STATE_NAMES[b] for b in range(len(RQ_STATE_NAMES))
            if st & (1 << b)]
    print(f"      state = 0x{st:x} [{','.join(bits) or 'none'}]")
    print(f"      rqn={u(rq + OFF['mlx5e_rq.rqn'], 4)} "
          f"wq_type={u(rq + OFF['mlx5e_rq.wq_type'], 1)} "
          f"ix={u(rq + OFF['mlx5e_rq.ix'], 4)}")
    wqll = rq + OFF["mlx5e_rq.union_wq"]
    print(f"      wq_ll: head={u(wqll + OFF['mlx5_wq_ll.head'], 2)} "
          f"wqe_ctr={u(wqll + OFF['mlx5_wq_ll.wqe_ctr'], 2)} "
          f"cur_sz={u(wqll + OFF['mlx5_wq_ll.cur_sz'], 2)} "
          f"(posted buffers)")
    print(f"      mpwqe: num_strides={u(rq + OFF['mlx5e_rq.mpwqe.num_strides'], 2)} "
          f"actual_wq_head={u(rq + OFF['mlx5e_rq.mpwqe.actual_wq_head'], 2)} "
          f"log_stride_sz={u(rq + OFF['mlx5e_rq.mpwqe.log_stride_sz'], 1)} "
          f"umr_in_progress={u(rq + OFF['mlx5e_rq.mpwqe.umr_in_progress'], 1)} "
          f"umr_last_bulk={u(rq + OFF['mlx5e_rq.mpwqe.umr_last_bulk'], 1)} "
          f"umr_completed={u(rq + OFF['mlx5e_rq.mpwqe.umr_completed'], 1)}")
    print(f"             min_wqe_bulk={u(rq + OFF['mlx5e_rq.mpwqe.min_wqe_bulk'], 1)} "
          f"pages_per_wqe={u(rq + OFF['mlx5e_rq.mpwqe.pages_per_wqe'], 1)} "
          f"umr_wqebbs={u(rq + OFF['mlx5e_rq.mpwqe.umr_wqebbs'], 1)} "
          f"umr_mode={u(rq + OFF['mlx5e_rq.mpwqe.umr_mode'], 1)}")
    icosq_ptr = u(rq + OFF["mlx5e_rq.icosq_ptr"], 8)
    ch_a = rq - OFF["mlx5e_channel.rq"]
    rel = ("channel.icosq" if icosq_ptr == ch_a + OFF["mlx5e_channel.icosq"]
           else "channel.async_icosq"
           if icosq_ptr == ch_a + OFF["mlx5e_channel.async_icosq"]
           else "OTHER")
    print(f"      rq.icosq -> 0x{icosq_ptr:x} ({rel})")
    st_ptr = u(rq + OFF["mlx5e_rq.stats"], 8)
    if st_ptr:
        g = lambda o: int.from_bytes(rd(st_ptr + o, 8), "little", signed=True)
        print(f"      rq.stats: packets={g(OFF['mlx5e_rq_stats.packets'])} "
              f"wqe_err={g(OFF['mlx5e_rq_stats.wqe_err'])} "
              f"mpwqe_filler_cqes={g(OFF['mlx5e_rq_stats.mpwqe_filler_cqes'])} "
              f"congst_umr={g(OFF['mlx5e_rq_stats.congst_umr'])} "
              f"buff_alloc_err={g(OFF['mlx5e_rq_stats.buff_alloc_err'])}")
    # --- the RQ's completion queue
    cq = rq + OFF["mlx5e_rq.cq"]
    fbc = cq + OFF["mlx5_cqwq.fbc"]
    cc = u(cq + OFF["mlx5_cqwq.cc"], 4)
    sz_m1 = u(fbc + OFF["mlx5_frag_buf_ctrl.sz_m1"], 4)
    log_sz = u(fbc + OFF["mlx5_frag_buf_ctrl.log_sz"], 1)
    log_stride = u(fbc + OFF["mlx5_frag_buf_ctrl.log_stride"], 1)
    lfs = u(fbc + OFF["mlx5_frag_buf_ctrl.log_frag_strides"], 1)
    frags = u(fbc + OFF["mlx5_frag_buf_ctrl.frags"], 8)
    cqn = u(cq + OFF["mlx5e_cq.mcq"] + OFF["mlx5_core_cq.cqn"], 4)
    cqe_sz = u(cq + OFF["mlx5e_cq.mcq"] + OFF["mlx5_core_cq.cqe_sz"], 4)
    mcq = cq + OFF["mlx5e_cq.mcq"]
    raw = rd(mcq, 192)
    CALIB["raw_hex"] = raw.hex()
    n_cqes = sz_m1 + 1
    print(f"      rq.cq: cqn={cqn} cqe_sz={cqe_sz} ncqes={n_cqes} "
          f"(log_sz={log_sz}) cc={cc} cons_index(calib skipped) "
          f"arm_sn(built-off)={int.from_bytes(raw[100:104], 'little')} "
          f"fbc.log_stride={log_stride} log_frag_strides={lfs}")
    # --- occupancy by completion timestamp (robust to cons_index
    # layout drift): the newest-written CQE is HW's producer head.
    nfrags = (n_cqes + (1 << lfs) - 1) >> lfs
    per_frag = 1 << lfs
    span = per_frag << log_stride
    fr = rd(frags, 16 * nfrags)
    frag_bufs = [int.from_bytes(fr[16 * i:16 * i + 8], "little")
                 for i in range(nfrags)]
    ts_at = {}
    op_at = {}
    for fi, fb in enumerate(frag_bufs):
        try:
            blob = rd(fb, span)
        except Exception as e:
            print(f"      cq walk: frag {fi} read fault: {e}")
            continue
        for j in range(per_frag):
            i = (fi << lfs) + j
            if i >= n_cqes:
                break
            ent = blob[j << log_stride:(j << log_stride) + 64]
            op_at[i] = ent[63]
            ts_at[i] = int.from_bytes(ent[48:56], "little")
    head = max(ts_at, key=lambda i: ts_at[i])
    max_ts = ts_at[head]
    pending = (head - ((cc - 1) % n_cqes)) % n_cqes
    behind = max_ts - ts_at[(cc - 1) % n_cqes]
    ph = (cc >> log_sz) & 1
    fwd = 0
    for k in range(n_cqes):
        if op_at.get((cc + k) % n_cqes, 0xFF) & 1 == ph:
            fwd += 1
        else:
            break
    hist = collections.Counter((op_at[i] >> 4) for i in
                               ((cc + k) % n_cqes for k in range(64)))
    print(f"      cq occupancy: HW writer head at index {head} "
          f"(cc={cc}) -> pending(unconsumed, incl. head)={pending}; "
          f"max_ts={max_ts} ts(cc-1)={ts_at[(cc - 1) % n_cqes]} "
          f"head-minus-(cc-1)={behind}")
    print(f"      cq owner-phase walk from cc (phase={ph}): {fwd} "
          f"consecutive HW-owned; opcode histogram of first 64 from cc: "
          f"{dict(hist)}")
    return {"cons": cc, "cc": cc, "pc_pending": fwd}

def ch_line(ix, tag):
    ch = chs[ix]
    print(f"== ch{ix} ({tag}) @ 0x{ch:x}")
    napi = ch + OFF["mlx5e_channel.napi"]
    st = u(napi + napi_state_off, 8)
    print(f"    napi.state = {decode_bits(st, napi_bits)}")
    cst = u(ch + OFF["mlx5e_channel.state"], 8)
    print(f"    channel.state = 0x{cst:x} "
          f"[{'XSK' if cst & 1 else 'no-xsk'}]")
    cpu = s64(ch + OFF["mlx5e_channel.cpu"]) & 0xFFFFFFFF
    print(f"    channel.cpu = {cpu}")
    st_ptr = u(ch + OFF["mlx5e_channel.stats"], 8)
    if st_ptr:
        g = lambda o: int.from_bytes(rd(st_ptr + o, 8), "little", signed=True)
        print(f"    ch.stats: events={g(0)} poll={g(8)} arm={g(16)} "
              f"eq_rearm={g(40)}")
    rq_line(f"ch{ix}", ch + OFF["mlx5e_channel.rq"])
    icosq_line("icosq", ch + OFF["mlx5e_channel.icosq"], ch)
    icosq_line("async_icosq", ch + OFF["mlx5e_channel.async_icosq"], ch)
    return {}

marks = {}
for snap in (1, 2):
    if snap == 2:
        time.sleep(GAP_S)
    print(f"\n######## SNAPSHOT {snap} {time.strftime('%H:%M:%S')}")
    print("== napi.state of all channels")
    for ix in sorted(chs):
        st = u(chs[ix] + OFF["mlx5e_channel.napi"] + napi_state_off, 8)
        print(f"    ch{ix}: {decode_bits(st, napi_bits)}")
    marks[snap] = ch_line(WEDGE_IX, "WEDGED") or {}
    ch_line(HEALTH_IX, "healthy comparison")
print("\n== done (facts only; interpretation held for the PI)")
