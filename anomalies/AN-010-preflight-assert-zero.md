# AN-010: intermittent preflight steering-assert zero on 6.18.9
# (facts only; DR-013 rule: facts, then wait for the PI)

Seen: after the T1d reboot onto 6.18.9+ (the program's first node
reboot), preflight.sh's queue-7 steering assert intermittently reads
rx7 advance 0, ~1 in 2-3 attempts, while other attempts read the
expected 80k. migrate_run's 60 s retry always recovered (no cell
data was lost to the gate: a cell counts only when its preflight
passed).

Instrumented failure facts (T1DA-1 cell.log, the instrumented
preflight):
- the sender sent the full 80064 packets, 10008/s, wall 8.00 s,
  enobufs=0 (inside the 14 s assert window);
- NO per-queue counter moved: rx0..7 deltas 0-3 (noise); the delta
  dump covered queues 0-15 only -- queues 16-63 were not sampled;
- the ntuple rules were present (125 rules, all "Direct to queue 7");
- the phy/sw counters were NOT sampled in this path (next time).

Context: every failing assert followed a cell that ran a 90 s
158k-pps flood minutes earlier; the preflight itself reconfigures
the ring (ethtool -G rx 1024, rx_striding_rq, threaded) before
re-installing the W1 rules and asserting. Suspicion (NOT verified):
a post-reconfig device window where steered flows are silently
dropped. Manual preflights minutes later always asserted.

Not done (per the stop list): no root-cause chase. The gate holds;
the retry recovers; the cells are unaffected. If it starts failing
RETRIES too, escalate to the PI.

Update 2026-09-28 ~06:40Z (still facts only; the suspicion is now
better supported):

- Run 3 of T1e (net-next) failed 6 consecutive preflights (cells
  2-7, ~25 min) -- the first time retries failed too.
- Full-queue diagnostic during the failing state (queues 0-63 +
  phy + sw): a control probe of 80k arrived perfectly (phy +80269,
  rx7 +80064, nothing elsewhere) minutes after the same preflight
  had failed -- the steering works; the window is real and self-
  healing.
- The 70-rule DB held ~14 copies of each W1 rule: preflight.sh was
  ADDING 5 rules per attempt, every attempt. Each ethtool -N add
  reprograms the device flow table; the reprogram window scales
  with the DB size, which explains failures appearing as the DB
  grew (early runs passed at 20-25 rules, run 3 failed at 60-125).
- Fix: preflight.sh v2 installs the W1 rules idempotently (checks
  the existing rule DB by src-port and adds only missing rules;
  0 adds verified on a clean pass, assert passed instantly after).
  Residual failures after the fix (2 cells) cleared on refill.
- Remaining device-side question (not chased): whether a rule ADD
  alone can briefly swallow steered flows, independent of DB size.
