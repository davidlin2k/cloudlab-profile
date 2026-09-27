# 2026-09-27 — DR-012 step 2: the stale-arm test REFUTED (device-moderation fallback stands)

## What
The pre-registered stale-arm test (specs/p1-ARM_SN.md, frozen) ran
end-to-end: smoke SM-1 (healthy queue) + 4 stale-arm cells AS-1..4
(HOP wiring 10<->46, TRACE=1, probe v3 with arm_sn + adb_sn, the
eq-filtered completion-event logger), one at a time, 09:13-09:51Z.

## Verdict
**Zero stale-arm candidates in 67 stranded gaps** (35 event-silent).
Every gap's arm record equals the frozen counter — the last doorbell
carried the CURRENT sn and the device accepted it, then raised NO
completion event for 0.3–4.8+ s while the queue sat ready and
unserved. Per the frozen decision rule: **the arm_sn race hypothesis
is refuted; the pre-registered device-moderation fallback is the
reported alternative.** Corroboration: the logger's zero-event holes
reproduce AS-1's event-silent gap durations to the millisecond
(0.321/1.682/1.864/1.808/4.839 s), confirming event-silence at the
EQ/IRQ level.

## Instrument notes (recorded because they bit)
- rq1_probe.py: mcq+16 is the arm_db POINTER; the record lives at
  *arm_db — the flat read produced constant garbage, caught in the
  first smoke, fixed before any ARM_SN cell ran.
- v6.17's mlx5_eq_comp_int is a notifier: arg0 = &eq_comp->irq_nb =
  eq+120 (not the eq pointer). EQ pointer via mlx5_core_cq.eq
  (mcq+176, DWARF of the build-tree mlx5_core.ko). All ch7 events
  arrive on cpu 8.

## Records
- notes/p1-ARM_SN-1.md (counts only, the deliverable)
- p1/{arm_sn_logger,arm_sn_cell,arm_sn_arm,arm_sn_post}.{sh,py},
  p1/eqdump.py, p1/arm_sn_analyze.py, p1/rq1_probe.py (v3)
- Cell artifacts on the node: /root/p1/migrate/{SM-1,AS-1..4}/
  (probe.csv, eqint.log, analyze.txt, arm_sn.txt, hops.csv)

## Next (DR-012 order)
- Steps 3-5 unchanged: the locality pin sweep across L3 domains, the
  tightened clean definition, the cell-level bootstrap statistics.
- New lead from step 2's verdict: at gap time, compare the DEVICE's
  EQ CI (eq_update_ci writes it) against the CQ consumer index —
  if the device's CI lags while the CQ drains, the device believes
  nothing is outstanding (moderation/state, downstream of a valid
  arm).
