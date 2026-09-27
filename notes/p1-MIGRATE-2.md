# p1-MIGRATE-2: the v2-harness re-run of the migration arm (counts only)

Frozen format (per DR-010/DR-011). Node @clnode366, 6.17.8, the task-1
M158 protocol with TRACE=1 + the readiness probe in every cell. This
is the v2 harness (per-session WIRE/TAG/NAMESEL; the v1 script-name
race fixed). Batch 2026-09-27 04:00-04:48Z; the MA arm re-ran in full
05:08-05:36Z, MB-1 re-ran 05:40Z (the arm step had skipped them
silently). Every trace join below is same-run (trace mtimes match the
re-run window; the join aligns probe-to-trace per cell).

Raw artifacts: analysis/migrate2/{migrate2-summ.txt, v1-classify.txt,
migrate2-ma2-detail.txt}; cells on the node at /root/p1/migrate/M[AB]-*.

## The 16-cell matrix (per cell: wedged / gaps / stranded / ready-unserved s)

| cell | wedged | gaps | stranded | ready_unserved_s | cpu_top (top-3) |
|---|---|---|---|---|---|
| MA-1 | YES | 25 | 8 | 72.2 | 12x138k, 9x41k, 40x33k |
| MA-2 | YES | 44 | 29 | 156.3 | 40x98k, 9x53k, 8x24k |
| MA-3 | no | 46 | 35 | 165.5 | 9x82k, 40x68k, 8x31k |
| MA-4 | no | 48 | 37 | 162.6 | 12x131k, 13x90k, 40x24k |
| MA-5 | YES | 47 | 33 | 166.6 | 9x81k, 40x80k, 12x48k |
| MA-6 | no | 50 | 35 | 176.6 | 12x95k, 14x56k, 13x45k |
| MA-7 | YES | 48 | 36 | 173.5 | 45x138k, 44x47k, 40x40k |
| MA-8 | no | 44 | 33 | 149.8 | 12x96k, 40x90k, 46x26k |
| MB-1 | YES | 21 | 3 | 27.8 | 46x296k, 44x4k |
| MB-2 | YES | 34 | 21 | 126.2 | 46x261k, 12x11k, 10x5k |
| MB-3 | YES | 28 | 12 | 102.0 | 46x168k, 14x19k, 13x11k |
| MB-4 | YES | 23 | 8 | 81.6 | 46x135k, 12x25k, 13x25k |
| MB-5 | YES | 24 | 5 | 56.4 | 46x119k, 15x35k, 14x10k |
| MB-6 | YES | 23 | 5 | 55.8 | 46x129k, 15x14k, 14x12k |
| MB-7 | YES | 21 | 5 | 36.8 | 46x160k, 13x3k, 14x2k |
| MB-8 | YES | 23 | 3 | 18.7 | 46x243k |

## The arm verdicts (the headline)

| Arm | Wiring | Wedged | vs v1 |
|---|---|---|---|
| M-A (unpinned/migrating) | 0-63 | **4/8** | v1 8/8 |
| M-B (pinned to 46) | {46} | **8/8** | v1 5/8 |

**The locality asymmetry sharpens: the pinned arm wedged in EVERY v2
cell** (v1: 5/8). Migration alone does not force a wedge (MA 4/8).
Combined with pin10 0/8 (RQ1/E2) and pin46 8/8, the wedge tracks
WHICH cpu the poll runs on, exactly as the topology note predicts:
cpu 46 shares no L3 with the IRQ core 8; cpu 10 does.

## The DR-011 gap classification (16/16 cells, 308 stranded gaps)

| Class | Count | Fraction | DR-011's mapping |
|---|---|---|---|
| event-silent (0 wake attempts) | 213 | 69% | the driver or the device |
| **wake-lost (wake issued, thread never ran)** | **4** | 1.3% | the core scheduler path |
| wake-flowing (the thread runs, no progress) | 91 | 30% | something else |

MA: 246 stranded = 167 event-silent + 4 wake-lost + 75 wake-flowing.
MB: 62 stranded = 46 + 0 + 16.

**Record correction (supersedes the p1-MIGRATE-1 sentence "wake-lost
never fires"):** that claim held over the v1 classified subset (134
gaps; MA-2's v1 trace did not join). The v2 MA-2 join classifies 4
wake-lost gaps: t=52488.9, 52494.0, 52503.9, 52508.9 (each ~5 s,
napi_schedule 2-4 on cpu 8, ZERO thread wakeups and switch-ins in the
window). The core wake path IS implicated in a small minority of
gaps. Event-silent still dominates (213/308), so the driver/device
side remains the primary site; the stale-arm hypothesis (DR-012 step
2) is unchanged and is the next pre-registered test.

## The analyze fix (supersede, never delete)

v1_classify runs of the v2 matrix initially printed CLASS SUMMARY for
12/16 cells: migrate_analyze.py crashed with IndexError on the
TRAILING stranded gap (its end index == len(rows)) in both the
classification and the detail loops. The join itself was sound (the
per-gap lines printed; the crash hit only the last gap). Fixed by
clamping b = min(b, len(rows)-1) (commit with this note); all 16
cells re-classified from the same data. Cells classified before the
fix are unaffected by it (a trailing-gap crash always aborted the
whole classification section, so no partial counts existed).

## MA-1 state anomaly note (carried from the batch close-out)

MA-1's probe ends in napi state 17 where every other cell ends in 16.
Per the build-tree DWARF the state byte is a bitfield; 0x11 = SCHED |
LISTED vs 0x10 = LISTED. State 17 = the thread still registered a
poll request at probe end (the cell was wedged at cutoff); state 16 =
the thread parked. Consistent with MA-1 being a WEDGED cell (YES)
whose final samples sit inside a stall. Not a harness defect.

## What this matrix does not settle

- The v1-vs-v2 wedge-count flip (MA 8/8 -> 4/8) is within run-to-run
  variance at n=8; no per-arm rate claim is made beyond "both arms
  wedge, MB more often".
- MA-2's 4 wake-lost gaps are 4 of 308; the wake-lost class's base
  rate needs the DR-012 step-5 bootstrap before any claim.
- The stale-arm test (specs/p1-ARM_SN.md, frozen) is the decisive
  next run; this note only closes the matrix.
