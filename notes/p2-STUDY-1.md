# p2-STUDY-1 -- receive-path liveness bugs in Linux, 2016-2026 (DR-005 task 3)

**Method (the memo's).** `git clone --filter=blob:none` of torvalds/linux
(local, 5.7G). The memo's `git log` extraction (2016-01-01 to
2026-09-25, no merges, the memo's REGEX over the memo's 16 paths) gave
**1,429 candidates** (analysis/study/study-candidates.tsv). Every full
message was read and triaged (10 parallel slices, the memo's
include/exclude rules verbatim: include only receive-path commits
whose symptom is a liveness failure -- no progress, livelock,
starvation, failure to recover; exclude crashes, leaks, TX-only).
All 1,429 were classified: **72 included, 1,357 excluded**. Rows:
analysis/study/rx-liveness-bugs.csv (72 rows, 12 columns, every hash
validated against the candidate set). Target was at least 30 included;
72 were included, so the criteria were not widened.

## Counts by class

| Symptom | n |
| --- | --- |
| stall | 31 |
| starvation | 14 |
| lost-event | 11 |
| livelock | 8 |
| no-recovery | 8 |

| Subsystem class | n |
| --- | --- |
| driver (48; mlx5e 9, i40e 7, bnxt 6, ixgbe 5, ice 4, virtio_net 4, others 13) -- counted from the `driver:` values | 48 |
| softirq | 9 |
| core-napi | 7 |
| threaded (threaded NAPI) | 5 |
| busy-poll | 3 |

| Fix type | n |
| --- | --- |
| other | 22 |
| re-check | 18 |
| reschedule | 15 |
| barrier | 9 |
| re-arm | 8 |

| Trigger | n |
| --- | --- |
| config toggle | 21 |
| overload | 17 |
| race | 15 |
| unknown | 14 |
| affinity change | 3 |
| reset | 2 |

## The memo's four numbers

1. **Counts by class:** above.
2. **Median lifetime:** **298 days** (n=40 rows with a `Fixes:` trailer
   and a resolvable introducing commit; min 13, max 3434; 32 rows have
   no lifetime because the message carries no `Fixes:` trailer).
3. **Fraction with a sustaining loop** (the message describes a state
   that persists until something external happens): **60 of 72 (83%);
   of the 65 with a known value: 60/65 = 92%** (Y 60, N 5, unknown 7).
4. **Fraction found in production rather than by tests:** of the 14
   rows whose `Reported-by:` marks the finder: **production 3, test 11
   -- 3/14 = 21% production**. The other 58 messages carry no
   `Reported-by:` and are marked unknown (this is reported rather than
   guessed).

Two derived observations (facts from the same table, not claims):
`recovers_when_load_drops` is N for 41 of 56 known values (Y 16,
unknown 15), and the trigger is most often a config toggle (21) or
overload (17) -- with 15 races and 14 unknowns.

## Caveats

- Classification is from commit messages alone (the memo's triage
  rule); `confidence` is high/low per row as judged from the message's
  specificity.
- The extraction's path list bounds the study to core networking plus
  11 driver families; bugs fixed without a `Fixes:` trailer are
  missing from the lifetime statistics but present in the counts.
