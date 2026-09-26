# p1-FIX (DR-008 E5): the fix, pre-registered before any build or cell

Frozen: 2026-09-26 ~16:20Z. Source: decisions/DR-008.md E5. Runs AFTER
the PERSIST batch (one run at a time on n1). Every build is incremental
against /scratch/kbuild/linux (v6.17.8, objects warm). Node @clnode366.

## The two variants

- **F1 (driver-local)**: p1/fix-f1-driver.patch -- in mlx5e_napi_poll's
  affinity-change detour, when the poll exhausted its budget
  (work_done == budget) do NOT decrement-and-complete; instead
  napi_schedule(napi) and return (out). Short polls keep the existing
  hand-back (complete + re-arm). Rationale: the latch is a
  budget-exhausted poll completing (parking) with tens of thousands of
  CQEs pending; napi_schedule sets SCHED|MISSED so the drain continues
  -- the same restart strategy i40e already uses (force-interrupt
  after bailout) and mlx5 already uses on the XSK path.
- **F2 (core)**: p1/fix-f2-core.patch -- when a threaded NAPI's kthread
  is created, bind it to the NAPI's IRQ affinity mask
  (napi->config->affinity_mask; the core already tracks it --
  iavf/ice/idpf use netif_set_affinity_auto). VERIFY the napi_config
  layout in the build tree before compiling (the hunk is marked).

## Arms (each 8 cells, the task-1 M158 flood protocol, gates per cell)

| Arm | Config | Pre-registered prediction |
|---|---|---|
| BASE | unfixed v6.17.8, A1 wiring (unpin threaded) | >= 3/8 PROBE-DEAD (replication control) |
| F1 | fix-f1 applied, module replaced, A1 wiring | 0/8 PROBE-DEAD; aff_change may rise (the bailout still fires) but no park-with-pending |
| F2 | fix-f2 applied, A1 wiring | 0/8 PROBE-DEAD; aff_change ~ 0 (the detour should never fire) |

Manipulation checks per cell (pre-registered): F2 -- the ch7 kthread's
Cpus_allowed_list must read the IRQ mask every sample; F1 -- no mask
claim (the kthread stays unpinned by design; the fix must work with it
unpinned), gate = the trace shows no complete-with-budget-exhausted
pattern... simplified: gate = BASE-vs-F1 delta on PROBE-DEAD counts
with the unpin wiring verified per cell (affinity-pre.txt).

## The livelock check (the bailout's original purpose, the memo's)

The 2017 scenario the detour guards: the poll runs on a busy CPU that
is not the channel's, hammering the channel's cache lines and
starving... operationally: threaded=0 (inline softirq on the IRQ core)
with k2_rx --core 8 (the app ON the IRQ core) at 525k, unfixed vs
fixed: measure k2rx goodput + softirq time on core 8. Success
(pre-registered): the fix must not DEGRADE the fixed-vs-unfixed
goodput in this config by > 5%, i.e. adding napi_schedule on the
budget-exhausted bailout must not reintroduce an unbounded poll loop
on the wrong CPU. F2 is exempt from the livelock check (it binds the
kthread; inline polls don't run kthreads).

Cells: LIVELOCK-BASE x 4, LIVELOCK-F1 x 4 (threaded=0, core 8, 525k
flood A6-style), same sampler.

## Success criteria (the memo's, made testable)

1. PROBE-DEAD: F1 = 0/8 AND F2 = 0/8 (vs BASE >= 3/8).
2. Livelock: F1 goodput within 5% of BASE in the threaded=0-on-core
   config.
3. No regression in the clean path: F1/F2 A6-style 525k cells deliver
   >= 95% of what BASE delivers in the same config (4 cells each --
   can be folded into the livelock cells for F1).
4. The dump tool on a fixed system shows no parked-poll state
   (b2_dump.py on 1 wedged F1/F2 cell).

## Discipline

Commit before running; smoke = 1 F1 cell; insmod the patched module
(after rmmod mlx5_core + dependencies -- the module build must include
DWARF for the dump tool: copy the kbuild config from the existing
tree). If the module build fails on the incremental tree, fall back to
full `make -j96 modules` (the kbuild3 path). Record module version +
build hash in notes/p1-FIX-1.md.
