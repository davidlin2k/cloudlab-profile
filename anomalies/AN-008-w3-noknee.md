# AN-008: W3 knee-pass — no knee to 130k QPS; per-request CPU cost falls with load

Opened: 2026-09-25T09:45Z. Facts only; interpretation held (run-book rule).
Covers specs/p1-W3MEMC.md v1 knee-pass cells 2026-09-25 09:16-09:36Z.

## What was predicted (v1, frozen before the runs)

P1: knee F_P0 = 62.0k QPS (bar 46.5-77.5k), F_P0X = 82.4k (bar 61.8-103.0k),
from low-load (20k aggregate) per-request costs of 16,130 ns (P0) and
6,066+12,138 ns (P0X).

## What was measured (14 cells, 1 rep each, spec-valid: Misses 0.0%,
Skipped 0.0%, op_q per table, landing purity 99.98-99.996% measure window)

Delivered QPS tracked offered within 0.1% at EVERY load 30k-130k on BOTH arms
(i.e. no knee definition fired; 130k = 2.1x the predicted P0 knee).

Per-request CPU cost (ref-cycles/req, bracket [t0+6, t0+70], 64 s):

| load  | P0 CPU8 | P0 total ns | P0X recv (CPU8) | P0X app (CPU9) | P0X total ns |
|-------|---------|-------------|------------------|----------------|--------------|
| 30k   | 33,725  | 10,947      | 12,887           | 27,212         | 12,338       |
| 45k   | 24,064  | 7,583       | 9,006            | 19,075         | 8,641        |
| 60k   | 19,883  | 6,192       | 8,007            | 16,274         | 7,471        |
| 75k   | 18,853  | 5,861       | 7,905            | 15,909         | 7,327        |
| 90k   | 18,341  | 5,696       | 7,772            | 15,709         | 7,225        |
| 110k  | 17,996  | 5,585       | 7,606            | 15,361         | 7,067        |
| 130k  | 17,842  | 5,541       | 7,408            | 14,830         | 6,843        |

CPU utilization: P0 CPU8 31.1% -> 71.4%; P0X CPU8 11.9% -> 29.6%, CPU9
25.1% -> 59.3% (30k -> 130k). Extrapolated saturation from utilization:
P0 ~182k QPS, P0X ~219k QPS (extrapolation, not a measurement).

Also recorded (raw): request p99 (measure connections) FELL with load: P0
947.9 -> 828.0 us, P0X 891.2 -> 703.3 us (30k -> 130k); idle p99 104-106 us;
op_q p99 rose 5.8 -> 16.5 (P0) / 5.7 -> 14.1 (P0X) of depth 32.

## Consequences (pre-registered handling, v1 outcome clause)

P1 as frozen is judged against the measured knee when found; on the current
evidence it is outside the bar by ~3x. v1's knee definition did not fire: no
cell failed "delivered >= 95% of offered". v1's validity gates assume pre-knee
cells (Skipped = 0.0%); overload cells are needed for P2 (kill criterion),
so a spec v2 separates the gate sets and extends the scan (160k-300k). v1's
14 cells stand as valid pre-knee data (not re-run).

Held: any explanation of the cost falloff, the p99 falloff, or the projected
knee location. The scan extension measures rather than infers.
