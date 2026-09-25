# FINDINGS (append-only)

### C1-CLOCK.1 — 2026-09-24 — level H
With the emitter timer fixed (AN-001), 25k/50k/75k streams through
HAProxy deliver 100% of offered load (0.998-1.032 of 1.0/2.0/3.0
Mtok/s over 27 runs of 75s) with zero drops and zero stall-seconds
per stream, and aligned/random/per-engine phases do not differ; at
100k the split 3.47/3.98/4.02 Mtok/s rests on one outlier rep. Rate
values interim per AN-002.
Supersedes: none · Note: notes/C1-CLOCK-1.md · Figure: F-C1-CLOCK-1

### C1-CLOCK.2 — 2026-09-24 — level H
The decode step is smeared at the wire at these scales: with
one-token-one-segment emission, 50k and 150k "aligned" streams put
p50 = 4.0-4.2% of each 25ms step's packets in its first 1ms at the
proxy NIC (the uniform-phase value is 4.0%; 13.9M and 14.5M packets
captured over 12s), peakedness 1.5-1.6 — the write path serializes
~25k writes per step into a sawtooth, so wire-level incast requires
sender-side coalesce+multiplex.
Supersedes: none · Note: notes/C1-CLOCK-1.md · Figure: pending

### p1-LADDER.1 — 2026-09-24 — level H
Moving the application off the interrupt core keeps inline receive
processing alive under flood: at 1.5x/2.0x the receive knee the default
co-located echo delivers 9.0%/0.2% of offered load while the same inline
path with the app on its own core delivers 97.5%/74.2% (n=2-3, 10k
bootstrap 95% CIs in the checkpoint; 111 verified rows after flow-split
and generator-budget filters). The threaded placements wedge at these
loads (p1-LADDER.2), so the separation that drains is app-separation
with inline processing.
Supersedes: none · Note: notes/p1-LADDER-3.md · Figure: F-p1-LADDER-1

### p1-LADDER.2 — 2026-09-24 — level H
Threaded-NAPI receive placement stalls under sustained flood on this
host regardless of rung: 24/24 cells (P2/P3/P4 x PIN_IDLE 0/1 x 2 reps
at 790 kpps) wedged -- queue silent for the rest of the 71 s budget,
onset t=2..68 s, rx ring loss ~750 k/s at onset, IRQ masked and the
napi kthread asleep (AN-003). C-state pinning is ruled out as the
trigger (12/12 collapsed in both halves). The wedge is a property of the
threaded mode, not of the placement choice.
Supersedes: none · Note: notes/p1-LADDER-3.md · Figure: F-p1-LADDER-1 (wedge markers)

## p1-LADDER.3 -- the utilization metric was blind to IRQ-context receive work

**Statement.** On this kernel (6.17.8, CONFIG_IRQ_TIME_ACCOUNTING not
set, NO_HZ_FULL) the receive core's busy time is charged to the idle
bucket when it arrives as sub-tick IRQ-context bursts on an otherwise
idle CPU. At P0X 390k pps the PMU basis (ref-cycles / TSC 3.250 GHz)
reads 36.53 s of busy over the 73 s first-pass bracket while
/proc/stat's fields sum to 0.22 s (166x undercount). Where a thread
keeps the CPU busy (P0) the stat basis captures most of it (57.43 vs
42.07 s).
**Evidence.** AN-007 (facts, arbiter, verdict); rows: /root/p1/
rows-task1.csv (30 cells, gates pass); calibration: 3,256,316,473
ref-cycles in 1.0019 s busy loop. Level H.
**Fix.** cpuN_busy_s now comes from per-CPU ref-cycles bracketed to the
consumer's mpkts window (task1b re-run); the /proc/stat sum is kept as
cpu8_busy_stat_s. Per-field stat seconds are stored per row. The
softirq_s column also carried an index bug (steal read as softirq),
which produced the cal-1 anchor note's phantom "hidden share"; the real
hidden share (C-006) is task-accounting invisibility and stands.
**Supersedes:** none (first finding on the metric).
**Status:** costs and Figure 3 recomputation pending the task1b data.

## p1-LADDER.4 -- corrected costs: the thread sees half the real cost, and the knee model needs no fitted constant

**Statement.** With the corrected busy metric (task1b, 30 cells, all
gates pass), at 390k pps / 64 B: per-packet system CPU is 2026-2935 ns
across placements while the app thread's schedstat accounts for
906-1407 ns -- the thread sees 43-55% of the real cost (Figure 3,
vision QA PASS 2 rounds). Receive cost per packet (c_net_ns): P0 1052,
P0X 1303, P2 1120, P3 1528, P4 1275 ns. The knee model at 64 B with
low-load costs (P0: c_app 1209 + c_net 1008 ns at 130k): F = 451.0k
vs measured knee 438.6k = 2.8% miss (the raw form passes once the
receive cost is measured honestly). P0X (costs at 390k = 0.48x knee):
1e9/max(c_app,c_net) = 767k vs measured 818k = 6.2% miss. The earlier
(1-h) correction and the metric fix are the same correction: applying
both double-counts (F' = 302k = 31% miss).
**Evidence.** /root/p1/rows-task1b.csv (30 cells); rows:
analysis/rows-fig13-merged.csv; figure: analysis/out/fig3.{png,pdf};
AN-007; p1-LADDER.3. Level H, 3 reps per cell.
**Supersedes:** the numerical basis of C-007's DR-004 wording (h = 0.33
form); the finding itself supersedes nothing.
**Status:** recorded per DR-004 ("whatever it is"); C-007 revision
appended as Pending for the PI.

## p1-LADDER.5 -- the control plane does not stall under 2x-knee receive overload

**Statement.** At 2x the P0 knee (790k pps flood), `ip link add/del`,
`ip netns add/del` and `drop_caches` complete at idle speed: 45/45
runs, flood medians 0.02/0.00/0.09 s against idle medians
0.02/0.00/0.09 s (the one 8.89 s idle outlier is a cold-cache first
run). The pre-registered stall prediction (>1 s per operation) is
falsified on its own rule.
**Evidence.** notes/p1-LADDER-2.md; specs/p1-CTRLSTALL.md v1;
/root/p1/ctrlstall/*.txt. Level H, 5 runs per cell.
**Supersedes:** none (first result on the control path).
**Status:** recorded per DR-004 task 2; no claim (the prediction did
not hold).

## p1-LADDER.6 -- separation helps TCP service, the collapse does not cross it

**Statement.** On memcached -t 1 (32 B values, 90% GETs, open-loop
Poisson from five senders), co-located receive/worker placement loses
to separated at every load above the lightest: at 1.5x the knee, 99.9%
of separated requests meet the 1.05 ms SLO (10x idle p99) against 82.9%
co-located, with p99 645 us against 1475 us; at 2x the knee, delivered
goodput is 369k against 320k QPS (+15%) with p99 1248 us against 1381
us. But the UDP collapse does NOT cross to TCP: at 2x the knee,
delivered goodput holds at 169% (co-located) and 194% (separated) of
the knee goodput -- flow control converts the collapse into a capacity
plateau. The pre-registered low-load cost model misses the TCP knee by
3.1x (predicted 62.0k/82.4k, measured 190k/260k) because per-request
cost falls with load (16.1 us at 20k to 3.3 us at 300k); the >= 5x
wake-delay prediction fails at 1.45x.
**Evidence.** notes/p1-W3.md; specs/p1-W3MEMC.md v1-v3 (pre-registered);
analysis/rows-w3-full.csv (69 rows; 67-130M samples per matrix cell);
AN-008. Level H, 3 reps.
**Supersedes:** none.
**Status:** C-005, C-015 Supported; C-016, C-017, C-018 Refuted on their
own pre-registered rules. Fig. 7 carrier claim stands; the collapse
claim is Dropped from the TCP story per skeleton rule 4 (decision
recorded in the result note).
**Supersedes:** none (first TCP result).
