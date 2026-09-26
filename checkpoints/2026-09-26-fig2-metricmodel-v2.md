# Checkpoint 2026-09-26: Fig. 2 v2 (DR-005 sec. 4) QA + hidden-share sweep complete

## What was finished

DR-005 decision 2 ("Replace 'hidden share' throughout") is now fully
applied to every live artifact; frozen records (specs, decisions,
checkpoints, FINDINGS) intentionally keep the old wording as history.

1. Figure (analysis/p1_fig_model.py -> fig2-metricmodel.{png,pdf}):
   - Annotation QA fixes: "6.2%" moved clear of the tolerance-band
     label; legend moved to the upper left (it sat on the TCP points
     and the "3.16x" label); "+/-25% of measured" placed in the empty
     lower-right region; axis limits widened so both "1000" ticks are
     inside the figure (no clipping).
   - Three visual QA rounds (final round: no overlaps, no clipping).
   - All numeric anchors re-verified at render time: task1b 390k app
     906-1407 ns and real 2026-2935 ns (OK), thread share per-rep
     42.0-52.3% (claim range 43-55%), /proc/stat 0.60% (AN-007),
     model P0 UDP 451.0k vs 438.6k (2.8%), P0X UDP 767.0k vs 818.0k
     (6.2%), TCP 62.0k/82.4k vs 190k/260k (3.06x/3.16x).
   - Script also made sandbox-robust: figstyle path now resolves in
     both /home/david/workspace and /mnt/davidlin-personal (the model
     switch relocated the flowlet-eval tree).

2. Workshop draft (docs-workshop-draft-v0.md): section 4 rewritten to
   the v2 message (standard metric blind: /proc/stat 0.6% / 166x,
   schedstat 43-55%, PMU-basis corrected = full cost; corrected costs
   predict the UDP knee within 2.8%/6.2% with no fitted constant; the
   constant-cost form fails on TCP at 3.06x/3.16x, where cost depends
   on load). Figure-table row renamed to fig2-metricmodel. Zero
   "hidden share" occurrences remain (grep-verified).

3. Workshop outline (docs-workshop-outline.md): section 1's model-miss
   numbers updated (2%/9% -> 2.8%/6.2%), section 4 row rewritten to
   the v2 message with the same anchors, figure-audit row updated to
   fig2-metricmodel with the 2026-09-26 QA stamp.

4. Mirror copies refreshed (deep-research-output/rx-placement-admission/
   workshop-outline.md and workshop-draft-v0.md); both grep clean.

## Old numbers retired (do not reuse)

hidden share 26-42% (mean 33%) as the section-4 headline; the (1-h)
correction model (669.0k uncorrected / 448.2k corrected / error 0.656
~= (1-h)); split form 9% (894.3k vs ~818k). These remain only in
frozen history and in the C-006/C-007 ledger entries themselves.

## Still open

- C-007 re-promotion and the other review flags in the draft remain
  the PI's call (unchanged).
- The blind-metric claim now cites the same finding IDs as before
  (F-p1-LADDER-3, C-006, AN-007, C-014, p1-LADDER.4, C-017); no new
  claims were introduced by the rewording.
