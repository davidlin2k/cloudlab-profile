# p1-CAUSAL (DR-010 RQ1): does the stop-and-rearm path strand work?

Frozen 2026-09-26 ~22:2xZ, before any RQ1 run. Source:
decisions/DR-010.md (verbatim). Supersedes the fix-batch order of
specs/p1-FIX.md (F1 is reborn as arm B of this experiment; the
4-arm fix batch, the audit, i40e/mlx4, the repair space, the theory
and the disclosure are PAUSED until RQ1 and RQ3 land).

## Design (holds location fixed, varies only the mechanism)

Both arms: ch7's NAPI kthread (napi_id 8263) pinned to CPU 10
(off-mask, FIXED); IRQ 312 -> CPU 8 (fixed); threaded=1; task-1
M158 flood (790k -> WEDGE -> reduce 158k -> 120 s monitor -> probe).
8 cells per arm.

- Arm A (driver as-is): stock v6.17.8 module. A budget-exhausted
  off-mask poll completes and rearms (the bailout unmodified).
- Arm B (keep-polling): the F1 patch (p1/fix-f1-driver.patch) built
  and insmod'ed -- the same poll calls napi_schedule() and keeps
  draining. Nothing else differs.

The E2 confound (pinning changed BOTH the location and whether the
completion path fires) is excluded: both arms run on the SAME wrong
CPU; only the completion-path behavior differs.

## The readiness probe (primary measurement, load-bearing)

p1/rq1_probe.py: an in-process kcore sampler targeting ~1 kHz (the
achieved rate is logged honestly). Per sample: cc, the ownership bit
of the CQE AT cc (owner parity vs the consumer cycle -- per the memo,
NOT the earlier occupancy walk), rq_stats.packets, ch_stats.events,
ch_stats.arm, the napi state byte, and the kthread's current CPU.

Per gap (a span with rq_stats.packets flat), record: duration, whether
a ready CQE was present at EVERY sample throughout, the cpu, and the
ch7_events/ch7_arm deltas across the gap. "Ready but unserved" = the
consumer-index CQE is owned the whole gap while cc does not advance.

Probe validation BEFORE the arms (pre-registered): a healthy queue
must read ZERO ready-unserved samples across a gap-free window; a
known-dead queue must read stranded work (owned CQE at cc through
gaps). If the dead queue does not show it, the earlier gap analysis
was measuring the wrong thing -- report before proceeding.

## Pre-registered predictions

- Arm A: stalls reproduce (PROBE-DEAD in most cells), and during the
  long gaps a ready CQE is present but unserved (work stranded on an
  idle-enough CPU).
- Arm B: on the same CPU 10, service continues, gaps shrink,
  stranded-work events go to zero.

## Decision rule (frozen)

- A strands ready work AND B restores service on the same CPU ->
  causality confirmed. Proceed to RQ3 (freeze specs/p1-TRIGGER.md).
- B still stalls, OR A never shows a ready CQE during gaps -> the
  mechanism is not the cause. Write the negative result; keep the
  placement measurements; open a separate investigation into their
  cause. Do not add theory to rescue the hypothesis.

## Deliverable

notes/p1-CAUSAL-1.md: per-arm stall counts, the stranded-work evidence
per gap, counts only, no interpretation. Brought to the PI BEFORE any
conclusions are drawn.

## Discipline

Commit before running; smoke = the probe on a healthy queue + one
known-dead queue before the batch. A0 is captured opportunistically
if a cell leaves the queue dead (quiet window + the standard probe);
no separate A0 batch. One run at a time on n1. Anomaly reports within
24 hours.
