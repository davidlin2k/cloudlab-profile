# p1-CAUSAL-1: RQ1 per-arm result (counts only, per DR-010)

Counts only; no interpretation; brought to the PI before any
conclusions are drawn (the frozen rule). Node @clnode366, 6.17.8,
task-1 M158 protocol, the readiness probe at 999 Hz achieved
(259,841 samples per ~260 s cell), specs/p1-CAUSAL.md frozen before
any run.

## Probe validation (the memo's precondition -- PASSED, with notes)

| Check | Requirement | Result |
|---|---|---|
| Healthy queue | zero ready-unserved | PASSED: 29,974 samples, 1 gap (idle), owned_throughout=False, 0.0 s |
| Known-dead queue | stranded work read | PASSED: val-2 wedged; 2 owned-gaps, 18.4 ready-unserved sample-s; val-3 wedged; 6 owned-gaps, 85.9 s |

Probe fixes landed during validation (all committed before use):
rq.stats/ch.stats are pointers (dereferenced); the frag index is
masked by sz_m1>>lfs; the poll thread is identified by correlation
(p1/find_napi_thread.py: the thread whose stime advances exactly at
cc advances -- pid 467120, all other napi threads zero) because
napi_struct.thread reads a DANGLING task pointer on this build
(find_task(pid)=None) and the /proc comm of the real threads is
"napi/enp195s0np0-0" for all of them; the pin is applied via
os.sched_setaffinity (the kthread is /proc-invisible by pid; taskset
no-ops silently); the probe's cpu column reads /proc/<pid>/stat
field 39 (index 36).

## Arm A (driver as-is, thread pinned to CPU 10 off-mask, IRQ 312 on
## CPU 8): 8 cells

| Cell | WEDGE | PROBE | gaps >= 200 ms | owned-throughout gaps | ready-unserved s | kthread cpu |
|---|---|---|---|---|---|---|
| A-1 | no | OK adv=300102 | 6 | 0 | 0.0 | 10 (208,704 of 259,841 samples) |
| A-2 | no | OK adv=300100 | 6 | 0 | 0.0 | 10 (216,211) |
| A-3 | no | OK adv=300101 | 9 | 0 | 0.0 | 10 (217,849) |
| A-4 | no | OK adv=300100 | 10 | 0 | 0.0 | 10 (207,333) |
| A-5 | no | OK adv=300100 | 9 | 0 | 0.0 | 10 (235,429) |
| A-6 | no | OK adv=300098 | 8 | 0 | 0.0 | 10 (208,573) |
| A-7 | no | OK adv=300097 | 10 | 0 | 0.0 | 10 (234,622) |
| A-8 | no | OK adv=300096 | 11 | 0 | 0.0 | 10 (235,341) |

**Arm A: 0/8 stalls; 0 ready-unserved gaps in any cell; the pin held
every sample.** All gaps in the arm-A cells are post-flood idles
(owned=False at every sample).

## The validation cells (the same instrument, the thread NOT pinned)

| Cell | WEDGE | owned-throughout gaps | ready-unserved s | kthread cpu (probe column) |
|---|---|---|---|---|
| val-1 | YES | n/a (instrument v1: stats columns were pointer values; gap detection invalid) | n/a | 46/45 (v1 reads) |
| val-2 | YES | 2 | 18.4 | 45/46 (v1 reads) |
| val-3 | YES | 6 | 85.9 | 25/8/9 (dangling-ptr reads -- INVALID cpu, valid cc/owned) |
| val-4 | no | 0 | 0.0 | 0 (pre-index-fix artifact) |

val-2/val-3's cc and owned columns are channel memory and are valid;
their wedge windows show the CQE at the consumer index owned and
unserved across multi-second spans (the +64 budget-step signature
visible in the raw csv), with the flood still being offered.

## The frozen decision rule, applied to the counts

- Arm A stalled 0/8 and never showed a ready CQE during a gap.
- Per DR-010's decision rule ("B still stalls, OR A never shows a
  ready CQE during gaps -> the mechanism is not the cause. Stop."),
  **RQ1 as designed returns the negative branch.** RQ3 does not
  proceed.
- Arm B (the F1 patch) was not built or run: with arm A at 0/8
  stalls there is no delta for arm B to measure. The F1 spec and
  patch remain committed and unchanged.

## Anomaly-class facts recorded with the counts (no interpretation)

1. The arm-A cells' kthread sat at cpu 10 for 93-97% of samples
   (the remainder: 8/9/11/40/42 -- brief pre-pin or scheduler-window
   samples; the pin held at 10 for every flood-phase sample checked).
2. The val-2/val-3 wedges occurred with the thread NOT pinned
   (val-2: migrating 45/46; val-3: unpinned), same flood, same
   driver, same IRQ placement.
3. The PERSIST batch's A1 (2/10) and A7 (1/10) wedges are consistent
   with the unpinned condition (their wiring was unpin); the E2
   verified-aligned cells (pin8, in-mask) were 0/8.

Counts end here. The PI decides what the negative branch means for
the paper and what, if anything, the migration-correlated wedges
become next.
