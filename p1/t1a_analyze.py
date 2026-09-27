#!/usr/bin/env python3
"""p1/t1a_analyze.py -- the per-gap device-state classification
(DR-013 T1a, specs/p1-T1A.md, counts only).

Inputs: <probe.csv> (v4: eq_ci/eq_devw/eq_cqn0/irq_*/rx_* columns),
<analyze.txt> (the DR-011 gap classification with the probe->trace
offset line), <eqint.log> (the v2 logger: WALL, BEGIN, E and I lines).

Per stranded gap (>=200 ms packets-flat, owned throughout), report:
  - the class (from the trace join),
  - eq_ci frozen across the gap? and the max eq_devw bits in-gap
    (DEVICE-WRITTEN = unconsumed EQEs),
  - I-lines (hardware IRQ entries) and E-lines (completion events)
    inside the gap (logger, wall-joined),
  - rx_oob at gap start vs end, irq affinity at the nearest 1 Hz
    sample,
  - the branch call per the frozen table:
      1 (interrupt delivery): device-written EQEs in-gap AND zero
        I-lines in-gap;
      3 (device/firmware): no device-written EQE in-gap AND zero
        I-lines AND the CQ shows unconsumed owned CQEs and the last
        E line precedes the gap;
      1/2 (unresolved split): device-written EQEs + zero I-lines is
        ALSO the signature of a lost re-arm (the MMIO commit is not
        host-readable); rows 1 and 2 are reported jointly unless the
        affinity evidence at onset says otherwise.
Facts only; no theory.
"""
import re
import sys

probe_csv, analyze_txt, eqlog = sys.argv[1], sys.argv[2], sys.argv[3]

rows = []
with open(probe_csv) as f:
    hdr = f.readline().strip().split(",")
    idx = {k: i for i, k in enumerate(hdr)}
    for line in f:
        p = line.rstrip("\n").split(",")
        if len(p) < len(hdr):
            continue
        try:
            rows.append({
                "ts": float(p[idx["ts_ms"]]),
                "cc": int(p[idx["cc"]]),
                "owned": p[idx["owned"]] == "True",
                "pkt": int(p[idx["packets"]]),
                "eq_ci": int(p[idx["eq_ci"]]),
                "eq_devw": int(p[idx["eq_devw"]]) if p[idx["eq_devw"]] else 0,
                "eq_cqn0": p[idx["eq_cqn0"]],
                "irq_aff": p[idx["irq_aff"]],
                "rx_oob": int(p[idx["rx_oob"]]) if p[idx["rx_oob"]] else None,
            })
        except (ValueError, KeyError):
            continue

# the offset (probe->trace) from the analyze output
off = None
for line in open(analyze_txt):
    m = re.search(r"probe->trace offset[: ]+([0-9.]+)", line)
    if m:
        off = float(m.group(1))

# the classified gaps (trace time -> probe time)
cls_gaps = []
for line in open(analyze_txt):
    m = re.match(r"GAP t=([0-9.]+)\.\.([0-9.]+) dur=([0-9]+)ms .*-> (\S+)", line)
    if m and off is not None:
        cls_gaps.append((float(m.group(1)) - off, float(m.group(2)) - off,
                         m.group(4)))

# probe-side stranded gaps (>=200 ms packets flat + owned throughout)
gaps = []
start = 0
for i in range(1, len(rows)):
    if rows[i]["pkt"] != rows[i - 1]["pkt"]:
        if rows[i]["ts"] - rows[start]["ts"] >= 200.0:
            seg = rows[start:i]
            if all(r["owned"] for r in seg):
                gaps.append((start, i))
        start = i
if rows and rows[-1]["ts"] - rows[start]["ts"] >= 200.0:
    seg = rows[start:]
    if all(r["owned"] for r in seg):
        gaps.append((start, len(rows)))

# the logger: WALL/BEGIN anchors + E/I lines (rel us)
wall0 = begin = None
ev = []  # (tag, rel_us, cpu)
for line in open(eqlog):
    if line.startswith("WALL "):
        wall0 = float(line.split()[1])
    elif line.startswith("BEGIN "):
        begin = int(line.split()[1])
    else:
        p = line.split()
        if len(p) == 3 and p[0] in ("E", "I") and begin is not None:
            try:
                ev.append((p[0], (int(p[1]) - begin) // 1000, int(p[2])))
            except ValueError:
                continue

# the logger's rel-us are relative to ITS start; the probe's ts_ms are
# relative to the probe start. The logger starts AFTER the probe: join
# by the irq_percpu/aff columns is not needed -- instead join via the
# E-line timing against the probe's events counter... simplest exact
# join: the logger started at probe-ts L (unknown); BUT the E/I lines'
# ABSENCE inside a gap needs only relative time INSIDE the logger's
# own window mapped onto probe time. Use the gap boundaries: convert
# the probe gap [gs, ge] (probe-ms) into logger-rel via the offset
# between the two clocks -- derived from the last gap-free region is
# circular. The runner starts the logger ~15 s after the probe: use
# the FIRST E line's probe-time nearest-neighbour match is fragile.
# EXACT join instead: the probe writes its wall t0 to probe.meta
# ("wall_t0 <s>"); the logger writes WALL at its launch. Both files
# are passed here via the meta path when given (argv[4]); the join:
# logger_wall(rel) = WALL + rel/1e6 (rel in us -> s); probe_wall(ms)
# = wall_t0 + ts/1000. In-gap test: |probe gap window in wall time|
# vs the E/I lines' wall times.
meta_wall = None
if len(sys.argv) > 4:
    try:
        for line in open(sys.argv[4]):
            if line.startswith("wall_t0"):
                meta_wall = float(line.split()[1])
    except OSError:
        pass

def logger_in_gap(g0_ms, g1_ms):
    # returns (n_E, n_I) inside the gap using the wall-clock join
    if meta_wall is None or wall0 is None:
        return None, None
    w0 = meta_wall + g0_ms / 1000.0
    w1 = meta_wall + g1_ms / 1000.0
    nE = nI = 0
    for tag, rel_us, _ in ev:
        wt = wall0 + rel_us / 1e6
        if w0 <= wt <= w1:
            nE += tag == "E"
            nI += tag == "I"
    return nE, nI

def classify(g0, g1, seg):
    devw = max(r["eq_devw"] for r in seg)
    ci_set = {r["eq_ci"] for r in seg}
    nE, nI = logger_in_gap(g0, g1)
    oob0 = next((r["rx_oob"] for r in seg if r["rx_oob"] is not None), None)
    oob1 = next((r["rx_oob"] for r in reversed(seg)
                 if r["rx_oob"] is not None), None)
    aff = next((r["irq_aff"] for r in seg if r["irq_aff"]), "")
    if devw > 0 and nI == 0:
        branch = "1/2-unconsumed-EQEs+no-IRQ"
    elif devw == 0 and nI == 0 and nE == 0:
        branch = "3-device/firmware"
    elif nI and nI > 0:
        branch = f"IRQ-firing-in-gap({nI})"
    else:
        branch = "unclassified"
    return (devw, len(ci_set) == 1, nE, nI, oob0, oob1, aff, branch)

print(f"gaps: {len(gaps)} stranded; classified-join: {len(cls_gaps)}; "
      f"wall-join: {'ok' if meta_wall is not None and wall0 is not None else 'MISSING'}")
for a, b in gaps:
    g0, g1 = rows[a]["ts"], rows[b - 1]["ts"]
    seg = rows[a:b]
    cls = next((c for cg0, cg1, c in cls_gaps
                if abs(cg0 - g0 / 1000.0) < 0.5), "?")
    devw, cifrozen, nE, nI, oob0, oob1, aff, branch = classify(g0, g1, seg)
    oobs = f"oob {oob0}->{oob1}" if oob0 is not None and oob1 is not None else "oob ?"
    print(f"GAP t={g0 / 1000:.3f}..{g1 / 1000:.3f} ({(g1 - g0):.0f} ms) "
          f"class={cls} eq_ci_frozen={cifrozen} eq_devw_max={devw} "
          f"E_in={nE} I_in={nI} {oobs} aff={aff or '?'} -> {branch}")