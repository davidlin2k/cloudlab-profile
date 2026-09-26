# p1-MIGRATE (DRAFT -- the separate investigation DR-010 orders; NOT
# frozen, NOT run until the PI approves)

Status: DRAFT for the PI's review. Per DR-010's negative branch:
"Write it up as a negative result, keep the placement measurements,
and open a separate investigation into their cause." This spec is
that investigation's pre-registration DRAFT. It does not run until
the PI approves the design.

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
