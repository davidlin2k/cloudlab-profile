#!/usr/bin/env python3
"""burst_analyze: from the proxy-NIC capture, measure achieved burst
width - packets per 100us bucket during the aligned emission window.
PI spec C: verify the burst is actually a burst (or a smear) before
calling any run 'aligned'.

Usage: burst_analyze.py <pcap>
"""
import struct
import sys
from collections import Counter

PCAP = sys.argv[1]
GH = 24  # global header

with open(PCAP, "rb") as f:
    magic = f.read(4)
    nano = magic == b"\xd4\xc3\xb2\xa1" or magic == b"\x4d\x3c\xb2\xa1"
    if magic not in (b"\xd4\xc3\xb2\xa1", b"\xa1\xb2\xc3\xd4",
                     b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d"):
        sys.exit("not a pcap: " + repr(magic))
    # nanosecond magics: 4d3cb2a1 / a1b23c4d
    nano = magic in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d")
    f.seek(GH)
    ts = []
    while True:
        h = f.read(16)
        if len(h) < 16:
            break
        sec, frac, incl, orig = struct.unpack("IIII", h)
        t = sec * 1_000_000 + (frac // 1000 if nano else frac)  # us
        ts.append(t)
        f.seek(incl, 1)

if not ts:
    sys.exit("no packets")

t0, t1 = ts[0], ts[-1]
span = (t1 - t0) / 1e6
print(f"packets={len(ts)} span={span:.3f}s mean_pps={len(ts)/max(span,1e-9):,.0f}")

# packets per 100us bucket
buckets = Counter((t - t0) // 100 for t in ts)
counts = sorted(buckets.values())
n = len(counts)
print(f"buckets_100us={n}  empty_buckets_excluded_from_quantiles")
print(f"pkts_per_100us: p10={counts[n//10]} p50={counts[n//2]} "
      f"p90={counts[9*n//10]} p99={counts[99*n//100]} max={counts[-1]}")
print(f"mean={sum(counts)/n:.1f}")

# burst width: at each step (25ms = 250 buckets), what fraction of the
# step's packets land in its first 1ms (10 buckets)? aligned => high;
# random => ~4%. Also report the 25ms-period autocorrelation proxy:
# the p99 of bucket counts vs the mean (peakedness).
step = 250  # 25ms in 100us buckets
frac_first_ms = []
for s in range(0, max(buckets) - step, step):
    tot = sum(buckets.get(s + k, 0) for k in range(step))
    if tot == 0:
        continue
    head = sum(buckets.get(s + k, 0) for k in range(10))
    frac_first_ms.append(head / tot)
if frac_first_ms:
    frac_first_ms.sort()
    m = len(frac_first_ms)
    print(f"fraction of each 25ms step's packets in its first 1ms: "
          f"p10={frac_first_ms[m//10]:.3f} p50={frac_first_ms[m//2]:.3f} "
          f"p90={frac_first_ms[9*m//10]:.3f} (aligned~0.9+, random~0.04)")
peaked = counts[99 * n // 100] / max(sum(counts) / n, 0.01)
print(f"peakedness p99/mean = {peaked:.1f} (aligned>>1, random~1-2)")
