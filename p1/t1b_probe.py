#!/usr/bin/env python3
"""t1b_probe.py -- the i40e readiness probe for T1B (specs/p1-T1B.md).

Raw-kcore port of rq1_probe.py (drgn is unusable on the mainline 6.17.8
kernel: no DWARF, and the i40e structs are absent from both BTFs).
All struct offsets are hand-derived from the 6.17.8 i40e sources and
cross-checked at startup against live values (ring count, queue_index).

Usage: t1b_probe.py <iface> <queue> <out_csv> <duration_s>
Writes <out_csv> at ~1 kHz and a summary on stdout.

Detector (per specs/p1-T1B.md): pending = the descriptor-done bit set
on any reposted slot in [ntp, ntu); STRANDED = pending while
next_to_process is frozen > 50 ms (primary, detector=DD).  Coarse
fallback = the queue's packet counter frozen > 50 ms while the port's
drop counter climbs (detector=PKT); both recorded per row.

CSV schema: ts_ms,ntp,ntp_prev,ntc,ntu,dd_ntp,pending,pkts,pkts_prev,
            drops,drops_prev,strand_ms,detector,irq_cpu,arm
"""
import os
import struct
import sys
import time

IFACE = sys.argv[1]
Q = int(sys.argv[2])
OUT = sys.argv[3]
DUR = float(sys.argv[4]) if len(sys.argv) > 4 else 330.0
STRAND_MS = 50.0
ARM = os.environ.get("T1B_ARM", "?")
IRQCPU = os.environ.get("T1B_IRQCPU", "?")

# ---- offsets (hand-derived from the 6.17.8 i40e sources + vmlinux BTF) ----
OFF_NET_DEV_BASE = 176      # struct net.dev_base_head
OFF_ND_NAME = 288           # struct net_device.name (char[16])
OFF_ND_DEVLIST = 344        # struct net_device.dev_list (list_head)
OFF_ND_PRIV = 2688          # struct net_device.priv area
OFF_PRIV_VSI = 0            # struct i40e_netdev_priv.vsi
OFF_VSI_RXRINGS = 3304      # struct i40e_vsi.rx_rings (6.17.8 layout!
                            # 3312 = tx_rings; verified vs ethtool:
                            # ring[7].stats.packets == rx-7.packets)
OFF_RING_DESC = 8
OFF_RING_QUEUE_INDEX = 56
OFF_RING_COUNT = 132
OFF_RING_NTP = 128
OFF_RING_NTC = 140
OFF_RING_NTU = 138
OFF_RING_SIZE = 224         # ring->size (desc bytes) -> stride derivation
OFF_RING_STATS = 152        # struct i40e_queue_stats: packets@0, bytes@8
OFF_VSI_ETH_STATS = 3008     # struct i40e_vsi.eth_stats
OFF_ETH_RX_DISCARDS = 32     # rx_discards = 5th u64 of i40e_eth_stats
DESC_SZ = 16                # union i40e_rx_desc = 16 bytes; DD = qword1 bit 0


class KCore:
    def __init__(self):
        self.f = open("/proc/kcore", "rb")
        hdr = self.f.read(64)
        phoff, = struct.unpack_from("<Q", hdr, 32)
        phentsize, phnum = struct.unpack_from("<HH", hdr, 54)
        self.f.seek(phoff)
        self.segs = []
        for _ in range(phnum):
            ph = self.f.read(phentsize)
            p_type, = struct.unpack_from("<I", ph, 0)
            p_offset, p_vaddr = struct.unpack_from("<QQ", ph, 8)
            p_filesz = struct.unpack_from("<Q", ph, 32)[0]
            if p_type == 1 and p_vaddr:
                self.segs.append((p_vaddr, p_vaddr + p_filesz, p_offset))

    def read(self, addr, n):
        for lo, hi, off in self.segs:
            if lo <= addr < hi:
                self.f.seek(off + (addr - lo))
                d = self.f.read(n)
                if len(d) == n:
                    return d
        raise OSError("kcore: unmapped 0x%x" % addr)

    def u64(self, addr):
        return struct.unpack("<Q", self.read(addr, 8))[0]

    def u16(self, addr):
        return struct.unpack("<H", self.read(addr, 2))[0]


KC = KCore()

# init_net via kallsyms (a static symbol: not in BTF)
init_net = None
for line in open("/proc/kallsyms"):
    p = line.split()
    if len(p) >= 3 and p[2] == "init_net":
        init_net = int(p[0], 16)
        break
if init_net is None:
    sys.exit("init_net not in kallsyms")

head = init_net + OFF_NET_DEV_BASE
nxt = KC.u64(head)
dev = None
for _ in range(1024):
    if nxt == head or nxt == 0:
        break
    cand = nxt - OFF_ND_DEVLIST
    try:
        nm = KC.read(cand + OFF_ND_NAME, 16).split(b"\x00")[0].decode(
            errors="replace")
    except OSError:
        nm = ""
    if nm == IFACE:
        dev = cand
        break
    nxt = KC.u64(cand + OFF_ND_DEVLIST)
if dev is None:
    sys.exit("netdev %s not found" % IFACE)

vsi = KC.u64(dev + OFF_ND_PRIV + OFF_PRIV_VSI)
rxr = KC.u64(vsi + OFF_VSI_RXRINGS)
ring = KC.u64(rxr + Q * 8)
qi = KC.u16(ring + OFF_RING_QUEUE_INDEX)
cnt = KC.u16(ring + OFF_RING_COUNT)
if qi != Q or cnt not in (256, 512, 1024, 2048, 4096):
    sys.exit("ring sanity FAIL: queue_index=%d count=%d" % (qi, cnt))
desc = KC.u64(ring + OFF_RING_DESC)
print("ring=%#x count=%d desc=%#x" % (ring, cnt, desc), file=sys.stderr)


def read_sys(path):
    try:
        return int(open(path).read().split()[0])
    except Exception:
        return -1


def q_pkts(ringp):
    """The ring's own packets counter (the i40e per-queue stat)."""
    try:
        return KC.u64(ringp + OFF_RING_STATS)
    except OSError:
        return -1


def port_drops():
    """The vsi's eth_stats.rx_discards (the port-level drop counter)."""
    try:
        return KC.u64(vsi + OFF_VSI_ETH_STATS + OFF_ETH_RX_DISCARDS)
    except OSError:
        return -1


sysdir = "/sys/class/net/%s/queues/rx-%d" % (IFACE, Q)
os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
f = open(OUT, "w")
f.write("ts_ms,ntp,ntp_prev,ntc,ntu,dd_ntp,pending,pkts,pkts_prev,"
        "drops,drops_prev,strand_ms,detector,irq_cpu,arm\n")

t0 = time.time()
ntp_prev, pkts_prev, drops_prev = -1, -1, -1
last_t = t0
strand_ms = 0.0
max_strand = 0.0
verdict = ""
n = 0
while (t1 := time.time()) - t0 < DUR:
    ntp = KC.u16(ring + OFF_RING_NTP)
    ntc = KC.u16(ring + OFF_RING_NTC)
    ntu = KC.u16(ring + OFF_RING_NTU)
    dd_ntp = KC.u64(desc + (ntp % cnt) * DESC_SZ + 8) & 1
    pend = 0
    k = (ntu - ntp) % cnt           # posted-but-unconsumed slots
    if k > 16:
        k = 16
    for i in range(k):
        if KC.u64(desc + ((ntp + i) % cnt) * DESC_SZ + 8) & 1:
            pend = 1
            break
    pkts = q_pkts(ring)
    drops = port_drops()
    det = ""
    climbing = drops > drops_prev and drops >= 0
    if ntp == ntp_prev and (pend or (pkts == pkts_prev and climbing)):
        strand_ms += (t1 - last_t) * 1000
        if strand_ms > STRAND_MS and not verdict:
            if pend:
                verdict = "stranded-dd"
                det = "DD"
            else:
                verdict = "frozen-pkt"
                det = "PKT"
    else:
        strand_ms = 0.0
        verdict = ""
    max_strand = max(max_strand, strand_ms)
    f.write("%.1f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.1f,%s,%s,%s\n" % (
        (t1 - t0) * 1000, ntp, ntp_prev, ntc, ntu, dd_ntp, pend,
        pkts, pkts_prev, drops, drops_prev, strand_ms, det, IRQCPU, ARM))
    ntp_prev, pkts_prev, drops_prev, last_t = ntp, pkts, drops, t1
    n += 1
    time.sleep(0.001)
f.close()
print("T1B-PROBE-DONE n=%d max_strand=%.1fms verdict=%s ntp=%d pkts=%d"
      % (n, max_strand, verdict or "none", ntp_prev, pkts_prev))