# p1-LOCALITY-1: the DR-012 step-3 locality pin sweep -- counts only

Frozen before any run: specs/p1-LOCALITY.md (cells, prediction,
decision rule). Node @clnode366, 6.17.8, the task-1 M158 protocol,
TRACE=1 + the readiness probe, one cell at a time, 2026-09-27
10:05-11:35Z. PT10-1..8 ran 10:05-10:44Z (arm valid end-to-end).
The FIRST PT24 arm (10:33-10:50Z) is INVALID: a harness bug
(bash case is GLOB, not regex -- `pin[0-9]+` needs a literal '+',
so WIRE=pin24 hit "bad wire" and the cells ran with NO metastab
harness, unpinned). Fixed (pin[0-9]|pin[0-9][0-9]), the orphan
probes killed, PT24-1..8 REDONE 11:04-11:35Z -- the redo is the
authoritative arm (pin cpu=24 pid=467120 OK in every cell).

## Wedge verdicts (the summarize verdict column, DR-012 step 4)

| pin | cells | wedged | stranded gaps (total, per cell) | ready-unserved s (per cell) |
|---|---|---|---|---|
| pin10 (same L3 as IRQ core 8) | 8 | **0/8** | 4 total (0.5/cell; 7/8 cells have ZERO) | 0.0-13.6 |
| pin46 (adjacent CCX, same NUMA; MIGRATE-2 MB arm) | 8 | **8/8** | 62 total (7.75/cell) | 200+ when wedged |
| pin24 (far: NUMA node 3) | 8 | **5/8** | 268 total (33.5/cell; every cell >= 21) | 97.3-182.5 |

Under the tightened definition (step 4) NO PT24 cell is CLEAN:
all 8 are WEDGED (5) or TRICKLING (3: 40-41 stranded gaps each,
~182 s ready-unserved, below the continuous-200-s wedge rule).
PT10: 7/8 CLEAN, PT10-1 TRICKLING (4 stranded).

## Classification (all 16 cells, the trace join)

| arm | stranded | event-silent | wake-lost | wake-flowing |
|---|---|---|---|---|
| PT10 | 4 | 3 | 0 | 1 |
| PT24 | 268 | 164 | 0 | 102 |

PT24-8 is a class-mix outlier: 22 stranded, ALL wake-flowing
(0 event-silent). No wake-lost anywhere in the sweep (consistent
with MIGRATE-2: the class is rare, 4/308 + 1/67).

## The pre-registered decision rule, applied

The memo's prediction: "stall probability rises with distance from
CPU 8" (P(wedge|10) <= P(wedge|46) <= P(wedge|24)).

**The wedge rate is NOT monotone in distance: 0/8 (10) < 5/8 (24)
< 8/8 (46).** The frozen alternative branch fires: "pin24 does NOT
wedge while pin46 does -> distance is not monotone; the asymmetry
is specific to the 46/8 CCX pair, not a gradient. Record it and
do not fit a curve."

The stranded-gap BURDEN, however, IS ordered by distance:
0.5/cell (10) < 7.75/cell (46) < 33.5/cell (24) -- and the
ready-unserved seconds reach 182.5/cell at pin24 vs 200+ only
inside full wedges at pin46. Both counts stand as recorded; no
curve is fitted.

## Step-5 bootstrap (B=10000 percentile, units = CELLS)

- PT10 0/8 vs PT24 5/8: diff = -0.625, 95% CI [-0.875, -0.250]
- pin46 8/8 vs PT24 5/8: diff = +0.375, 95% CI [+0.125, +0.750]
- PT10 0/8 vs pin46 8/8: diff = -1.000, 95% CI [-1.000, -1.000]

The adjacent-CCX pin wedges significantly MORE than the far pin
(CI excludes 0) -- the non-monotonicity is not sampling noise at
n=8.

## Honest caveats

- The first PT24 arm is discarded (harness bug, above); its cell
  dirs are overwritten by the redo (migrate_run.sh rm -rf's each
  dir at cell start). The PT10 arm is untouched by the bug (it
  matched the pre-existing pin10 branch exactly).
- The pin24 cells' cpu_top shows the thread parked on 24 (139k-301k
  samples of ~200-300k) with spillover on 25/27/56/8/9/40 -- the
  pin held for the poller; the residual samples are other threads
  (the probe's own sampler runs on cpu 0 by taskset and does not
  appear in the ch7 cpu histogram).
- The classify ran with the same DR-011 gap rule (>=200 ms flat,
  owned throughout); PT24's high flat-gap counts include idle
  windows at the cell edges (the owned-throughout filter is what
  makes them stranded).
