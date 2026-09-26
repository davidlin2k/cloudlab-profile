# p1-PERSIST (DR-007 Task A): persistence of the dead state across wirings, with the counterbalanced striding arms

Frozen: 2026-09-26 (Saturday), before any PERSIST run. Source:
decisions/DR-007.md (verbatim). Node: @clnode366 (n1). One run at a
time.

## Protocol (per cell, the memo's)

flood to WEDGE or 120 s -> hold 10 s -> reduce to 158k -> monitor
120 s -> stop -> 20 s wait -> 30 s probe at 10k.
PROBE-DEAD = the probe advances rx7 < 270,000 (delivered < 90% of
10k x 30 s). Every dead cell is followed by `p1/rxrecover.sh`
(logging the reviving step); if recovery fails, halt the batch and
alert the PI. `p1/preflight.sh` runs after every ring/flag/channel
change and asserts queue-7 steering before the cell counts.

## Arms, 10 cells each, one of each per round, 10 rounds

| Arm | Wiring | Pre-registered prediction |
|---|---|---|
| A1 | unpin threaded (replication: threaded=1, NAPI kthreads 0-63, IRQ 312 -> CPU 8, k2_rx core 8, flood 790k then 158k kept) | PROBE-DEAD >= 3/10; falsified at 0/10 |
| A4 | default inline: threaded=0, NAPI kthreads free, IRQ 312 -> CPU 8, k2_rx core 8, same flood | Record the count. Any death is the headline. |
| A5 | default inline, app off-core: threaded=0, k2_rx on a core that is NOT the IRQ core and NOT a flood target core | Record the count |
| A6 (negative control) | unpin threaded (A1 wiring), flood held at 525k throughout (no overload; reduce to 158k still applies per protocol) | 0/10 dead. Any death falsifies overload as the trigger |
| A7 | unpin threaded, rx_striding_rq on (A1 wiring + flag pinned on) | >= 8/10 dead (confirmatory) |
| A8 | unpin threaded, rx_striding_rq off (A1 wiring + flag pinned off) | <= 1/10 dead (confirmatory) |

Counterbalancing: within each round the A7/A8 pair runs on/off/on/off
alternating across rounds 1..10 (round 1 = A7 first, round 2 = A8
first, ...). Arm order is therefore not confounded with the feature.
Every arm's cells run with all other dimensions at the task 1 M158
defaults (adaptive-rx on, GRO on, defer 0, flush 0, busy 0, ring
1024), except where the arm names a difference.

## Pre-registered outcome rules (the memo's)

- A1: the replication claim stands if PROBE-DEAD >= 3/10; falsified
  at 0/10.
- A4/A5: descriptive counts (the memo records no prediction); any A4
  death triggers the same-hour alert.
- A6: any death falsifies overload as the trigger.
- A7/A8: confirmatory at >= 8/10 and <= 1/10 dead respectively.
  If A8 dies >= 3/10, the multi-packet path is NOT necessary and the
  mechanism is still open -- report to the PI immediately.
- Every dead A-cell is also a Task B specimen; the most stable
  specimen gets the B2 dump while dead (with Task B's B0 tooling).

## Deliverable (the memo's)

notes/p1-PERSIST-1.md: per-arm PROBE-DEAD counts with exact 95%
binomial intervals, the reviving-step distribution from
rxrecover.sh's logs, and the firmware header (firmware 20.43.3608,
mlx5_core, 6.17.8). Counts only, no narrative.

## Discipline

Smoke before the batch (one A8 cell -- the arm most likely to be
clean -- verifies the wiring and the recovery path). Commit before
running. Supersede, never delete. No public mention of the wedge.
