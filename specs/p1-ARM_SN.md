# p1-ARM_SN (DR-012 step 2): the stale-arm test, pre-registered

Frozen 2026-09-27 ~3x:xxZ, before any run. Source:
decisions/DR-012.md (verbatim; the prediction below is the memo's).
Runs AFTER the topology note (notes/topology-n1.md) -- both are
prerequisites for interpreting anything else.

## The hypothesis under test (the memo's, verbatim)

"the event-silent stalls are a stale-arm race on `arm_sn`, made
reachable when the poll runs on a different CPU (and EQ) than the
one servicing the queue's events."

Source facts (v6.17.8): the arm doorbell carries `arm_sn & 3`;
`mlx5_eq_comp_int` increments `cq->arm_sn` per completion event;
`cq.c` only initializes the sequence number.

## Instrumentation

1. The readiness probe gains an `arm_sn` column: cq->arm_sn read
   via kcore per sample (mlx5_core_cq.arm_sn @ mcq+100, mcq @ cq+56
   -> cq+156), alongside cc, the owned bit, packets, events, arm,
   the state byte, and the thread's cpu.
2. p1/arm_sn_logger.sh (bpftrace): kprobe on the driver's arm call
   (the exact symbol verified in /proc/kallsyms at deploy) filtered
   to ch7's cq, recording (ts, cpu, arm_sn-read) -- the sn the
   doorbell is about to carry; plus a counter on mlx5_eq_comp_int
   (the event-arrival timeline).
3. The cell: HOP wiring (the race reachable), TRACE=1, the probe
   with arm_sn, the hopper.

## Pre-registered prediction (the memo's)

During an event-silent gap the last arm's `sn` does not match the
device's expected next value (a stale arm), and the queue is
unserved with pending completions. If `sn` matches and there's
still no event, the race hypothesis is wrong and it's a
device-side moderation issue.

## The operational stale-arm signature (the memo's prediction made
## countable)

An arm call at time T reads arm_sn = X and writes the doorbell with
X & 3. If arm_sn has advanced past X by the time the doorbell
commits (a concurrent completion event consumed on another cpu),
the device rejects the arm as stale. Countable as: an arm event
whose recorded sn differs from the arm_sn value observed at the
next probe sample boundary that follows any concurrent
eq_comp_int invocation -- i.e. the sn was read before the
increment and written after it. The stale-arm candidates are
counted per gap and cross-referenced with the gap's class
(event-silent expected).

## Cells

4 cells, HOP wiring (the 10<->46 hop, the race reachable), with the
full probe + arm_sn + TRACE=1. Smoke = 1 cell on a healthy queue
(the logger must show sn parity walking normally with events).

## Decision rule

- Stale-arm candidates cluster at event-silent gap starts -> the
  hypothesis is confirmed as the mechanism candidate.
- No stale-arm candidates during event-silent gaps -> the race
  hypothesis is wrong; report the device-moderation alternative.

Deliverable: notes/p1-ARM_SN-1.md (counts only). One run at a time.
