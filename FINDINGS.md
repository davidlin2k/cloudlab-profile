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
