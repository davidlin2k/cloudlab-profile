# p1-MIGRATE (the separate investigation DR-010 orders)

## V2 (frozen 2026-09-27 ~01:4xZ, per DR-011 item 2 -- supersedes the
## v1 design below for all cells after the frozen v1 batch)

The frozen v1 batch completed: **M-A (unpinned) 8/8 WEDGED; M-B
(pin46) 5/8 WEDGED** -- the frozen M-B prediction (0/8) is
falsified. Static pin46 wedges with ZERO migrations after the pin,
so migration alone cannot be the necessary condition; the wedge
tracks WHICH cpu the poll runs on (pin10: 0/8; pin8 in-mask: 0/8;
pin46: 5/8; unpinned roaming: 8/8). The v2 design therefore tests
migration moments AGAINST residence time on the wedge-prone cpu:

- **Arm HOP-1046 (30 cells):** pin the thread and hop it between
  cpus 10 and 46 every 100 ms (p1/hopper.py, the hop log joined at
  analysis). Decisive statistic: for every stranded gap, whether it
  STARTS within 50 ms of a hop (a migration-moment candidate) or
  falls inside a 46-residence segment (a residence candidate). If
  the gaps cluster at hops, migration moments are causal; if they
  cluster inside 46 residence, the wedge is a property of polling
  on that cpu (memory/domain locality), and migration is a passenger.
- The controls are the already-run cells: PIN-10 = 0/8 (RQ1 arm A),
  PIN-46 = 5/8 (the frozen M-B), UNPINNED = 8/8 (the frozen M-A).
- The unpinned arm is DROPPED from the new batch (measured 8/8).
- Every stranded gap is classified (event-silent / wake-lost /
  wake-flowing; DR-011 item 3, implemented in
  p1/migrate_analyze.py).
- The re-arm trace: the wake trace already captures
  napi_complete_done and the poll cpu per event; the analysis joins
  the hop log, the probe, and the trace per cell (DR-011 item 2's
  re-arm/CPU-around-migrations requirement).
- The power: 30 hop cells; under a pure-residence model (the 46
  fraction ~50% of cell time at the observed 5/8 rate) most cells
  wedge, and the gap-start-vs-hop analysis separates the hypotheses
  regardless of the total wedge rate. If the hop arm wedges at ~0/30
  despite the 46 residence, both hypotheses fail and the trigger
  envelope re-opens from scratch (reported as such).
- Time-box (DR-011 item 4): one week from 2026-09-27; go/no-go = a
  migration-causal (or locality-causal) result PLUS a gap class
  pointing at specific code, else stop and write the short note +
  the netdev liveness bug report.
- Deliverable: notes/p1-MIGRATE-1.md (counts only + the
  classification table + the gap-start-vs-hop table).

## V1 (frozen 2026-09-27 ~00:0xZ; the batch ran as designed and its
## counts stand)

## The question (one variable)

The wedged cells to date share one condition: the poll thread is
UNPINNED (migrating) under flood. The pinned cells (pin8 in-mask,
pin10 off-mask) never stall. The isolated variable: **thread
migration**. Does the stall require the thread to be free to migrate
-- and does a wake get lost at a migration moment?

## Design (two arms, the migration variable isolated)

Both arms: stock driver, task-1 M158 protocol, IRQ 312 on 8,
threaded=1, the validated readiness probe covering each cell.

| | Arm M-A (migrating) | Arm M-B (fixed, any cpu) |
|---|---|---|
| Thread affinity | 0-63 (unpinned, the default) | pinned to one cpu (e.g. 46 -- where val-2's thread sat) |
| Cells | 8 | 8 |

Unlike RQ1, the mechanism under test is NOT the driver's completion
path (it behaves identically in both arms); the variable is the
scheduler's freedom to move the thread.

## Measurements

1. The readiness probe per cell (unchanged): stranded-work gaps.
2. **The wake trace at the migration moments** (new): during the
   wedge windows, a tracepoint/kprobe capture of
   sched_wakeup/sched_migrate/sched_switch for the poll thread +
   napi_schedule/napi_complete_done + the IRQ handler entry for
   312, correlated with the cc advances from the probe. Question:
   at a cc advance that ends a stranded gap, did a wake precede it,
   and did any wake get lost (a napi_schedule with no subsequent
   thread run) across a migration?
3. Per-cell: migration count, the stranded-gap count, and whether
   each gap's closing wake coincided with a migration or an idle
   wake.

## Pre-registered predictions

- Arm M-A stalls reproduce (>= 3/8 wedged, stranded-ready evidence
  per wedge); Arm M-B 0/8 (matching every pinned cell to date).
- If the wake trace shows lost wakes at migration boundaries, the
  investigation has its next mechanism candidate (a scheduler-level
  wake loss under migration, not a driver contract defect).
- If Arm M-A does NOT stall at >= 3/8, the unpinned-correlation was
  confounded (e.g. the pre-reboot environment or the harness wiring
  differed), and the stall's trigger envelope must be re-opened from
  scratch -- reported as such.

## Discipline (if approved)

Commit the spec frozen before the first cell; smoke = 1 M-A cell;
the wake trace validated on one healthy cell first (zero lost wakes
expected); counts only to notes/p1-MIGRATE-1.md; one run at a time.
