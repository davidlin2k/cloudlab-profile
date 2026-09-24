# p1-LADDER-1: Figs 1-3 characterization (W1/W2 x 6 policies x load grid)
Draft skeleton — fill numbers when fig1-3 completes. Spec: p1-LADDER v1
(runs) / v2 (model). Evidence: H (hardware, r6615 Genoa block).

## Result
<!-- goodput-vs-offered curves per policy; the [X]% figure for the
abstract comes from here (P0's delivered fraction at 2.5x knee) -->

## Prediction check (spec v1)
| # | Prediction | Verdict | Numbers |
|---|---|---|---|
| 1 | P0 < 50% of offered at 2.5x knee; P2 50-65%; P3 > P2; P4 >= 90% | yes/no/partial | |
| 2 | W2 p99: P0 within 10% of P4; P2 >= 2x P0; P3 between | yes/no/partial | |
| 3 | (model form F deferred to the Fig 4 note) | — | |
| 4 | W1 p50 at 2x knee: P0 >= 2 ms; P2 >= 10x P3; P3 within 30% of P4 | yes/no/partial | |

## The scheduler's blind spot (Fig 3 quantification)
<!-- at each load: cpu8 busy ns/pkt vs app schedstat ns/pkt vs the
/proc/stat softirq column. cal-1 anchor: at 390k pps cpu8 busy = 41.5s
of 60s, app ~26s, softirq column = 0 -> ~37% of the core invisible to
both per-task accounting and the softirq column -->

## Caveats
- W1 rx->dequeue latency includes the recvmmsg batch cycle (~half a
  cycle of queueing); the round-trip story is W2 (clean, 29 us p50 at
  20k rps in smoke). SLO goodput uses each instrument's own idle p99.
- No cpufreq driver on this block (SBIOS _CPC absent): ref/cyc covariate
  recorded per run; arms interleaved back-to-back.
- W1 p50 rep spread at mid load reflects sender-batch clumping (sendmmsg
  batches of 64 arrive clumped); medians + bootstrap CIs reported.

## Data locations
- rows: rx:/root/p1/rows-fig1-3.csv; manifests: rx:/root/p1/results/fig1-3/
- figures: analysis/p1_figures.py -> analysis/out/fig{1,2,3}.{png,pdf}
