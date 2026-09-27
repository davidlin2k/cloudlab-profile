#!/usr/bin/env python3
"""p1/arm_sn_analyze.py -- the stale-arm statistic (DR-012 step 2,
specs/p1-ARM_SN.md, counts only).

Inputs:
  1. probe.csv from an ARM_SN cell (rq1_probe.py v3: arm_sn + adb_sn
     columns).
  2. the migrate_analyze.py per-gap output for the same cell (the GAP
     lines with the DR-011 class + the printed probe->trace offset),
     so the stale-arm relation can be cross-referenced with the gap
     classes.

Model (from the frozen spec's operational signature, made host-
countable): during an event-silent gap NO completion events fire, so
cq->arm_sn (the software counter, read via kcore) is FROZEN across
the gap. The arm doorbell record (arm_db, committed by the last
mlx5_cq_arm) freezes with it. Then:
  - adb_sn == arm_sn & 3 for the whole gap  -> the last arm carried
    the current sn (a CLEAN arm; the device accepted it and the
    silence needs another explanation: moderation);
  - adb_sn == (arm_sn - 1) & 3 SUSTAINED across the gap -> the last
    doorbell committed one sn BEHIND the counter, i.e. arm_sn
    advanced between the read and the doorbell write (a STALE arm;
    the device rejected it). This is the memo's race signature.
  - anything else (the counter advancing mid-gap) means events DID
    arrive during the "gap" -- a probe/trace bookkeeping artifact.

The transient lag-1 state is NORMAL between an event and the next arm
in the live regime; only a lag SUSTAINED across a stranded gap counts.

Usage: arm_sn_analyze.py <probe.csv> <analyze_out.txt> [min_gap_ms]
"""
import csv
import re
import sys

probe_csv, analyze_txt = sys.argv[1], sys.argv[2]
MIN_GAP_MS = float(sys.argv[3]) if len(sys.argv) > 3 else 200.0

# ---- probe side ------------------------------------------------------
rows = []
with open(probe_csv) as f:
    for r in csv.DictReader(f):
        rows.append(dict(ts=float(r["ts_ms"]) / 1000.0,
                         pkt=int(r["packets"]),
                         owned=r["owned"] == "True",
                         arm_sn=int(r["arm_sn"]),
                         adb_sn=int(r["adb_sn"])))

gaps = []          # (start_idx, end_idx) probe-sample indices
start = 0
for i in range(1, len(rows)):
    if rows[i]["pkt"] != rows[i - 1]["pkt"]:
        if (rows[i]["ts"] - rows[start]["ts"]) * 1000 >= MIN_GAP_MS:
            gaps.append((start, i))
        start = i
if rows and (rows[-1]["ts"] - rows[start]["ts"]) * 1000 >= MIN_GAP_MS:
    gaps.append((start, len(rows)))

def rel(s):
    """class of one sample's arm relation"""
    a, d = s["arm_sn"] & 3, s["adb_sn"]
    if a == d:
        return "equal"
    if d == (a - 1) & 3:
        return "lag1"
    return "other"

# ---- classified gaps from the analyze output -------------------------
off = None
m = re.search(r"probe->trace offset:\s*([0-9.]+)\s*s", open(analyze_txt).read())
if m:
    off = float(m.group(1))
cls_gaps = []      # (t0, t1, class) in TRACE time
for line in open(analyze_txt):
    g = re.match(r"GAP t=([0-9.]+)\.\.([0-9.]+) .*-> (\S+)", line)
    if g:
        cls_gaps.append((float(g.group(1)), float(g.group(2)), g.group(3)))

def class_for(t0_probe):
    """the DR-011 class of the classified gap covering this probe time"""
    if off is None:
        return "?"
    tt = t0_probe + off
    best, bestd = None, 1e9
    for a, b, c in cls_gaps:
        d = min(abs(tt - a), abs(tt - b))
        if a - 0.5 <= tt <= b + 0.5 and d < bestd:
            best, bestd = c, d
    return best or "unclassified"

# ---- the statistic ---------------------------------------------------
print(f"probe: {len(rows)} samples, {len(gaps)} flat gaps >= {MIN_GAP_MS:.0f} ms")
print("cell gaps: start_s end_s dur_ms relation(equal/lag1/other) "
      "stale_candidate class")
n_stale = n_clean = n_other = n_unc = 0
for a, b in gaps:
    seg = rows[a:b]
    counts = {"equal": 0, "lag1": 0, "other": 0}
    for s in seg:
        counts[rel(s)] += 1
    modal = max(counts, key=lambda k: counts[k])
    t0, t1 = seg[0]["ts"], seg[-1]["ts"]
    klass = class_for(t0)
    cand = "STALE-CAND" if modal == "lag1" else (
        "clean" if modal == "equal" else "mixed")
    if modal == "lag1":
        n_stale += 1
    elif modal == "equal":
        n_clean += 1
    else:
        n_other += 1
    if klass in ("?", "unclassified"):
        n_unc += 1
    print(f"GAP {t0:.3f} {t1:.3f} {(t1 - t0) * 1000:.0f}ms "
          f"{counts['equal']}/{counts['lag1']}/{counts['other']} "
          f"{cand} {klass}")
print(f"SUMMARY: gaps={len(gaps)} stale_cand={n_stale} clean={n_clean} "
      f"mixed={n_other} unclassed={n_unc}")
print(f"DECISION INPUT: stale candidates among event-silent gaps = "
      f"the STALE-CAND rows whose class is event-silent")
