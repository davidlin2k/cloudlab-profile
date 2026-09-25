# 2026-09-25 -- DR-004 task 1 complete: costs, Figure 3, knee model
**Date:** 2026-09-25 05:2xZ
**Data:** task1b (30 cells, 3 reps each, all gates pass), aligned PMU
bracket; rows analysis/rows-fig13-merged.csv.

## Figure 3 (updated; vision QA PASS, 2 rounds)
Per-packet CPU at 390k / 64 B, thread-accounted vs receive work:
| placement | thread (ns) | receive (ns) | total (ns) |
| --- | --- | --- | --- |
| inline (P0) | 1062 | 1052 | 2114 |
| inline sep.app (P0X) | 1112 | 1303 | 2415 |
| thr app-core (P2) | 906 | 1120 | 2026 |
| thr sibling (P3) | 1407 | 1528 | 2935 |
| thr other (P4) | 1135 | 1275 | 2410 |

The thread sees 43-55% of the real cost in every placement.

## Knee model with corrected costs (DR-004: "whatever it is")
- P0 64 B: F = 1e9/(1209+1008) = 451.0k vs measured 438.6k = 2.8% miss
  (PASS; no fitted constant).
- P0X 64 B: 1e9/max(1112,1303) = 767k vs measured 818k = 6.2% miss
  (PASS; costs at 390k = 0.48x knee, caveat noted).
- The (1-h) correction and the metric fix are the same correction;
  applying both double-counts (31% miss).

## Records touched
FINDINGS p1-LADDER.3/.4; AN-007; CLAIMS C-014 Supported, C-007
revision Pending (PI re-promotion); Figure 3 updated; the handbook
confound list gained "softirq execution context".

## Next actions
1. DR-004 task 2 (control-plane stall) -- spec + run (~1 h).
2. Friday memo by noon (2026-W40): figure of the week = fig-wedge-ab.
3. Monday: DR-004 task 3 (wedge tracing, one day strict).
