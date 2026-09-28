#!/usr/bin/env python3
"""t1b_qpkts.py -- print the i40e ring's per-queue packets counter (kcore).
Usage: t1b_qpkts.py <iface> <queue>   (the same offsets as t1b_probe.py)"""
import struct
import sys

IFACE = sys.argv[1]
Q = int(sys.argv[2])
OFF_NET_DEV_BASE = 176
OFF_ND_NAME = 288
OFF_ND_DEVLIST = 344
OFF_ND_PRIV = 2688
OFF_VSI_RXRINGS = 3304
OFF_RING_QUEUE_INDEX = 56
OFF_RING_COUNT = 132
OFF_RING_STATS = 152

f = open("/proc/kcore", "rb")
hdr = f.read(64)
phoff, = struct.unpack_from("<Q", hdr, 32)
phentsize, phnum = struct.unpack_from("<HH", hdr, 54)
f.seek(phoff)
segs = []
for _ in range(phnum):
    ph = f.read(phentsize)
    p_type, = struct.unpack_from("<I", ph, 0)
    p_offset, p_vaddr = struct.unpack_from("<QQ", ph, 8)
    p_filesz = struct.unpack_from("<Q", ph, 32)[0]
    if p_type == 1 and p_vaddr:
        segs.append((p_vaddr, p_vaddr + p_filesz, p_offset))


def read(addr, n):
    for lo, hi, off in segs:
        if lo <= addr < hi:
            f.seek(off + (addr - lo))
            d = f.read(n)
            if len(d) == n:
                return d
    raise OSError("unmapped 0x%x" % addr)


def u64(a):
    return struct.unpack("<Q", read(a, 8))[0]


def u16(a):
    return struct.unpack("<H", read(a, 2))[0]


init_net = None
for line in open("/proc/kallsyms"):
    p = line.split()
    if len(p) >= 3 and p[2] == "init_net":
        init_net = int(p[0], 16)
        break
head = init_net + OFF_NET_DEV_BASE
nxt = u64(head)
dev = None
for _ in range(1024):
    if nxt == head or nxt == 0:
        break
    cand = nxt - OFF_ND_DEVLIST
    try:
        nm = read(cand + OFF_ND_NAME, 16).split(b"\x00")[0].decode(
            errors="replace")
    except OSError:
        nm = ""
    if nm == IFACE:
        dev = cand
        break
    nxt = u64(cand + OFF_ND_DEVLIST)
vsi = u64(dev + OFF_ND_PRIV)
rxr = u64(vsi + OFF_VSI_RXRINGS)
ring = u64(rxr + Q * 8)
if u16(ring + OFF_RING_QUEUE_INDEX) != Q:
    sys.exit("ring sanity FAIL")
print(u64(ring + OFF_RING_STATS))