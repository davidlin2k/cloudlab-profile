# p2-RXFUZZ -- rxfuzz v0 design note (DR-005 task 6)

**Version:** 1 (2026-09-25; the memo's fixed choices, due Monday
October 5 and written early). Implementation Tuesday-Thursday; first
overnight run Thursday night; results in Friday's memo.

## Configuration dimensions (the memo's, fixed)

| Dimension | Values |
| --- | --- |
| threaded | 0, 1 |
| NAPI thread placement | the IRQ's CPU, its SMT sibling, another core in the same L3 domain, another L3 domain, unpinned |
| adaptive-rx | on, off |
| receive ring | default, 8192; set between cells only |
| striding receive queue | on, off; set between cells only |
| GRO | on, off |
| `busy_read` sysctl | 0, 50 |
| per-device `napi_defer_hard_irqs` | 0, 2 |
| per-device `gro_flush_timeout` (ns) | 0, 200000 |

Reference rate = 525k pps (the Fig. 1 contract knee). Configurations
are sampled uniformly at random per cell; every cell's sampled
configuration is logged before its run.

## Load schedules (the memo's, fixed)

1. Ramp from 0.3 to 1.5x the reference over 60 s.
2. Flood at 1.5x for 60 s, then drop to 0.6x for 120 s.
3. Five cycles of 20 s at 1.5x and 20 s at 0.3x.
4. A steady 0.9x.

## Perturbations (the memo's, fixed)

Once per cell, during load, one of:
- toggle threaded 1 -> 0 -> 1;
- move the NAPI thread's affinity;
- move IRQ 312's affinity;
- change `ethtool -C` moderation.

Never change channels or rings mid-cell.

## Oracles (the memo's conditions; windows fixed here)

Evaluated from the 1 Hz counter log (`rx7_packets`,
`rx_out_of_buffer`, plus the offered rate from the schedule):

| Oracle | Condition |
| --- | --- |
| STALL | rx7_packets flat (zero delta) for >= 6 s while rx_out_of_buffer rises each of those samples |
| METASTABLE | A STALL still holding >= 60 s after the load drops to <= 0.6x the reference |
| COLLAPSE | Delivered rate < 0.5 x min(offered, reference) for >= 10 consecutive 1 s samples |
| PERMANENT | The 10k pps probe (30 s, as in task 1) advances rx7 < 270000, 30 s after all load stops |

## Budget and output (the memo's)

- Cells last 5 minutes; about 96 per night, randomly sampled.
- Every hit saves its configuration, schedule, counters and `dmesg`,
  plus a 10 s trace for the first hit of each class.
- Output: `results/p2-RXFUZZ/<date>/<cell>/` and `hits.csv`
  (columns: date, cell, oracle, dimensions..., schedule, onset_s,
  recovered, reset_needed).

## Minimization (the memo's)

For each hit: reset one dimension at a time to its default and rerun.
Keep only the dimensions whose reset removes the hit. Confirm the
minimal configuration 3 times.

## Discipline

Every new script gets a short smoke run before any batch (DR-005
rules). One cell at a time on the wire; between cells the task 1
step 4 recovery runs when the previous cell ends PERMANENT (logged in
the cell's directory). The second-driver node list is
notes/p2-CLNODES.md (done 2026-09-25: c6620/d760 ice, c6420/c4130
i40e, d6515/d750/rs440 bnxt).
