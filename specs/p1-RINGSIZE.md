# p1-RINGSIZE -- receive ring size A/B (DR-005 task 4)

**Version:** 1 (2026-09-25; frozen before any run.)
**Question.** Is ring starvation necessary for the wedge? (DR-005
task 4, "Receive ring size".)

## Design (the memo's, with fixed definitions)

- 8 cells at the default ring size vs 8 cells at
  `ethtool -G enp195s0np0 rx 8192`, in the `unpin` arm with the task 1
  flood (5 senders x 158k = 790k pps, 64 B, sources .10-.14, existing
  source ports; `k2_rx --port 7777 --core 8`).
- Pre-flight before the batch: `ethtool -g` maximum recorded (if 8192
  exceeds it, use the maximum and supersede this spec's label).
- Cell = one flood until the task 1 wedge detector fires (rx7_packets
  flat AND rx_out_of_buffer rising > 50k per 2 s, 3 consecutive 2 s
  samples) or 120 s without it (NO-WEDGE). A cell counts as wedged iff
  WEDGE fires.
- After every ring change: the full pre-flight (RSS key, port map,
  IRQ 312 -> CPU 8 re-pin), and rediscover the queue-7 NAPI thread
  (5 s flood at 158k; the `napi/enp195s0np0-*` thread whose
  /proc/<pid>/stat utime+stime grows most). No script hard-codes the
  thread's numeric suffix.
- Between cells, the DR-005 step 4 recovery runs if the previous cell
  ended PROBE-DEAD/NOT-RECOVERED (logged in the cell's directory).

## Prediction (the memo's, verbatim)

"If ring starvation is necessary, the wedge rate falls at least 4x
with the larger ring."

## Outcome classes (pre-registered)

- **Prediction holds:** default-size wedge rate >= 4x the 8192 rate
  (with 8 cells/arm: e.g. 8/8 vs <=2/8).
- **Prediction fails:** the rate ratio is < 4x (including no
  difference). Ring starvation is not necessary at this scale.
- **Invalid:** any cell fails the wire gate (the flood's packets not
  arriving at the PHY) or the environment needed a reset at cell start
  and the post-reset probe delivered < 90% of 10k pps. Invalid cells
  are re-run and reported.
Report x/8 per arm with the exact 95% binomial interval.
