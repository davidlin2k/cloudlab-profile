# p1-LADDER result note 3: the low-rate anomaly was flow-splitting, and
# full delivery shows separation removes the low-load latency cost
Date: 2026-09-24 · Runs: smoke46 3 passed (P0, P0X, P2 at 130k, W1),
fig1-3 99 analyzed (16 discarded: 6 bind-collision victims, 10 below-socket
conservation fails kept as overload evidence) · Evidence level: H

## Result
The 46–57% delivery anomaly on non-P0 arms at low rates was SO_REUSEPORT
flow-splitting with a straggler consumer from the previous cell, not a
policy effect: with kill-verified isolation, P0, P0X and P2 all deliver
99.9% of 9,230,000 offered (n=1 each) at 130k, every datagram exactly
64 B (byte counter; GRO merging excluded). At that full delivery the
same-core separation line (P0X) answers in p50 11.5 µs vs 108.5 µs for
inline sharing the interrupt core (P0) — a 9.4x low-load latency
difference at 100% delivery, the Fig. 2 nugget.

## Figure
F-p1-LADDER-2 (fig2.png, provisional): low-rate W2 round-trip p50/p99
per policy, with the W1 smoke46 numbers as the full-delivery W1 check.
Script: analysis/p1_figures.py · Data: results/{smoke46,fig1-3,fig1-3b}/
on rx:/root/p1/results/.

## Prediction check
Predicted (model form F, costs.env): nothing predicted this anomaly —
it was an instrument artifact class. For the corrected runs the model's
low-load latency ordering (separation < sharing) is what the design
argues, so: Observed ordering matches the design's claim; the model's
knee prediction (634k predicted vs 525–600k measured, 64 B) is
independent and still graded in result note 4.

## Caveats
n=1 per arm in smoke46 (diagnostic cell, not a final figure number);
130k is 0.25x knee only. The straggler class also invalidated every
non-P0 low-rate W1 row in the fig1-3 matrix — those cells are being
re-run (fig1-3b/fig1-3c); the matrix's P0 and W2 rows stand.

## Claims touched
C-005 (low-load latency side of the trade-off, Figs. 1–2): supported in
part — measured at full delivery (ledger status Pending, PI's call).
C-007 (knee model): untouched here; graded with Fig. 4.

## Next
Complete fig1-3b/fig1-3c re-runs and the wedge A/B (chain6), then the
Fig. 1–3 final render with wedge markers and the [X] abstract fill.
