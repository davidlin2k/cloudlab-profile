# AN-009: low-load TCP latency anomaly (2026-09-25)

Facts (logged at the PI's instruction, DR-005 "Parked items"): under
memcached/mutilate the idle p99 is ~105 us and the p99 at 190k QPS is
lower than at 47.5k QPS. At 47.5k (0.25x knee) the p99 is about 1.2 ms
-- higher than at 190k and about 10x idle.

Standing restriction (PI, verbatim): make TCP latency claims only at
0.5x the knee and above until a C-state and moderation check explains it.

No mechanism explanation is offered here (the interpretation rule).
A C-state and interrupt-moderation check is the parked follow-up.
