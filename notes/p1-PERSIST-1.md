# p1-PERSIST-1: PERSIST per-arm counts (DR-007 Task A)

FROZEN FORMAT -- counts fill in as the batch lands; no narrative.
Node @clnode366, firmware 20.43.3608, mlx5_core, kernel 6.17.8.
Batch: p1/persist.sh, 7 arms x 10 rounds (A7/A8 position
counterbalanced, A0 rotated), rxrecover after every dead cell.
Started: 16:05Z 2026-09-26. Smoke: M1-p-A8-0 (striding off) PROBE-OK
adv=300096. PERSIST DONE 20:33:35Z.

## Per-arm PROBE-DEAD counts with exact 95% (Clopper-Pearson) intervals

| Arm | dead/total | 95% CP interval | prediction (frozen) | verdict |
|---|---|---|---|---|
| A0 | 0/10 | [0.0%, 30.8%] | none (quiet-window rule) | all 10 DEEP-TRICKLE |
| A1 | 2/10 | [2.5%, 55.6%] | >= 3/10 dead; falsified at 0/10 | **NOT MET** |
| A4 | 0/10 | [0.0%, 30.8%] | descriptive; any death = same-hour alert | no alert; softirq arm clean |
| A5 | 0/10 | [0.0%, 30.8%] | descriptive | no deaths |
| A6 | 0/10 | [0.0%, 30.8%] | 0/10 dead; any death falsifies overload | MET |
| A7 | 1/10 | [0.3%, 44.5%] | >= 8/10 dead (confirmatory) | **NOT MET** (~10% vs ~80%) |
| A8 | 0/10 (+ smoke) | [0.0%, 30.8%] | <= 1/10 dead (confirmatory) | MET |

(Compute the CP intervals with the task-4 evaluator's exact-binomial
helper; do not approximate.)

## A0 quiet-window classification (Amendment A)

| A0 cell | quiet_adv (rx7 over 300 s) | oob_adv | probe | class |
|---|---|---|---|---|
| 1 | 4 | 0 | adv=300097 | DEEP-TRICKLE |
| 2 | 22 | 0 | adv=300098 | DEEP-TRICKLE |
| 3 | 28 | 0 | adv=300118 | DEEP-TRICKLE |
| 4 | 18112 | 0 | adv=344216 | DEEP-TRICKLE |
| 5 | 28 | 0 | adv=300099 | DEEP-TRICKLE |
| 6 | 28 | 0 | adv=300099 | DEEP-TRICKLE |
| 7 | 25 | 0 | adv=300098 | DEEP-TRICKLE |
| 8 | 29 | 0 | adv=300099 | DEEP-TRICKLE |
| 9 | 13 | 0 | adv=300099 | DEEP-TRICKLE |
| 10 | 18 | 0 | adv=300096 | DEEP-TRICKLE |

PERMANENT-LATCH count: 0/10. Nine of ten cells trickle at 0.01-0.07
pps through the quiet window (essentially frozen) and then revive at
the probe's first traffic; cell 4 drained 18k during quiet and still
advanced 344k at probe (it was mid-recovery). No cell needed the
latch classification; the deep-trickle/revive-on-traffic shape is
uniform.

Rule (frozen): PERMANENT-LATCH = quiet_adv 0 AND probe DEAD;
DEEP-TRICKLE = quiet_adv > 0 OR probe OK. Parser: p1/a0_parse.py.

## Reviving-step distribution (rxrecover logs)

[Pending the per-cell rxrecover log audit; aggregate from the batch:
0 recovery failures, 0 alerts (grep ALERT / "RECOVERY FAIL" = 0).
Per-rung counts to be filled after the log audit -- the frozen rule
counts each rung that fired across the 3 dead cells (A1 x2, A7 x1).]

## Incidents

None: 0 recovery failures, 0 preflight failures, 0 same-hour alerts
(A4 fired never -- 0/10 deaths). One A8 smoke cell (M1-p-A8-0) ran
before the batch proper; it is not counted in the A8 table (which
covers the 10 batch cells) and recovered at the monitor + probe
ceiling.

## The honest misses (recorded before any interpretation)

1. A1 2/10 vs the >= 3/10 replication threshold -- the replication
   claim does NOT stand this batch.
2. A7 1/10 vs >= 8/10 -- the striding-on arm latched at ~10%, versus
   8/8 in the task-1-era ring-default cells. An ~8x rate drop.
3. A5 0/10 sits below even A1's observed rate (frozen rule said ~A1).

Possible contributors -- HYPOTHESES ONLY, untested here: the ntuple
steering route (explicit W1 rules vs the RSS-key route that never
worked pre-reboot), the fresh boot's kthread placement distribution,
ring-size differences between the PERSIST arms and the task-1 cells
(A-cells run ring 1024 per task-1; the task-4 ring-default cells ran
1024 too -- but the arm wiring differs in threaded/adaptive states).
Per decisions/DR-010.md the next run (RQ1) is NOT conditional on
resolving the rate discrepancy.
