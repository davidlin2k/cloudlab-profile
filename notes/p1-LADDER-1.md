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

## Forensics and validity (2026-09-24, before numbers enter any figure)

Three anomaly classes were decoded after the first fig1-3 pass; all rows
affected by (a) and (b) are invalid and are being re-run as fig1-3b.

- (a) deliv>1 parse bug: parse_kv key "pkts" substring-matches "mpkts=",
  so deliv printed (pkts+mpkts)/sent = 1.88 for clean runs. Fixed
  (pkts_true = pkts_key - mpkts_key). Goodput (mpkts/measure-span) was
  never affected.
- (b) SO_REUSEPORT flow-split (the "46%" class): a straggler consumer
  from the previous cell stays bound to the port, and the kernel splits
  the 5 source-port flows across the two sockets. P0X rep1 at 130k
  received EXACTLY 2/5 of the wire (3,686,241 of 9,230,000; wire
  tq_delta = 9,230,028; sockdrops = 0). smoke46 with kill-verify: P0,
  P0X, P2 all deliver 99.9% of 9,230,000 and every datagram is exactly
  64 bytes (GRO merging ruled out). Same root cause as the win-file
  clobber (straggler fd). All non-P0 low-rate matrix rows are victims;
  re-run as fig1-3b (72 cells). P0 rows and all W2 rows are valid.
- (c) AN-003 threaded-NAPI lost-wakeup wedge (KEEP as finding): at
  >=790k with the NAPI thread on a remote core, the queue's NAPI stops
  dead (thread run-time delta 0.000, IRQ 312 masked-frozen,
  rx_out_of_buffer grows ~750k/s, sender counters clean). P3/P4 wedged
  7/8 at >=790k in the matrix; P3-525k rep3 wedged (1/3). The p1wedge
  chain at 790k gave the OPPOSITE pattern (P4 82% delivered, P3 2%, P2
  0) with C-states unpinned - trigger is state-sensitive. wedge-m matrix
  (placement x PIN_IDLE x 4 reps, interleaved order) running now.

Low-load nugget already solid (smoke46, all at 100% delivery, n=1 each,
provisional): W1 at 130k - P0X p50 11.5us vs P0 108.5us vs P2 114.5us.
Separation (app off the IRQ core) removes the low-load latency cost
entirely; same-core threading does not. Feeds Fig 2.

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
