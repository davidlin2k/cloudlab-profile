#!/usr/bin/env python3
"""p1/a0_parse.py -- Amendment A outcome per A0 cell.

Usage: a0_parse.py <cell-dir> [<cell-dir> ...]
Reads <cell-dir>/quiet.csv (1 Hz ts,rx7,rx_out_of_buffer) and
<cell-dir>/cell.env (the PROBE verdict) and prints, per cell:
  quiet_advance (rx7_packets over the 300 s quiet window),
  oob_advance, probe verdict,
  classification per the pre-registered rule:
    PERMANENT-LATCH: quiet_advance == 0 AND probe == PROBE-DEAD
    DEEP-TRICKLE:    quiet_advance > 0 OR probe == PROBE-OK
Facts only.
"""
import sys

for d in sys.argv[1:]:
    try:
        rows = [r.strip().split(",") for r in open(f"{d}/quiet.csv") if r.strip()]
        rx = [int(r[1]) for r in rows if len(r) >= 2 and r[1].isdigit()]
        oob = [int(r[2]) for r in rows if len(r) >= 3 and r[2].isdigit()]
        qadv = rx[-1] - rx[0] if len(rx) >= 2 else None
        oadv = oob[-1] - oob[0] if len(oob) >= 2 else None
    except FileNotFoundError:
        print(f"{d}: no quiet.csv (not an A0 cell or sampler failed)")
        continue
    probe = ""
    try:
        for line in open(f"{d}/cell.env"):
            if "PROBE-" in line:
                probe = line.split()[-1]
    except FileNotFoundError:
        pass
    if qadv is None:
        print(f"{d}: quiet.csv empty")
        continue
    cls = "PERMANENT-LATCH" if (qadv == 0 and "DEAD" in probe) else "DEEP-TRICKLE"
    print(f"{d}: quiet_adv={qadv} oob_adv={oadv} probe={probe or '?'} -> {cls}")
