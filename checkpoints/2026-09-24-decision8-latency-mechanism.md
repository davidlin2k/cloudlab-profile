# 2026-09-24 -- decision 8 closed: the co-location latency mechanism
**Date:** 2026-09-24 18:57Z
**PI decisions executed:** DR-003 decision 8 (the 108 us latency gets a
mechanism before it goes in any claim).

## What was run
perfsched.sh: P0 and P0X at 130k pps = 0.25x knee (W1), `perf sched
record` on the consumer, the same pair with adaptive-rx off. Pass 1
(untraced) = the latency record; pass 2 (traced) = the mechanism. perf
6.8.12 invoked by absolute path (the /usr/bin/perf wrapper rejects this
mainline kernel).

## Result: the mechanism is scheduler wait behind receive processing
| cell | k2_rx wake delay avg | max | switches | p50 latency |
| --- | --- | --- | --- | --- |
| P0 adaptive-rx on | 0.060 ms | 1.24 ms | 104,350 | 88.5 us |
| P0X adaptive-rx on | 0.004 ms | 0.91 ms | 159,757 | 12.5 us |
| P0 adaptive-rx off | 0.034 ms | 3.50 ms | 168,426 | 89.5 us |
| P0X adaptive-rx off | 0.004 ms | 0.89 ms | 263,282 | 13.5 us |

The controlled pair differs only in the app's CPU. Co-located, the app's
wakeup waits 34-60 us (about 60% of its p50) behind the shared core's
receive processing; separated, the wait is 4 us and the latency floor
follows. The gap does NOT close with adaptive-rx off -> decision 8's
first branch (interrupt moderation against co-location) does NOT fire;
logged in anomalies/collisions.md row 2 evidence.

## Decision 8's second branch, still open
"If co-location stays slower at every load on memcached too, we drop
the latency-versus-protection trade-off from the paper." Memcached (W3)
is future work (DR-003 allows nothing beyond the run list tonight). The
trade-off claim stays flagged in the claims ledger (C-005 Pending:
mechanism now measured, memcached check pending).

## Artifacts
analysis/latency-untraced-2026-09-24.txt (clean latency record);
/root/p1/perf/sched-perfsched-*.data (traces); perfsched.sh (perf path
+ PERF_PID name-collision fix).

**Next actions:** (1) ftrace session per DR-003 decision 3 (the wedge
mechanism: napi_schedule, poll entry/exit, interrupt re-enable); (2)
Friday memo by noon with fig-wedge-ab as figure of the week; (3) r650
request blocked on auth (vault save declined; no cl/omni/cert).
