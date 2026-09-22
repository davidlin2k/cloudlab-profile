#!/usr/bin/env python3
"""trace2cdf.py -- pktemu replay trace -> ns-3 Homa message-size CDF.

Format consumed by contrib/homa's ReadMsgSizeDist: line 1 = mean message
size in 1430B packets (float), then "<size_in_pkts> <cumfrac>" ascending.
Usage:
  trace2cdf.py wai_full.trace --out wai.cdf
"""
import argparse, sys

def main():
    p = argparse.ArgumentParser()
    p.add_argument("trace")
    p.add_argument("--out", required=True)
    p.add_argument("--pkt-bytes", type=int, default=1430)
    a = p.parse_args()
    sizes = []
    for line in open(a.trace):
        f = line.split()
        if len(f) >= 2:
            sizes.append(int(f[1]))
    sizes.sort()
    n = len(sizes)
    if not n:
        sys.exit("empty trace")
    mean = sum(sizes) / n
    with open(a.out, "w") as f:
        f.write(f"{mean:.1f}\n")
        last = -1
        for i, s in enumerate(sizes):
            if s != last:
                f.write(f"{s} {(i + 1) / n:.6f}\n")
                last = s
    print(f"trace2cdf: {a.out}  n={n} mean={mean:.1f} pkt "
          f"({mean * a.pkt_bytes / 1e6:.2f} MB) max={sizes[-1]}")

if __name__ == "__main__":
    main()
