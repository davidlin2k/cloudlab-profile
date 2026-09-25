# AN-006A -- wedge tracing: the two timelines (DR-004 task 3)

*Filed 2026-09-25 by the agent. Facts only -- interpretation held for
the PI per the run-book ("bring them to me before interpreting
anything"). Source data: /root/p1/wedgetrace/wedge-<arm>-<rep>/
(report.txt, q7-events.txt, counters.log, timeline-*.txt; raw traces
wedge-<arm>-<rep>.dat, CLOCK_MONOTONIC throughout).*

## What ran

Six cells per the run-book, pulled forward from Monday: arms unpin and
ali-P4, three each; 790k pps flood until wedge + 10 s, flood stop,
20 s more, then the 10k pps probe (60 s). Trace-cmd record per the
memo's command line (all four functions verified in /proc/kallsyms on
6.17.8 first; 2 s smoke test rc=0). Counters every second. Cell
wiring verified per cell from affinity-pre.txt: kthread affinity 0-63,
IRQ 312 smp/effective affinity = 8 (unpin arm), the queue-7 kthread
= napi/enp195s0np0-8263 (pid 1594438 after threaded-NAPI re-create).

Wedge outcomes: unpin 3/3 wedged (detector confirmations at +8 to
+16 s of flood; queue-7 silence began 1.5-2 s into the flood --
instant-wedge class). ali-P4 0/3 within the 120 s watch window --
censored; note the watch window here was 120 s vs 195 s in the wdiag
matrix, so the ali-P4 censoring is not directly comparable to the
matrix's 6/8 (its onsets ran to 93 s). Open instrument fact.

## Timeline 1 -- onset (facts only; unpin-1, cell refs in parens for -2/-3)

The healthy queue-7 cycle before the freeze (identical in all cells):

    <idle>/k2_rx [008]  irq_handler_entry: irq=312 mlx5_comp7    (interrupt on CPU 8)
    idle        [013]  sched_wakeup: napi/enp195s0np0-8263 CPU:013
    kthread     [013]  mlx5e_napi_poll -> napi_complete_done -> napi_poll
                        ... work 63 budget 64                    (budget-limited poll)
    kthread     [013]  sched_switch: kthread S ==> swapper/13    (sleeps; next IRQ wakes it)

Last events before the silence (unpin-1: silence starts mono
206308.165295; -2: 206429.887603; -3: 206582.663080):

    206308.164938 [008] irq_handler_entry: irq=312                 (last interrupt)
    206308.164941 [013] sched_wakeup: kthread CPU:013              (last wakeup -- yes, a wakeup was issued)
    206308.164943 [013] mlx5e_napi_poll
    206308.165053 [013] napi_complete_done
    206308.165295 [013] napi_poll ... work 63 budget 64 -> sched_switch kthread S ==> swapper/13
    (nothing further on queue 7 for 18.7 s)

-2 ends identically: last poll work 63 budget 64 at 206429.887601,
kthread to S at 206429.887603. -3 ends identically on CPU 40: last
poll work 63 budget 64 at 206582.663074, kthread to S at
206582.663080.

Kthread state and CPU at the freeze: S (sleeping) after its own
sched_switch; CPU 13 in unpin-1/-2, CPU 40 in unpin-3 (affinity
0-63). The interrupt is on CPU 8 (effective affinity 8); in the
healthy cycles its interrupted context on CPU 8 alternates between
<idle> and the application (k2_rx-1631031). The application thread
sees the interrupt as preemption of its own CPU.

Per-second counters across the silence (unpin-1 samples 206307.27 ->
206308.28, then frozen until the detector at 206316.59): wire
rx_packets_phy +631k/s, rx_out_of_buffer +96.9k/s, rx7_packets
+472k/s in the last alive second then frozen, ch7_poll +7,479/s in
the last alive second then flat, IRQ 312 CPU-8 column +14,592/s
then flat. rx_buff_alloc_err, rx_congst_umr, ch7_force_irq,
ch7_eq_rearm: 0.

## Timeline 2 -- recovery (facts only; unpin-1 refs)

First queue-7 event after the flood stop, in all three cells, is an
INTERRUPT, followed 7-12 us later by the kthread wakeup and the
resumption of the same budget-63 poll cadence:

    unpin-1: stop 206326.59 -> irq312 [008] 206326.852028 (262 ms) -> wakeup [013] +12 us -> poll
    unpin-2: stop 206448.31 -> irq312 [008] 206448.328792 (19 ms)  -> wakeup [013] +12 us -> poll
    unpin-3: stop 206600.33 -> irq312 [008] 206609.256570 (8.9 s)  -> wakeup [040] +7 us  -> poll

    206326.852028 [008] irq_handler_entry: irq=312
    206326.852040 [013] sched_wakeup: kthread CPU:013
    206326.852047 [013] mlx5e_napi_poll -> napi_complete_done -> napi_poll ... work 63 budget 64
    (cadence continues as before the wedge)

The probe (10k pps) starts 20+ s after the flood stop and is not
involved in the first poll. No timer or other wakeup of the kthread
appears before the interrupt: the interrupt is the first queue-7
event of any kind after the silence. The interrupt-to-wakeup gap
(7-12 us) and the poll cost match the pre-wedge cycle exactly.

## Open facts (not explanations)

1. The interval from flood stop to the recovery interrupt varies 19 ms
   / 262 ms / 8.9 s across three identical cells.
2. In the wedged interval the wire keeps arriving (rx_out_of_buffer
   climbing at ~97k/s) but queue 7 generates no completions and no
   interrupts (both flat) while the kthread sleeps.
3. The ali-P4 arm's 0/3 censoring at a 120 s window vs the matrix's
   6/8 at 195 s.
