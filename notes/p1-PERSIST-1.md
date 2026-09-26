# p1-PERSIST-1: PERSIST per-arm counts (DR-007 Task A)

FROZEN FORMAT -- counts fill in as the batch lands; no narrative.
Node @clnode366, firmware 20.43.3608, mlx5_core, kernel 6.17.8.
Batch: p1/persist.sh, 7 arms x 10 rounds (A7/A8 position
counterbalanced, A0 rotated), rxrecover after every dead cell.
Started: [FILL]. Smoke: M1-p-A8-0 (striding off) PROBE-OK adv=300096.

## Per-arm PROBE-DEAD counts with exact 95% (Clopper-Pearson) intervals

| Arm | dead/total | 95% CP interval | prediction (frozen) |
|---|---|---|---|
| A0 | [FILL]/10 | [FILL] | none (rule below) |
| A1 | [FILL]/10 | [FILL] | >= 3/10 dead; falsified at 0/10 |
| A4 | [FILL]/10 | [FILL] | descriptive; any death = same-hour alert |
| A5 | [FILL]/10 | [FILL] | descriptive |
| A6 | [FILL]/10 | [FILL] | 0/10 dead; any death falsifies overload |
| A7 | [FILL]/10 | [FILL] | >= 8/10 dead (confirmatory) |
| A8 | [FILL]/10 | [FILL] | <= 1/10 dead (confirmatory) |

(Compute the CP intervals with the task-4 evaluator's exact-binomial
helper; do not approximate.)

## A0 quiet-window classification (Amendment A)

| A0 cell | quiet_adv (rx7 over 300 s) | oob_adv | probe | class |
|---|---|---|---|---|
| 1 | [FILL] | [FILL] | PROBE-OK | DEEP-TRICKLE |
| [FILL 2..10] | | | | |

Rule (frozen): PERMANENT-LATCH = quiet_adv 0 AND probe DEAD;
DEEP-TRICKLE = quiet_adv > 0 OR probe OK. Parser: p1/a0_parse.py.

## Reviving-step distribution (rxrecover logs)

[FILL: counts per rung across dead cells -- probe-only, threaded
toggle, channel recreate 16->32, none needed]

## Incidents

[FILL: any recovery failure (halt+alert), preflight fails, anomalies]
