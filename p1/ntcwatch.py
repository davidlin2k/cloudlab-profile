#!/usr/bin/env python3
"""ntcwatch.py -- watch i40e rx7 ring indices for N seconds."""
import struct
import sys
import time

f = open("/proc/kcore", "rb")
hdr = f.read(64)
phoff, = struct.unpack_from("<Q", hdr, 32)
pe, pn = struct.unpack_from("<HH", hdr, 54)
f.seek(phoff)
segs = []
for _ in range(pn):
    ph = f.read(pe)
    t, = struct.unpack_from("<I", ph, 0)
    off, va = struct.unpack_from("<QQ", ph, 8)
    fs = struct.unpack_from("<Q", ph, 32)[0]
    if t == 1 and va:
        segs.append((va, va + fs, off))


def read(a, n):
    for lo, hi, o in segs:
        if lo <= a < hi:
            f.seek(o + (a - lo))
            d = f.read(n)
            if len(d) == n:
                return d
    raise OSError(hex(a))


def u64(a):
    return struct.unpack("<Q", read(a, 8))[0]


def u16(a):
    return struct.unpack("<H", read(a, 2))[0]


init = None
for line in open("/proc/kallsyms"):
    p = line.split()
    if len(p) >= 3 and p[2] == "init_net":
        init = int(p[0], 16)
        break
head = init + 176
nxt = u64(head)
dev = None
for _ in range(1024):
    if nxt == head or nxt == 0:
        break
    c = nxt - 344
    nm = read(c + 288, 16).split(b"\x00")[0].decode(errors="replace")
    if nm == "enp24s0f1np1":
        dev = c
        break
    nxt = u64(c + 344)
vsi = u64(dev + 2688)
rxr = u64(vsi + 3312)
r7 = u64(rxr + 56)
t0 = time.time()
while time.time() - t0 < 3:
    time.sleep(0.7)
    print("ntp=%d ntc=%d pkts=%d" % (u16(r7+128), u16(r7+140), u64(r7+152)))
