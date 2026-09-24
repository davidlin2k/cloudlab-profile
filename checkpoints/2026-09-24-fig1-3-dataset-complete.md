# 2026-09-24 — Figs 1–3 dataset complete (111 verified rows)

Status: the fig1-3 collection program is CLOSED (fig1-3 + fig1-3b +
fig1-3c re-runs + smoke46 + cal-1; dedup and validity filters leave 111
rows; 5 dropped). chain6 is collecting Fig 4 (162 cells, ~17:00Z).

## Headline table (goodput share of offered, n=2–3, 10k-resample
bootstrap 95% CIs on the means)

| load | P0 | P0X | P2 | P3 | P4 |
| --- | --- | --- | --- | --- | --- |
| 1.0x knee (525k) | 85.7% | 99.5% | 84.9% | 79.4% | 62.6% |
| 1.5x (790k) | 9.0% | 97.5% | 35.9% | 0.0% | 3.9% |
| 2.0x (1050k) | 0.2% | 74.2% | 26.8% | 0.0% | 0.0% |

- [X] abstract recheck UNCHANGED: 0.20% [0.20, 0.20] at 2x knee (n=2);
  0.13% [0.05, 0.21] at 2.5x (n=2).
- P0 knee bracket: deliv 0.999 @390k, 0.998 @450k (n=1), 0.861 @525k,
  0.094 @790k. Knee (>=95% delivery) = 450–525k pps at 64 B.
- Fig 2 (W2, n=3): p50 P0 104.5 [27.5,144.5] vs P0X 55.2 [28.5,107.5] us.
- Fig 3: hidden softirq share 26–42% at 390k (n=3).

## Contract action (skeleton rule 4)
Fig. 1's claim partially fails: the drain claim holds for P0X (app
separation with inline processing) and fails for the threaded rungs at
flood (wedge-limited, C-008). Decision record DR-001 (PROPOSED) offers
the resolution; the claim list changes only on the PI's call. Fig. 1-3
stay Draft; the intro's separation sentence follows DR-001's outcome.

## Data locations
analysis/rows-{fig1-3,fig1-3b,fig1-3c,smoke46,cal-1}.csv (committed),
analysis/out/fig{1,2,3}.{png,pdf}, raw on rx:/root/p1/results/.
