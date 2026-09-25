# Spec p1-METASTABLE: the metastability test

Frozen 2026-09-25 (UTC), BEFORE any run, per DR-005 task 1 step 1 and
the handbook ("spec before runs"). A spec change after runs start is a
new version. All definitions below are DR-005's fixed definitions,
carried verbatim.

## Question (DR-005)

After a wedge begins, does the queue stay dead when the offered load
falls to a level it normally handles?

## Fixed definitions (DR-005, verbatim)

| Item | Value |
| --- | --- |
| Arm | `unpin`, wired exactly as `wdiagtrace.sh` does it: threaded=1, every `napi/enp195s0np0-*` kthread at affinity 0-63, IRQ 312 -> CPU 8, `k2_rx --port 7777 --core 8` |
| Flood | 5 senders x 158k packets/s = 790k (hosts 10.10.1.10-14, the existing source ports) |
| Reference capacity | 525k packets/s, the "1.0x knee" of the Fig. 1 contract |
| Reduced levels | **M158**: keep sender .10 only (158k, 30% of reference). **M316**: keep senders .10 and .11 (316k, 60%) |
| Baselines | **B158** and **B316**: the same kept senders for 120 s with no flood beforehand, same wiring |
| Wedge detector | Unchanged from `wdiagtrace.sh`: `rx7_packets` flat, and `rx_out_of_buffer` rising more than 50k per 2 s, for 3 consecutive 2 s samples |
| Recovered | `rx7_packets` advancing at >=90% of the kept offered rate for 3 consecutive 2 s samples. Recovery time = the start of the first of those samples, computed offline from `counters.log` |
| Reps | 5 per cell type (M158, M316, B158, B316) |

## Pre-registered outcome classes, per reduced level (DR-005, verbatim)

| Class | Rule |
| --- | --- |
| **Metastable** | At least 4 of 5 M cells not recovered within 120 s, and the matching B cells healthy in 5 of 5 |
| **Not metastable** | At least 4 of 5 M cells recover within 2 s of the reduction |
| **Intermediate** | Anything else. Report the distribution; run 5 more reps; make no claim |
| **Invalid** | Any B cell wedges. The M result at that level can't be interpreted; use the other level |

## Implementation and run protocol (DR-005 steps 2-5)

- Script: `p1/metastab.sh`, a copy of `p1/wdiagtrace.sh` with exactly the
  changes in DR-005 step 2 (MODE/KEEP/REP args; unpin wiring only;
  trace-cmd off by default with TRACE=1; 400 s senders and consumer;
  mode B = kept senders + the monitor with no flood and no wedge
  detection; mode M = WEDGE, hold 10 s, kill non-KEEP senders, log
  REDUCE, then the monitor; the monitor block is DR-005's verbatim;
  then the 10k/30 s probe with PROBE-OK at >=270,000 rx7 advance; the
  mechanism snapshot for M316 rep 1 only, 30 s after REDUCE).
- Rules in force: every new script gets a short smoke run before any
  batch; every script is committed before it runs.
- Smoke: one M316 cell and one B316 cell. Each must create cell.env, a
  counters.log at 1 Hz, and exactly one verdict line.
- Batch order: B316, M316, B158, M158, repeated for 5 rounds.
- Step 4 (if a queue stays dead after the probe): stop all senders;
  echo 0 > /sys/class/net/enp195s0np0/threaded, wait 5 s, echo 1; if
  still dead, `ethtool -L enp195s0np0 combined 32` and the full
  pre-flight (RSS key, port map, IRQ re-pin, rediscover the queue-7
  NAPI thread). Log every reset in the cell's directory. A cell that
  needed a reset still counts; its verdict is PROBE-DEAD.
- Step 5 records: analysis/rows-metastab.csv (cell, rep, mode, keep,
  t_flood, t_wedge, t_reduce, recovered, t_recover_s, rx7_rate_reduced,
  oob_rate_reduced, probe); p1/metastab_eval.py printing the
  pre-registered class per level; a result note, a FINDINGS entry, an
  AN-006 addendum. The class is reported to the PI before any
  interpretation (facts only until then).
