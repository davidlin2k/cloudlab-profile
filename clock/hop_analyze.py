#!/usr/bin/env python3
"""hop_analyze: per-hop conservation from a hop-*.txt sample file.
Hops: emitters (12 procs) -> HAProxy frontend -> HAProxy backends ->
sink. The hop where the rate drops is the bottleneck (PI spec A).

Usage: hop_analyze.py results/hop-<label>-<N>.txt
"""
import re
import sys

path = sys.argv[1]
samples = []
cur = None
for line in open(path):
    line = line.rstrip()
    if line.startswith("== sample"):
        m = re.search(r"t=(\d\d):(\d\d):(\d\d)", line)
        ts = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3)) if m else None
        cur = {"raw": [], "ts": ts}
        samples.append(cur)
        continue
    if cur is None:
        continue
    cur["raw"].append(line)


def parse(s):
    em = {"tok": 0, "byt": 0, "drop": 0, "slow": 0, "cpu": 0.0}
    hap_in = hap_out = 0
    hap_scur = 0
    sink_tok = sink_rate = sink_cpu = 0.0
    hap_cpu = 0.0
    for line in s["raw"]:
        m = re.match(
            r"streams=(\d+) tokens=(\d+) bytes=(\d+) dropped=(\d+) "
            r"slow_writes=(\d+) slot_overruns=(\d+) steps=(\d+) cpu_s=([\d.]+)", line)
        if m:
            em["tok"] += int(m.group(2))
            em["byt"] += int(m.group(3))
            em["drop"] += int(m.group(4))
            em["slow"] += int(m.group(5))
            em["cpu"] += float(m.group(8))
        elif line.startswith("hap ") and "FRONTEND" in line:
            mm = dict(kv.split("=") for kv in line.split()[3:] if "=" in kv)
            hap_in += int(mm.get("bin", 0))
            hap_out += int(mm.get("bout", 0))
            hap_scur = int(mm.get("scur", 0))
        elif line.startswith("hap CurrConns"):
            pass
        elif line.startswith("live=") or (line.startswith("rate=") and "tok/s" in line):
            mm = dict(kv.split("=") for kv in line.split() if "=" in kv)
            sink_tok = int(mm.get("tokens", 0))
            sink_rate = float(mm.get("rate", 0).split()[0] if mm.get("rate") else 0)
        elif line.startswith("Average") and line.rstrip().endswith("haproxy") and " |__" not in line:
            f = line.split()
            if len(f) > 8:
                try:
                    hap_cpu = float(f[8])  # %CPU of the process (TGID) row
                except ValueError:
                    pass
    return em, hap_in, hap_out, hap_scur, sink_tok, sink_rate


print(f"{'sample':>6} {'emit_tok/s':>11} {'emit_byt/s':>11} {'hap_bin/s':>11} "
      f"{'hap_bout/s':>11} {'sink_tok/s':>11} {'drops/s':>8} {'slow/s':>7} "
      f"{'em_cpu':>7} {'hap_cpu':>7}")
prev = None
rows = []
for i, s in enumerate(samples):
    p = parse(s)
    if prev is not None:
        em, hin, hout, scur, stk, srate = p
        pem, phin, phout, _, pstk, _ = prev
        dt = max((s["ts"] or 0) - (samples[i-1]["ts"] or 0), 1)
        dem = (em["tok"] - pem["tok"]) // dt
        dbyt = (em["byt"] - pem["byt"]) // dt
        dhin = (hin - phin) // dt
        dhout = (hout - phout) // dt
        dstk = (stk - pstk) // dt
        ddrop = (em["drop"] - pem["drop"]) // dt
        dslow = (em["slow"] - pem["slow"]) // dt
        dcpu = (em["cpu"] - pem["cpu"]) / dt
        rows.append((dem, dbyt, dhin, dhout, dstk, ddrop, dslow, dcpu))
        print(f"{i:6d} {dem:11d} {dbyt:11d} {dhin:11d} {dhout:11d} "
              f"{dstk:11d} {ddrop:8d} {dslow:7d} {dcpu:7.1f} {srate:7.0f}")
    prev = p

if rows:
    import statistics as st
    print("\n--- medians over the window (per second) ---")
    names = ["emit_tok/s", "emit_byt/s", "hap_bin/s", "hap_bout/s",
             "sink_tok/s", "drops/s", "slow_writes/s", "em_cpu_s/s"]
    for j, nm in enumerate(names):
        vals = sorted(r[j] for r in rows)
        print(f"{nm:>14}: {vals[len(vals)//2]:,}")
    print("\n--- conservation (median ratios) ---")
    mtok = st.median([r[0] for r in rows])
    mbyt = st.median([r[1] for r in rows])
    mhin = st.median([r[2] for r in rows])
    mhout = st.median([r[3] for r in rows])
    mstk = st.median([r[4] for r in rows])
    if mtok:
        print(f"hap_bin  / emit_bytes = {mhin/max(mbyt,1):.3f}  (1.0 = conserved)")
        print(f"hap_bout / emit_bytes = {mhout/max(mbyt,1):.3f}")
        print(f"sink_tok / emit_tok   = {mstk/max(mtok,1):.3f}")
    # the hop with the biggest drop is the limiter
    hops = {"emitters": mtok, "haproxy_out~": mhout / 96 if mhout else 0,
            "sink": mstk}
    print("\n--- limiter: the largest step-down is at/above that hop ---")
    for k, v in hops.items():
        print(f"{k:>12}: {v:,.0f} tok/s equiv")
