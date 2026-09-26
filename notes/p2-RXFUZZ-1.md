# rxfuzz night 1 (DR-005 task 6): 96 cells, 6 hit cells, 5 metastable

Date: 2026-09-25 19:2xZ - 2026-09-26 01:12Z. Spec: specs/p2-RXFUZZ.md
(frozen). Runner: p2/rxfuzz.py (committed before it ran; smoke run
passed first -- and the smoke caught an offered-interval bug, fixed
and re-smoked). Seed 20260925. Node @clnode366.

## The night's numbers

96 cells, 4 schedules x 9 dimensions sampled. 6 cells hit (24 hits.csv
rows); every hit cell went PERMANENT (probe failed, step-4 recovery
ran and is logged in the cell directory); 5 of 6 classified METASTABLE.

| cell | sched | onset_s | threaded | placement | adaptive | ring | striding | gro | busy | defer | flush | oracles |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 015 | 1 | 104.1 | 1 | unpin | off | 1024 | on | off | 0 | 0 | 0 | STALL/META/COLL/PERM |
| 038 | 3 | 98.1 | 1 | irq-cpu | on | 8192 | on | on | 0 | 2 | 200000 | STALL/META/COLL/PERM |
| 056 | 3 | 461.4 | 1 | other-l3 | off | 1024 | on | off | 50 | 2 | 0 | STALL/META/COLL/PERM |
| 069 | 1 | 110.2 | 0 | irq-cpu | on | 8192 | on | on | 0 | 2 | 200000 | STALL/META/COLL/PERM |
| 086 | 2 | 4.1 | 1 | unpin | off | 1024 | on | on | 0 | 2 | 200000 | STALL/COLL/PERM |
| 089 | 1 | 123.3 | 0 | smt-sibling | off | 1024 | on | off | 0 | 2 | 200000 | STALL/META/COLL/PERM |

## Facts (no claim)

- All 6 hit cells ran with rx_striding_rq on. 90 clean cells include
  both striding states, so this is an observation, not a controlled
  result -- but it independently matches task 4's A/B (0/8 wedged with
  striding off vs 8/8 on).
- 5 of 6 hit cells sit OUTSIDE the task 1 M158 corner (different
  placement, moderation, ring size, defer/flush) -- the search finds
  wedging configurations the fixed task 1 wiring never sampled. Cell
  038 (irq-cpu pinning, adaptive on, GRO on, ring 8192) is the
  strongest example.
- Onset caveat: cell 056's STALL onset (461 s) is after its load ended
  (schedule 3 = 200 s) -- the oracle caught the stalled queue during
  the probe window, so its METASTABLE row reflects a stall recognized
  late, not a new post-load collapse. The other five onsets are
  in-load. Recorded as an oracle caveat; no number bent.
- Traces: 10 s trace-cmd captures exist for the first hit of each
  class (4 classes, in cell-015's directory), plus per-cell counters,
  dmesg, and recovery logs for every hit cell.

## Next (the spec's own workflow)

Minimization for all 6 hits: reset one dimension at a time to its
default, rerun, keep only dimensions whose reset removes the hit,
confirm 3x. Launched after this note.
