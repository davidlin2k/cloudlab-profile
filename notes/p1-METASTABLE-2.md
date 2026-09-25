# p1-METASTABLE-2 -- result note: the pre-registered 5 more reps (combined)

Spec: specs/p1-METASTABLE.md (frozen). Batch 2 = reps 6-10 of all four
cell types (20 cells, 2026-09-25 15:03-16:10Z), same wiring, same
detector, step-4 recovery between cells as needed. Combined rows:
analysis/rows-metastab.csv (40 rows). The rules are defined per 5-rep
set ("4 of 5"); both sets and the pooled set are reported. Facts only
-- the memo's order holds: the class before any interpretation.

## Class, per 5-rep set (the frozen rules applied literally)

**Set 1 (reps 1-5): Intermediate at both levels** (reported in
notes/p1-METASTABLE-1.md).

**Set 2 (reps 6-10): Intermediate at both levels.**
- Level 158: not recovered within 120 s = 2/5 (<4); recovered within
  2 s of the reduction = 0/5 (<4).
- Level 316: not recovered within 120 s = 2/5; recovered within 2 s =
  0/5.

**Pooled (10 per level), thresholds scaled to the rule's 80%:**
- Level 158: 4/10 unrecovered (needs >=8); 2/10 recovered <=2 s (needs
  >=8) -> Intermediate.
- Level 316: 5/10 unrecovered; 0/10 recovered <=2 s -> Intermediate.

(Note: running the evaluator over 10 pooled cells printed
"Metastable" because its threshold was the absolute 4 of the 5-rep
rule; corrected to 80% of the set size and committed. Under every
correct reading of the frozen rules -- per set or scaled -- the class
is Intermediate at both levels.)

Baselines: B cells 20/20 healthy (recovery 0.8-2.2 s at the kept
rate, all probes full delivery). No level is Invalid.

## Combined distribution (facts only)

Recovery time from REDUCE, the 20 M cells (offline, from counters.log):

| outcome | n | cells (t_recover_s) |
| --- | --- | --- |
| recovered <=2 s | 2 | M1-1 (1.5), M1-3 (1.1) |
| recovered 2-5 s | 5 | M2-2 (3.0), M2-10 (3.0), M2-5 (2.9), M1-7 (4.5), -- |
| recovered 5-15 s | 2 | M1-8 (8.5), M1-5 (10.5) |
| recovered 15-60 s | 2 | M2-9 (22.2), M1-6 (42.1) |
| recovered 60-120 s | 1 | M2-6 (66.7) |
| not recovered in 120 s, probe OK (late) | 4 | M1-4, M1-10, M2-4, M2-8 |
| not recovered in 120 s, PROBE-DEAD (dead until reset) | 5 | M1-2, M1-9, M2-1, M2-3, M2-7 |

By level: level 158 -- 6 recovered (1.1-42.1 s), 2 late, 2 dead; level
316 -- 5 recovered (2.9-66.7 s), 2 late, 3 dead.

## Reset count (memo item 2)

9 M cells needed the step 4 recovery (the 5 dead-until-reset plus the 4
late); 5 of them only revived after a genuine channel recreation
(32->16->32) + full pre-flight, the others after the `threaded` 0->1
toggle. Every reset is logged in its cell's step4-reset.log.

## Disposition (the frozen spec's own words)

"Intermediate = anything else; report the distribution, run 5 more
reps, make no claim." The 5 more reps ran; both sets are Intermediate;
the distribution is above. **No claim is made at either level.**

Formally on record for the memo's clause: task 1 shows the queue
staying dead until manual reset in 5 of 20 M cells (and late-but-
eventual recovery in 4 more). Per DR-005 task 5 ("If task 1 shows the
queue staying dead until manual reset, stop and tell me before
drafting: that changes the disclosure route") the netdev draft is
stopped pending the PI's call on the disclosure route.
