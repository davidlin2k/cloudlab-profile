# p1-MIGRATE-1: the frozen v1 batch + the v2 HOP batch (counts only,
# per DR-010/DR-011)

FROZEN FORMAT. Node @clnode366, 6.17.8, the task-1 M158 protocol with
TRACE=1 + the validated readiness probe (999 Hz) in every cell.
specs/p1-MIGRATE.md v1 froze before the run; v2 froze after the v1
batch completed and governed the HOP batch.

## The frozen v1 batch

| Arm | Wiring | Wedged |
|---|---|---|
| M-A (unpinned/migrating) | 0-63 | **8/8** |
| M-B (pinned to 46) | {46} after the wiring | **5/8** |

Reference pinned cells (the same harness, RQ1): pin10 0/8; pin8
in-mask 0/8 (E2). **The frozen M-B prediction (0/8) is falsified.**
Static pin46 wedged with zero migrations after the pin: migration is
not the necessary condition; the wedge tracks which cpu the poll
runs on.

## The DR-011 gap classification (the v1 cells with a clean trace
## join: MA-1/3/4/6, MB-1/4/5/6 -- 134 classified gaps)

| Class | Count | DR-011's mapping |
|---|---|---|
| event-silent (0 wake attempts) | 99 | the driver or the device |
| wake-flowing (the thread runs, no progress) | 35 | something else |
| **wake-lost (the wake issued, the thread never ran)** | **0** | the core scheduler path |

**Wake-lost never fires.** Per the memo's class separation, the
core-scheduler wake path is not implicated in any classified gap.
MA-6 and MB-4 carry most of the event-silent weight (15 and 34).
MA-1: 5 stranded gaps = 4 event-silent (one with 1 migration inside
the window) + 1 wake-flowing (44,316 wakes ~= 44,298 switch-ins,
44,778 polls in the 76 s window, 11 migrations -- the thread polls
at ~585 Hz and loses to the offered load). MA-2/5/7/8 and
MB-2/3/7/8's CLASS lines are pending a trace-join rerun (the probe
side counted: 3/3/3/2 and 56/64/44/37 stranded gaps respectively).

## The v2 HOP-1046 batch (30 cells; 21 delivered probes; 9 failed at
## preflight on the post-M-B dead window -- the preflight-retry fix
## landed mid-batch)

Wedged 17 / clean 2 of the 19 probe-bearing cells (HOP-27 and
HOP-30 stayed clean while showing 42 and 27 stranded gaps -- the
trickling regime without the full stall).

> ADDENDUM 2026-09-27 (DR-012 step 4, supersedes the "clean 2"
> wording above, which is kept for the record): under the tightened
> definition a cell is CLEAN only with ZERO stranded gaps, so
> HOP-27 (42) and HOP-30 (27) are TRICKLING, not clean. The batch
> verdict becomes: wedged 17 / trickling 2 / clean 0 of the 19
> probe-bearing cells. See notes/p1-LOCALITY-1.md and the
> rq1_summarize.py verdict column.

**The decisive statistic (259 stranded gaps across the 19 cells):**

| Gap class | Count | Fraction |
|---|---|---|
| migration-moment (starts <= 2 ms after an observed cpu change) | 71 | 27% |
| residence-46 (>= 80% of the gap's samples on cpu 46) | 163 | 63% |
| residence-10 | 15 | 6% |
| (remainder: residence-mix / unaligned) | 10 | 4% |

The chance rate for a random moment to fall within 2 ms of a hop is
2/100 (the 100 ms hop period): the observed 27% is ~14x enriched.
The first pass with a 50 ms window read 47% -- degenerate (the
window covered the whole hop period); the 2 ms window is the honest
one. The probe's cpu column shows the thread on 46 for 55-95% of
each cell despite the 50/50 hop requests: the scheduler lingers on
46 after each hop.

Both signals are present in the same data: strand onsets cluster at
migration moments (27% vs 2% chance) AND the strands persist during
46-residence (63%). A third-variable confound (the flood's arrival
pattern causing both) is not excluded by this data alone.

## What the counts say about the DR-011 go/no-go inputs

1. Migration-causality: the at-hop-start enrichment is present but
   the residence term is larger; neither hypothesis dominates.
2. The gap class: wake-lost = 0 -> the core wake path is not the
   site; event-silent dominates -> the driver/device side.
3. The locality asymmetry (pin10 0/8 vs pin46 5/8 vs unpinned 8/8)
   is unexplained by either hypothesis and is now the sharpest
   unexplained fact in the record.

Counts end here. Per DR-011: the PI weighs the go/no-go; the
one-week box runs to ~2026-10-03.

## Instrument notes (all committed before use)

- The hopper (p1/hopper.py) + the hop log; the probe's cpu column
  self-calibrates the gap-vs-hop join (no cross-process offset).
- The wake trace's ch7 polls filter by the napi struct address
  (ch + 10000 DECIMAL = +0x2710); the first analyzer run used a
  hex-10000 arithmetic error (0 matches -- fixed).
- The analyzer's probe/trace alignment uses the tail-50 match
  (~7 s spread in MA-1 -- the finder-flood portion of the probe csv
  has no trace counterpart); the classifications are robust (the
  gap windows are 1-76 s).
- The preflight-retry fix (60 s) landed mid-batch after HOP-1/2/3
  burned on the post-M-B-8 dead window; the queue had
  self-recovered by the retry.
