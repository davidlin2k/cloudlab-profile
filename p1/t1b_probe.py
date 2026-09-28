#!/usr/bin/env python3
"""t1b_probe.py -- the i40e readiness probe for T1B (specs/p1-T1B.md).

Port of rq1_probe.py's strand detection to i40e/Intel X710:
  STRANDED = the RX descriptor at next_to_clean has its descriptor-done
  (DD) bit set while next_to_clean is frozen for more than 50 ms.
Per DR-015 the coarse fallback = the queue's rx_packets frozen while
the port's drop counters climb; this probe records BOTH so the cell
records which detector classified it.

Usage: t1b_probe.py <iface> <queue> <out_csv> <duration_s> [--pid PID]
Writes <out_csv> at ~1 kHz and a summary on stdout.

CSV schema: ts_ms,ntc,dd,rxq_pkts,rxq_drops,port_drops,irq_cpu,arm
  (arm/cpu columns filled from the env T1B_ARM / T1B_IRQCPU.)
"""
import os
import sys
import time

import drgn
from drgn import cast
from drgn.helpers.linux.net import find_netdev

IFACE = sys.argv[1]
Q = int(sys.argv[2])
OUT = sys.argv[3]
DUR = float(sys.argv[4])
ARM = os.environ.get("T1B_ARM", "?")
IRQCPU = os.environ.get("T1B_IRQCPU", "?")

prog = drgn.program_from_kernel()
try:
    prog.load_debug_info([], main=False)  # rely on BTF (distro kernel)
except Exception:
    pass

netdev = find_netdev(prog, IFACE)
if not netdev:
    sys.exit("no such netdev: " + IFACE)
np = cast("struct i40e_netdev_priv *", netdev.priv)
vsi = np.vsi
try:
    ring = vsi.rx_rings[Q]
except Exception:
    ring = vsi.rx_rings.rx_ring[Q]
print("ring=%#x count=%d" % (ring.value_(), ring.count.value_()),
      file=sys.stderr)

desc_base = ring.desc
stride = 16  # union i40e_rx_desc = 2 qwords
count = ring.count.value_()


def qw1_at(ntc):
    addr = desc_base.value_() + ntc * stride + 8
    o = drgn.Object(prog, "unsigned long", address=addr)
    return int(o.read_())


def read_sys(path):
    try:
        return int(open(path).read().strip())
    except Exception:
        return -1


sysdir = "/sys/class/net/%s/queues/rx-%d" % (IFACE, Q)
os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
f = open(OUT, "w")
f.write("ts_ms,ntc,dd,rxq_pkts,rxq_drops,port_drops,irq_cpu,arm\n")

t0 = time.time()
ntc_prev = dd_prev = -1
frozen_ms = 0.0
last_t = t0
n = 0
strand_ms = 0.0
verdict = "none"
while (t1 := time.time()) - t0 < DUR:
    ntc = ring.next_to_clean.value_()
    qw1 = qw1_at(ntc)
    dd = qw1 & 1  # I40E_RX_DESC_STATUS_DD = bit 0
    rxq_pkts = read_sys(sysdir + "/rx_packets")
    rxq_drops = read_sys(sysdir + "/rx_dropped")
    port_drops = read_sys("/sys/class/net/%s/statistics/rx_dropped" % IFACE)
    if ntc == ntc_prev and dd == 1:
        strand_ms += (t1 - last_t) * 1000
        if strand_ms > 50 and verdict == "none":
            verdict = "stranded-dd"
    else:
        strand_ms = 0.0
        verdict = "none"
    f.write("%.1f,%d,%d,%d,%d,%d,%s,%s\n" % (
        (t1 - t0) * 1000, ntc, dd, rxq_pkts, rxq_drops, port_drops,
        IRQCPU, ARM))
    ntc_prev, dd_prev, last_t = ntc, dd, t1
    n += 1
    time.sleep(0.001)
f.close()
print("T1B-PROBE-DONE n=%d verdict=%s" % (n, verdict))