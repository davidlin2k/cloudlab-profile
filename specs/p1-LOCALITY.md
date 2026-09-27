# p1-LOCALITY (DR-012 step 3): the locality pin sweep, pre-registered

Frozen 2026-09-27 ~10:1xZ, BEFORE any run. Source: decisions/DR-012.md
step 3 (verbatim instruction) + the topology map (notes/topology-n1.md,
committed). Run AFTER the MIGRATE-2 matrix and the ARM_SN step-2 test
(both closed); one run at a time.

## The cells

16 cells, the task-1 M158 protocol with TRACE=1 + the readiness probe
(the same harness as MIGRATE-2, the SWEEP wiring added):

| arm | wiring | cells |
|---|---|---|
| PT10 | the napi kthread pinned to cpu 10 (SAME L3 as the IRQ core 8: {8-11,40-43}; same NUMA node 1) | PT10-1..8 |
| PT24 | pinned to cpu 24 (FAR: NUMA node 3, a different L3 and a different NUMA from the NIC's node 1) | PT24-1..8 |

(cpu 46 / adjacent-CCX is already covered at n=8 by MIGRATE-2's MB arm
(8/8 wedged, classified); RQ1/E2 covers pin10 0/8 under the same M158
protocol. The sweep repeats both pins' bracket with TRACE + the
classification so every cell joins the same analysis.)

## The pre-registered prediction (the memo's)

"Stall probability rises with distance from CPU 8": P(wedge | pin10)
<= P(wedge | pin46) <= P(wedge | pin24). MIGRATE-2/RQ1 already give
pin10 0/8 and pin46 8/8; the sweep's new content is the far pin
(pin24) and the TRACE-classified joins for pin10.

## The decision rule

- pin24 wedges >= pin46's rate and pin10 stays low -> the locality
  gradient is confirmed; the report is the measured curve.
- pin24 does NOT wedge while pin46 does -> distance is not monotone;
  the asymmetry is specific to the 46/8 CCX pair, not a gradient.
  Record it and do not fit a curve.

## Deliverable

notes/p1-LOCALITY-1.md (counts only): wedge counts per pin, the
classification table (16 cells), and the DR-012 step-5 bootstrap
over cells for the wedge-rate differences. One run at a time.
