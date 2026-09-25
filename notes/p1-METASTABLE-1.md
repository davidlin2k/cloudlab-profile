# p1-METASTABLE-1 -- result note: task 1 class (first 5 reps)

Spec: specs/p1-METASTABLE.md (frozen 2026-09-25 before any run).
Cells: p1/metastab.sh, 20 cells (5 per type), interleaved B316, M316,
B158, M158, run 2026-09-25 13:43-14:50Z. Rows:
analysis/rows-metastab.csv (20 rows, built by p1/metastab_eval.py).

## Class (the pre-registered rules applied literally, before any
interpretation -- the memo's order)

**Level 158 (keep .10, 158k pps = 30% of the 525k reference):
Intermediate.** Rule check: "Metastable" needs >=4/5 M not recovered
within 120 s -- 2/5. "Not metastable" needs >=4/5 M recovered within
2 s of the reduction -- 2/5. Neither fires. Per the spec: report the
distribution, run 5 more reps, make no claim.

**Level 316 (keep .10+.11, 316k pps = 60%): Intermediate.** Rule
check: not recovered within 120 s = 3/5 (<4); recovered within 2 s =
0/5 (<4). Neither fires. Same disposition.

B cells: 5/5 healthy at both levels (all recovered at the kept rate
within 2.2 s of REDUCE, all probes full delivery) -- the M results are
interpretable (no level is Invalid).

## Distribution (facts only)

Level 158, M cells (recovery time from REDUCE, offline from
counters.log; the verdict window is 120 s):

| cell | recovered <=120 s | t_recover_s | probe |
| --- | --- | --- | --- |
| M1-1 | Y | 1.5 | PROBE-OK (300,099) |
| M1-2 | N | -- | PROBE-DEAD (needed reset) |
| M1-3 | Y | 1.1 | PROBE-OK |
| M1-4 | N (late: recovered after the window, before the probe) | -- | PROBE-OK (needed reset) |
| M1-5 | Y | 10.5 | PROBE-OK |

Level 316, M cells:

| cell | recovered <=120 s | t_recover_s | probe |
| --- | --- | --- | --- |
| M2-1 | N | -- | PROBE-DEAD (needed reset; the smoke cell) |
| M2-2 | Y | 3.0 | PROBE-OK |
| M2-3 | N | -- | PROBE-DEAD (needed reset) |
| M2-4 | N (late) | -- | PROBE-OK (needed reset) |
| M2-5 | Y | 2.9 | PROBE-OK |

M-cell outcome types seen: fast recovery (1-3 s: 5 cells), slow
recovery (10.5 s: 1 cell), late recovery past the 120 s window but
before the probe (2 cells), dead through the probe (2 cells).

## Resets (memo item 2, reported immediately)

5 of 5 unrecovered M cells ended in a state that needed the DR-005
step 4 recovery before the next cell (M1-2, M1-4, M2-1, M2-3, M2-4;
logs in each cell's step4-reset.log). The M2-1 queue additionally
survived the prescribed resets (threaded 0->1 toggle; `ethtool -L
combined 32` + full pre-flight) with the wire provably alive
(+790,177 rx_packets_phy in one probe window, delivered to no queue),
and revived only after a genuine channel recreation (32->16->32) +
pre-flight (probe 80,067). Facts logged; this triggers the memo's
"stop and tell me before drafting" clause for task 5.

## Instrument facts (recorded, not interpreted)

- `devlink health diagnose pci/0000:c3:00.0 reporter rx` (and `show`,
  `dump show`) return "kernel answers: Invalid argument" on this
  platform; the fw reporter's diagnose works ("Syndrome: 0"), so the
  documented syntax is right and the kernel's rx handler refuses.
  The rx reporter name exists in `devlink health`.
- debugfs /sys/kernel/debug/mlx5/.../CQs/<cqn>/ exposes only
  log_page_size, num_cqes, pid -- no producer/consumer indices.
- rx7_packets does not zero across channel recreation.

## Next (the pre-registered rule)

The 5 more reps are running (batch 2, reps 6-10 of all four cell
types, 2026-09-25). No claim is made at either level until the
combined distribution is reported. No interpretation accompanies this
note.
