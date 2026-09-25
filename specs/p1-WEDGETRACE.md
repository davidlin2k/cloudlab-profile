# p1-WEDGETRACE -- wedge tracing (DR-004 task 3)

**Version:** 1 (2026-09-25; frozen before runs. Pulled forward from
Monday on operator instruction.)
**Question.** What exactly happens at the wedge onset, and what
triggers the first poll at recovery? Facts only -- no interpretation
until the timelines reach the PI (DR-004 task 3).

## Design (the memo's, instrumented)

- Arms: unpin (fastest onset) and ali-P4; 3 cells each.
- Per cell: arm wiring per wdiag3 (unpin = threaded=1, kthread 0-63,
  IRQ unchanged; ali-P4 = kthread pinned CPU 9, IRQ 312 affinity 9),
  then flood 790k pps (5 senders x 158k, 64 B) until a wedge is
  detected plus 10 s, stop the flood, keep tracing 20 s, then a 10k
  pps probe for 60 s. Wedge rule: wire (rx7_packets) advancing > 50k
  per 2 s while ch7_poll is flat across 3 samples.
- Trace, one clock (CLOCK_MONOTONIC everywhere: trace-cmd -C mono,
  /proc/uptime in the counter log):
  trace-cmd record -C mono -b 262144 -o wedge-ARM-REP.dat with events
  napi:napi_poll; irq:irq_handler_entry filtered irq==312;
  irq:softirq_entry/exit filtered vec==3; sched:wakeup/switch/
  migrate_task; function trace on mlx5e_napi_poll,
  mlx5e_completion_event, napi_complete_done, __napi_schedule.
  (All four verified present in /proc/kallsyms on 6.17.8 before runs;
  the command smoke-tested for 2 s, rc=0.)
- Counters every second (ethtool -S + /proc/interrupts IRQ 312 line):
  rx_out_of_buffer, rx_buff_alloc_err, rx_congst_umr, ch7_poll,
  ch7_arm, ch7_events, ch7_eq_rearm, ch7_force_irq, all rx7_*
  counters, and ch7_aff_change. Page-pool counters are NOT exposed on
  this kernel/NIC (checked ethtool -S, sysfs, /proc) -- gap recorded.

## Deliverable

Two timelines per the memo, facts only:
1. Onset: everything in the second around the last successful poll,
   including the NAPI kthread's state and CPU, the last interrupt,
   and whether a wakeup was issued.
2. Recovery: the first poll after the flood stops, and exactly what
   preceded it.
Recorded as an AN-006 addendum; brought to the PI before any
interpretation.

## Gates

Traffic gate (wire advancing) before any wedge claim; the trace must
cover the whole episode; counter and trace clocks compared at cell
start/end.
