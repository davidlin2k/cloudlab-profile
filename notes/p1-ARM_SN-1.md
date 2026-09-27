# p1-ARM_SN-1: the stale-arm test -- counts only (DR-012 step 2)

Frozen before any run: specs/p1-ARM_SN.md (the memo's hypothesis,
prediction, and decision rule verbatim). Node @clnode366, 6.17.8.
Runs: 1 smoke (SM-1, static pin10 wiring, the healthy-queue check) +
4 stale-arm cells (AS-1..4, HOP wiring 10<->46 @100 ms, TRACE=1, the
probe with arm_sn, the hopper, the eq-filtered completion-event
logger). 2026-09-27 09:13-09:51Z, one cell at a time.

## Instrumentation (as deployed)

- rq1_probe.py v3: per sample (999 Hz) reads cq->arm_sn (kcore,
  mcq+100) AND the arm doorbell RECORD at *arm_db (mcq+16 holds the
  POINTER; the dereference fix landed after the first SM-1 smoke
  showed the flat read was constant garbage). adb_sn = the record's
  top 2 bits (BE sn<<28|cmd|ci).
- p1/arm_sn_logger.sh: kprobe:mlx5_eq_comp_int filtered to ch7's comp
  EQ. v6.17 makes the handler a NOTIFIER: arg0 = &eq_comp->irq_nb =
  eq + 120 (DWARF of the build-tree mlx5_core.ko). EQ pointer read
  per cell via p1/eqdump.py (mlx5_core_cq.eq @ mcq+176). All events
  arrive on cpu 8 (the IRQ home): 2558/2564 in the instrument smoke.
- p1/arm_sn_analyze.py: the host-countable signature. During an
  event-silent gap the counter is FROZEN (no events -> no
  ++arm_sn). Then adb_sn == arm_sn&3 for the whole gap = the last
  arm carried the CURRENT sn (CLEAN; the device accepted it);
  adb_sn == (arm_sn-1)&3 SUSTAINED = the doorbell committed one sn
  behind the counter (the memo's read-before-increment race;
  STALE-CAND). Transient lag-1 between an event and the next arm is
  normal in the live regime and does not count.

## Smoke (SM-1): PASSED

329,785 samples, 0 stranded gaps (static pin10, healthy as RQ1
predicted), 17 flat windows: relation equal/clean in 17/17, no
stale candidates, events flowing (24.6 MB logger). The arm record's
sn walks 0-3 under flood (live check).

## The 4 stale-arm cells (HOP wiring, the race reachable)

| cell | samples | gaps | stranded | event-silent | wake-lost | wake-flowing | stale_cand | clean |
|---|---|---|---|---|---|---|---|---|
| AS-1 | 304756 | 17 | 10 | 5 | 1 | 4 | **0** | 10 |
| AS-2 | 226637 | 39 | 24 | 21 | 0 | 3 | **0** | 24 |
| AS-3 | 251652 | 23 | 21 | 9 | 0 | 12 | **0** | 21 |
| AS-4 | 329793 | 30 | 12 | 0 | 0 | 12 | **0** | 12 |
| total | | 109 | 67 | 35 | 1 | 31 | **0** | **67** |

**Zero stale-arm candidates in 67 stranded gaps** (35 of them
event-silent). Every gap's arm record equals the frozen counter:
the last doorbell before every silence carried the CURRENT sn.

## Corroboration (the EQ-level timeline, AS-1)

The logger's zero-event holes reproduce the trace's event-silent
gaps to the millisecond: holes 0.321 / 1.682 / 1.864 / 1.808 /
4.839 s vs the classified event-silent durations 321 / 1682 / 1864 /
1809 / 4839 ms. Event-silence is real at the EQ/IRQ level: the
device raises NOTHING while completions sit ready.

## Verdict (the frozen decision rule)

"No stale-arm candidates during event-silent gaps -> the race
hypothesis is wrong; report the device-moderation alternative."

**The stale-arm race on arm_sn is REFUTED.** The arm is committed
with the correct sn (record == counter through every gap), the
device accepts it, and then raises no completion event for
0.3-4.8+ s while the queue is ready and unserved. The failure is
DOWNSTREAM of the arm: device-side moderation/state, the memo's
pre-registered fallback. The DR-011 gap mapping stands: wake-lost
is rare (1 of 67 here; 4 of 308 in MIGRATE-2) and the silence is
not the core wake path.

## Honest caveats

- The logger was killed at cell WRAP (~215 s coverage of the ~330 s
  probe window); all 5 of AS-1's event-silent gaps fell inside the
  covered span (the hole match). The parity statistic itself is
  probe-only and covers every sample.
- The bpftrace logger's absolute timestamps wrap sign (%d on nsecs);
  only relative hole structure was used. Noted as a harness
  limitation, no impact on the counts.
- The parity argument assumes the counter freezes during an
  event-silent gap (arm_sn advances ONLY in mlx5_eq_comp_int, eq.c
  v6.17 -- source-verified). The logger confirms no events fire.

## What this leaves the program (per DR-012)

Step 2 is done: the mechanism is NOT the arm_sn race. The device
accepts the arm and then goes silent -- the next probe is the
DEVICE's own state at gap time (the EQ doorbell CI vs the CQ
consumer index: if the device's CI lags while the CQ drains, the
device believes nothing is outstanding). DR-012 steps 3 (the
locality pin sweep across L3 domains), 4 (the tightened clean
definition) and 5 (the cell-level bootstrap) are unchanged and
remain queued.
