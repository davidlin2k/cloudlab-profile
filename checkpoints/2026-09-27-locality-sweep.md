# 2026-09-27 — DR-012 step 3: the locality pin sweep — distance is NOT monotone

## What
specs/p1-LOCALITY.md frozen before the run; 16 cells (PT10 x8, PT24
x8) plus the already-committed pin46 8/8 (MIGRATE-2 MB). The first
PT24 arm was discarded (a bash-case GLOB bug turned `pin24` into
"bad wire"; the cells ran unpinned without the harness) — fixed and
redone; the redo is authoritative.

## Verdict
- Wedge rate NOT monotone in distance: **0/8 (pin10, same L3 as the
  IRQ core) < 5/8 (pin24, far NUMA) < 8/8 (pin46, adjacent CCX)**.
  Bootstrap over cells: pin46 − pin24 = +0.375, 95% CI [+0.125,
  +0.750] — the non-monotonicity is real at n=8.
- The frozen alternative branch fires: the asymmetry is specific to
  the 46/8 CCX pair, not a gradient. Recorded; no curve fitted.
- The stranded-gap BURDEN IS distance-ordered: 0.5/cell (10) <
  7.75/cell (46) < 33.5/cell (24); under the tightened (step-4)
  definition zero PT24 cells are CLEAN (5 wedged + 3 trickling at
  40-41 stranded gaps each).
- Classification: 268 PT24 stranded gaps = 164 event-silent /
  102 wake-flowing / 0 wake-lost; PT10: 4 stranded total (7/8 cells
  completely clean). Wake-lost stays rare everywhere.

## Records
- notes/p1-LOCALITY-1.md (counts only, the deliverable)
- analysis/migrate2/sweep-classify.txt (16-cell classification)
- p1/sweep_classify.sh, p1/pin_sweep_arm.sh, metastab.sh pinN fix
- Cell artifacts on the node: /root/p1/migrate/{PT10-*,PT24-*}/,
  /root/p1/metastab/M1-PT*/

## Next (DR-012 order)
- Step 4 is applied in rq1_summarize.py (WEDGED/TRICKLING/CLEAN);
  retroactively: MIGRATE-2's and HOP's "clean" cells re-derive from
  the recorded gap counts (HOP-27/30 were already not clean under
  the tightened rule — the re-derivation needs no new runs).
- Step 5 done for the wedge statistic; the onset-fraction bootstrap
  applies to future HOP-shaped runs (the sweep has no hopper).
- The 46/8-specific asymmetry + the step-2 device-moderation verdict
  now jointly point at the device/EQ state for the CCX-adjacent
  wiring — the device-side CI probe (checkpoint 2026-09-27-arm-sn)
  remains the queued mechanism step.
