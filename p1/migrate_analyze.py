#!/usr/bin/env python3
"""p1/migrate_analyze.py -- the wake-loss / migration analysis for
p1-MIGRATE cells (specs/p1-MIGRATE.md measurement 2).

Joins (a) the readiness probe csv (cc advances, owned, packets) with
(b) `trace-cmd report` of the cell's TRACE=1 capture. The probe's ts
is cell-relative; the trace's ts is mono -- the two are aligned by
matching the cc-advance sequence to the ch7 poll sequence (nearly
1:1 in the trickle regime), taking the offset from the largest
run of coincidences.

Per stranded gap (packets flat, owned throughout) it reports:
  the wake events in the window (IRQ-side __napi_schedule, the
  thread's sched_wakeup / sched_switch-in), the migrations of the
  thread near the gap, and the LOST-WAKE candidates: __napi_schedule
  with no thread wakeup within WAKE_US and no cc advance within
  WAKE_MS.

Usage: migrate_analyze.py <probe.csv> <trace.dat> <napi_pid> <ch_napi_addr_hex>
"""
import csv
import re
import subprocess
import sys

probe_csv, trace_dat = sys.argv[1], sys.argv[2]
tpid = int(sys.argv[3])
ch_napi = sys.argv[4].lower()          # ch struct addr + 10000, hex string
WAKE_US = 100
WAKE_MS = 5

# ---- the probe side -------------------------------------------------
rows = []
with open(probe_csv) as f:
    for r in csv.DictReader(f):
        rows.append(dict(ts=float(r["ts_ms"]) / 1000.0,   # ms -> s
                         cc=int(r["cc"]),
                         owned=r["owned"] == "True",
                         pkt=int(r["packets"])))
gaps = []
start = 0
for i in range(1, len(rows)):
    if rows[i]["pkt"] != rows[i - 1]["pkt"]:
        if rows[i]["ts"] - rows[start]["ts"] >= 0.2:
            gaps.append((start, i))
        start = i
if rows and rows[-1]["ts"] - rows[start]["ts"] >= 0.2:
    gaps.append((start, len(rows)))
stranded = [(a, b) for a, b in gaps if all(r["owned"] for r in rows[a:b])]
print(f"probe: {len(rows)} samples, {len(gaps)} gaps, "
      f"{len(stranded)} stranded (owned throughout)")

# ---- the trace side -------------------------------------------------
txt = subprocess.run(["trace-cmd", "report", trace_dat],
                     capture_output=True, text=True).stdout
line_re = re.compile(
    r"^\s*(\S+)-(\d+)\s+\[(\d+)\]\s+([\d.]+):\s+(\S+):\s*(.*)$")
events = []          # (ts, cpu, pid, event, rest)
for line in txt.splitlines():
    m = line_re.match(line)
    if not m:
        continue
    ts = float(m.group(4))
    events.append((ts, int(m.group(3)), int(m.group(2)),
                   m.group(5), m.group(6)))
print(f"trace: {len(events)} events")

# ch7's polls (the napi_poll tracepoint carries the napi struct addr)
ch_polls = [e for e in events
            if e[3] == "napi_poll" and ch_napi in e[4].lower()]
# the thread's scheduler events
th_wake = [e for e in events
           if e[3] == "sched_wakeup" and f":{tpid} " in e[4]]
th_in = [e for e in events
         if e[3] == "sched_switch" and f" ==> napi" in e[4]
         and f":{tpid} " in e[4]]
th_mig = [e for e in events
          if e[3] == "sched_migrate_task" and f"comm=napi" in e[4]]
# ch7's wake request: __napi_schedule runs in ch7's IRQ context, and
# the IRQ is pinned to cpu 8 -- other cpus' __napi_schedule events
# belong to the other 31 channels
irq_sched = [e for e in events if e[3] == "function"
             and "__napi_schedule" in e[4] and e[1] == 8]
print(f"ch7 polls={len(ch_polls)} thread_wakeups={len(th_wake)} "
      f"thread_switchins={len(th_in)} migrations={len(th_mig)} "
      f"__napi_schedule={len(irq_sched)}")

# ---- align probe ts to trace ts -------------------------------------
# the probe covers the finder flood too; the TRACE covers only the
# cell. Align by the TAILS: the last 50 cc jumps vs the last 50
# ch7 polls (the cell ends for both at ~the same moment).
jumps = [rows[i]["ts"] for i in range(1, len(rows))
         if rows[i]["cc"] != rows[i - 1]["cc"]][-50:]
poll_ts = [e[0] for e in ch_polls][-50:]
if jumps and poll_ts and len(jumps) == len(poll_ts):
    offs = [p - j for p, j in zip(poll_ts, jumps)]
    offs.sort()
    off = offs[len(offs) // 2]
    spread = offs[-1] - offs[0]
    print(f"probe->trace offset: {off:.3f} s (median of {len(offs)}, "
          f"spread {spread:.3f} s)")
    if spread > 2.0:
        print("WARNING: alignment spread > 2 s -- treat the join as "
              "approximate")
else:
    off = None
    print("ALIGNMENT FAILED: no cc jumps or no polls to match")

# ---- the lost-wake scan ---------------------------------------------
lost = []
for a, b in stranded:
    t0 = rows[a]["ts"] + off if off else None
    t1 = rows[b]["ts"] + off if off else None
    if t0 is None:
        break
    scheds = [e for e in irq_sched if t0 - 0.01 <= e[0] <= t1 + 0.01]
    wakes = [e for e in th_wake if t0 - 0.01 <= e[0] <= t1 + 0.01]
    runs = [e for e in th_in if t0 - 0.01 <= e[0] <= t1 + 0.01]
    migs = [e for e in th_mig if t0 - 0.05 <= e[0] <= t1 + 0.05]
    status = []
    for s in scheds:
        near_wake = any(0 <= w[0] - s[0] <= WAKE_US / 1000 for w in wakes)
        near_run = any(0 <= r[0] - s[0] <= WAKE_MS / 1000 for r in runs)
        if not near_wake and not near_run:
            status.append(
                f"LOST-WAKE cand: __napi_schedule @{s[0]:.6f} cpu{s[1]} "
                f"-> no thread wakeup within {WAKE_US}us, no switch-in "
                f"within {WAKE_MS}ms")
    print(f"GAP t={t0:.3f}..{t1:.3f} dur={t1 - t0:.1f}s "
          f"napi_schedule={len(scheds)} thread_wakeups={len(wakes)} "
          f"switchins={len(runs)} migrations={len(migs)}")
    for s in status:
        print("   " + s)

migs_all = sorted({e[0] for e in th_mig})
print(f"thread migrations total: {len(th_mig)}")
