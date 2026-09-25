# 2026-09-25 -- task 3 wedge tracing: onset + recovery timelines

Task 3 (DR-004, pulled forward from Monday per operator instruction)
ran to its deliverable today: six cells (unpin 3/3 wedged, ali-P4 0/3
censored at the 120 s watch window), full ftrace episodes on one
monotonic clock, per-second counter logs.

Both required timelines exist and are recorded in
anomalies/AN-006A-wedgetrace.md (facts only, interpretation held for
the PI per the run-book):

- Onset: the queue-7 kthread (napi/enp195s0np0-8263, pid 1594438)
  finishes a budget-63/64 poll and switches to S; the last interrupt
  (irq 312, CPU 8) and the last wakeup (kthread, CPU 13/13/40) both
  precede that final poll. After it: 18.7 s of complete queue-7
  silence while the wire keeps arriving (oob +97k/s) and rx7 is
  frozen.
- Recovery: the first queue-7 event after the flood stop is an
  INTERRUPT on irq 312 (CPU 8) -- 19 ms / 262 ms / 8.9 s after the
  stop across the three cells -- followed 7-12 us later by the
  kthread wakeup and the unchanged budget-63 cadence. The 10k pps
  probe starts 20+ s later and is not involved.

Also this session: the task-2 control-plane result note and
falsification record, the W39 Friday memo update, the task-1 record
set (C-014 Supported), and an infra event: the root filesystem hit
100% from a stale 39 GB observability log (/var/log/llmd/epp.log,
last written Sep 23) which was truncated; experiment data untouched.

Next: the PI sees the timelines before any interpretation (run-book
rule); the netdev report path stands if the wedge is still unexplained
after the PI's read.
