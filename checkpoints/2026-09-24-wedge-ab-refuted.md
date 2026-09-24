# 2026-09-24: wdiag A/B verdict -- the poll-affinity hypothesis is REFUTED

WDIAG DONE 18:10:10Z. 48 valid cells (6 arms x 8 reps x 195 s),
pre-registered (DR-002), graded mechanically by wdiageval3.

| arm | wedged/8 | aff_active (/s) | onsets (s) |
| --- | --- | --- | --- |
| mis-P3 | 4 | 785 | 11, 32, 54, 83 |
| mis-P4 | 5 | 586 | 13, 22, 24, 189, 196 |
| ali-P3 | 6 | 1065 | 11, 11, 15, 20, 21, 190 |
| ali-P4 | 6 | 598 | 15, 29, 31, 33, 46, 93 |
| P2 | 4 | 948 | 16, 17, 19, 84 |
| unpin | 8 | 1267 | 9, 9, 10, 11, 12, 13, 14, 19 |

Verdicts: mis NOT MET (pred: >=7/8 + aff>1e5/s); ali VIOLATED (pred:
<=1/8); REFUTATION RULE FIRES (ali >=4/8 with aff near zero). Second
surprise: aff_change is ~600-1300/s in every arm -- the earlier
"22.9M vs 3.9k" Test-1 signal was cumulative exposure, not rate.

Stands regardless: the wedge is real (25/48 today; 24/24 wedge-m);
unpin 8/8 with the fastest onsets (C-011 evidence strengthened);
recovery = self-recovering performance bug (netdev route, no embargo,
AN-003).

Decisions in force: DR-003 #3 (stop; ftrace tomorrow: napi_schedule,
poll entry/exit, IRQ re-enable; no patch, no new theory tonight);
DR-002 reframe SUSPENDED pending mechanism; C-010 Refuted; C-011
Pending (PI promotes).

In flight: perfsched.sh (decision 8 mechanism cells, started 18:28Z;
independent of the wedge theory).

Next actions: (1) ftrace session tomorrow on unpin + ali-P4 cells;
(2) survival-curve figure (the memo's figure of the week) from the
onsets above; (3) perfsched results -> the 108 us mechanism or the
claim drop per decision 8.
