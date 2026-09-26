# p1-FIX (DR-008 E5, as revised by DR-009): the fix, pre-registered
# before any build or cell -- measured on the STRANDED-BACKLOG EVENT,
# not just dead-cell counts

Frozen: 2026-09-26 ~16:20Z; revised per DR-009 (Change 2 + Change 3)
before any fix cell ran. Source: decisions/DR-009.md (verbatim). Runs
AFTER the PERSIST batch (one run at a time on n1). Every build is
incremental against /scratch/kbuild/linux (v6.17.8, objects warm).
Node @clnode366. The defect under test is NAPI's overloaded
poll-return value (work-done vs keep-polling), not the mlx5 park.

## The structural gate (DR-009 Change 2): the stranded-backlog event

p1/stranded_logger.sh observes, per sub-budget poll (mlx5e_napi_poll
returning work < 64): the cpu, the napi state byte, the CQ consumer
index cc, and the ownership bit of the CQE AT cc (the entry the poll
stopped at). The core's trace_napi_poll view (work / again) is logged
alongside.

**Stranded-backlog event** (the paper's metric): work < 64 AND
repoll not set AND the CQE at cc is HW-written-unconsumed (owned) AND
the poll ran off the channel's affinity mask. I.e. the driver told the
core "done" while a completion sat pending on an off-mask poll.

BASE shows the event firing continuously on a wedged queue; a correct
fix drives it to zero. EVERY arm (BASE/F1/F2/F3) reports the event
count. This replaces the F1 "BASE-vs-F1 dead-cell delta" gate.

## The four variants

- **BASE**: unfixed v6.17.8, A1 wiring (unpin threaded). Prediction:
  >= 3/8 PROBE-DEAD; stranded-backlog events fire continuously.
- **F1 (naive, driver-local)**: p1/fix-f1-driver.patch -- in the
  affinity-change detour, when the poll exhausted its budget,
  napi_schedule(napi) and return instead of decrement-and-complete.
  Placement abandoned (the poll keeps draining on the wrong CPU).
  Prediction: 0/8 PROBE-DEAD; stranded events -> 0 (the backlog
  drains, but off-mask).
- **F2 (naive, core)**: p1/fix-f2-core.patch -- bind the threaded NAPI
  kthread to n->config->affinity_mask at creation (verify the
  napi_config layout at build). Placement frozen. Prediction: 0/8
  PROBE-DEAD; aff_change ~ 0 (the detour never fires); stranded
  events -> 0.
- **F3 (contract fix, DR-009 Change 3)**: p1/fix-f3-contract.patch --
  on a budget-exhausted off-mask poll, return budget (the core's
  repoll is honored; the backlog is not stranded) and express the
  placement preference through the channel the core tracks: move the
  kthread onto napi->config->affinity_mask (softirq context keeps the
  original hand-back -- no kthread to move; the IRQ restarts the poll
  on the new affinity CPU, the 2017 case). Verify NAPIF_STATE_THREADED
  and napi_config.affinity_mask in the build tree before compiling.

## F3's four predictions (pre-registered, the memo's)

1. PROBE-DEAD 0/8 (like F1/F2).
2. The stranded-backlog event count -> 0 (unlike BASE).
3. The poll migrates: within one repoll, polling lands on the
   affinity CPU and aff_change returns to ~0 -- placement preserved,
   not abandoned (F1) or frozen (F2).
4. Livelock check passes (<= 5% goodput degradation in the
   threaded=0, app-on-IRQ-core, 525k config), and no busy-poll/XSK
   regression.

If F3 hits all four, it's the paper's fix and F1/F2 are the foil. If
F3 can't satisfy 3 and 4 together, that tension is itself a finding --
report it.

## Arms and cells

| Arm | Cells | Metrics |
|---|---|---|
| BASE | 8 | PROBE verdicts + stranded-backlog count |
| F1 | 8 | same |
| F2 | 8 | same + per-sample kthread mask |
| F3 | 8 | same + migration latency + aff_change return |

The livelock check (frozen, the invariant the 2017 code protects --
do not weaken): threaded=0, k2_rx --core 8 (app ON the IRQ core), 525k
flood; unfixed vs fixed goodput; every fix arm must pass (<= 5%
degradation). F1/F2/F3 cells: LIVELOCK x 4 each + the clean-path 525k
cells (foldable into the livelock cells for F1).

## Success criteria

1. PROBE-DEAD: F1 = 0/8 AND F2 = 0/8 AND F3 = 0/8 (vs BASE >= 3/8).
2. Stranded-backlog events: ~0 per arm (BASE: continuous firing).
3. F3's prediction 3 (migration) observed.
4. The livelock invariant holds for every fix arm.
5. The dump tool on one fixed wedged cell shows no parked-poll state.

## Discipline

Commit before running; smoke = 1 F3 cell (the contract fix first --
it is the paper's); insmod the patched module (rmmod mlx5_core +
deps; keep DWARF in the module build for the dump tool). Module
version + build hash recorded in notes/p1-FIX-1.md. Revised order per
DR-009: E7 first, then the logger on BASE, then the four-arm batch,
then E3/E4 (portal), A0 -> severity word, disclosure.
