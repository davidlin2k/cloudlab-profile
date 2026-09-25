# 2026-09-25 -- DR-004 task 1: the utilization metric is fixed at the source
**Date:** 2026-09-25 04:1xZ
**Scope:** DR-004 task 1 (metric fix), steps 1-2 complete; step 3
(recompute Figure 3 + per-packet costs + knee model) runs on the
task1b data landing ~04:45Z.

## What was found (AN-007, FINDINGS p1-LADDER.3)
- /proc/stat's cpu8 line charges CPU 8's receive bursts to idle on this
  kernel: P0X 390k -- PMU 36.53 s vs stat 0.22 s (166x).
- Kernel facts: CONFIG_IRQ_TIME_ACCOUNTING is not set, NO_HZ_FULL=y,
  HZ=1000. Sub-tick IRQ-context bursts on an idle CPU land in the idle
  bucket; ticks rarely land inside a burst.
- p1_analyze's softirq_s read steal (d[7]) instead of softirq (d[6]) --
  the cal-1 anchor's phantom "hidden share".
- First PMU bracket spanned 73 s against the consumer's 63 s mpkts
  window (16% overcount); task1b uses the aligned bracket.

## What changed
- p1cell.sh: every cell brackets perf stat -A -a -C 8,9,40
  -e cycles,ref-cycles over the consumer's window.
- p1_analyze.py: cpuN_busy_s = ref-cycles / TSC 3.250 GHz (calibrated);
  the /proc/stat sum kept as cpu8_busy_stat_s; per-field stat seconds
  (user/nice/system/irq/softirq/steal) stored per row; softirq index
  fixed.
- C-014 -> Supported (PI's DR-004 instruction); FINDINGS p1-LADDER.3;
  the lab handbook confound list gained "softirq execution context".

## Next actions
1. task1b data -> Figure 3 recompute, per-packet costs, knee model miss.
2. DR-004 task 2 (control-plane stall test) with pre-registration.
3. Friday memo by noon (figure of the week: the wedge survival curves).
