#!/usr/bin/env python3
"""Layered receive-path instrument for the step-clock test.

Samples, once per second, every layer the paper's law touches:
  NIC      ethtool -S rx_discards / rx_errors on the experiment port
  softirq  /proc/net/softnet_stat (dropped, time_squeeze per core)
  TCP      /proc/net/snmp + nstat (RetransSegs, RcvbufErrors,
           PruneCalled, RcvCollapsed, TCPMemoryPressures)
  sockets  /proc/net/sockstat (tcp mem pages, in-use sockets)
  CPU      /proc/stat softirq lines per core
  haproxy  admin socket session counters (if available)
Writes one JSONL line per second. Run on the proxy host (n1).
"""
import json
import subprocess
import sys
import time

NIC = sys.argv[1] if len(sys.argv) > 1 else "enp195s0np0"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/clock-instrument.jsonl"
DUR = int(sys.argv[3]) if len(sys.argv) > 3 else 3600


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""


def softnet():
    # per-core: processed, dropped, time_squeeze; columns 2,3,4 (0-indexed 1..3)
    out = []
    for line in read("/proc/net/softnet_stat").splitlines():
        f = line.split()
        if len(f) >= 4:
            out.append((int(f[1], 16), int(f[2], 16), int(f[3], 16)))
    return {"dropped": sum(x[1] for x in out), "squeeze": sum(x[2] for x in out)}


def softirq_cpu():
    tot = 0
    for line in read("/proc/stat").splitlines():
        if line.startswith("cpu") and len(line.split()) > 8:
            tot += int(line.split()[7])  # softirq jiffies
    return tot


def tcp_counters():
    d = {}
    lines = read("/proc/net/snmp").splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Tcp:") and i + 1 < len(lines) and lines[i + 1].startswith("Tcp:"):
            keys = line.split()[1:]
            vals = lines[i + 1].split()[1:]
            for k, v in zip(keys, vals):
                try:
                    d[k] = int(v)
                except ValueError:
                    pass
            break
    out = subprocess.run(["nstat", "-z", "-0"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 2 and any(k in f[0] for k in (
                "Retrans", "Prune", "Collapsed", "MemoryPress",
                "RcvbufErrors", "ListenOverflows", "ListenDrops",
                "TCPTimeouts", "DelayedACK")):
            try:
                d[f[0]] = int(f[1])
            except ValueError:
                pass
    return d


def sockstat():
    d = {}
    for line in read("/proc/net/sockstat").splitlines():
        f = line.split()
        if f and f[0] == "TCP:":
            d["tcp_inuse"] = int(f[2].lstrip("("))
            for i, w in enumerate(f):
                if w == "mem":
                    d["tcp_mem_pages"] = int(f[i + 1])
    return d


def nic_counters():
    out = subprocess.run(["ethtool", "-S", NIC], capture_output=True, text=True).stdout
    d = {}
    for line in out.splitlines():
        if ":" in line:
            k, _, v = line.strip().partition(":")
            k = k.strip()
            if k in ("rx_discards_phy", "rx_out_of_buffer", "rx_errors",
                     "rx_packets", "rx_dropped"):
                try:
                    d[k] = int(v)
                except ValueError:
                    pass
    return d


def main():
    t0 = time.time()
    with open(OUT, "w") as f:
        while time.time() - t0 < DUR:
            rec = {
                "t": round(time.time(), 3),
                "softnet": softnet(),
                "softirq_jiffies": softirq_cpu(),
                "tcp": tcp_counters(),
                "sock": sockstat(),
                "nic": nic_counters(),
            }
            f.write(json.dumps(rec) + "\n")
            f.flush()
            time.sleep(1)


if __name__ == "__main__":
    main()
