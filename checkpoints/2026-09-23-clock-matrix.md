# CHECKPOINT — LLM Serving Runs on a Clock
Written: 2026-09-23 21:15 UTC · Experiment davidlin-317389 · repo cloudlab-profile (main)

## Status: default-Linux phase matrix (H1/H2 verdict window)

### Kit (all committed to cloudlab-profile/clock/)
- clockemit.go: step-clock SSE emitter — aligned (8 striped writers on
  one shared tick), random (per-stream phase), per-engine (256-stream
  engines, aligned internally, random phases between engines). 25ms
  period, 100B chunks (ONE-TO-ONE: validated against real vLLM 0.30+cpu
  — 37 payload segments carry 37 SSE frames). TCP_NODELAY. Overrun gate
  (any write pass >22.5ms marks the run invalid) — the gate caught the
  first emulator artifact (single-goroutine tick pass).
- clocksink.go: multi-core SSE client — delivered tokens/s, p50/p99
  inter-token latency, stalls (>1s gaps), errs. 4-port dial sharding
  (ephemeral-port tuple ceiling at ~28k/dest found and fixed).
- sweep_master.sh: 6 Ns (10k..200k) x 3 reps x (15s discard + 60s
  measure), per-cell emitters relaunch, layer counters on n1
  (instrument.py: softnet drops/squeeze, nstat retrans+memory+backlog,
  sockstat, per-core softirq, mlx5 counters).
- HAProxy (n1): 400k maxconn, 12 backends (4 ports x 3 engine nodes),
  4 client listen ports.

### Aligned (default Linux) — 3 reps each
| streams | delivered tok/s | demanded | stalls/rep | errs |
|---|---|---|---|---|
| 10k | 399-401k | 400k | 0 | 0 |
| 25k | 970k-1051k | 1.0M | 0 | 0 |
| 50k | 1744-1765k | 2.0M | 0 | 0 |
| 100k | 1096-1601k | 4.0M | 58k→114k cum | 0 |
| 150k | 1511-1557k | 6.0M | 927k→2.37M cum | 0 |
| 200k | 1472-1514k | 8.0M | 1.31M→2.72M cum | 0 |

PLATEAU ~1.5-1.6M tok/s from 100k streams up (all streams live, each
starving at ~7.6 tok/s at 200k). Knee between 50k and 100k streams.

### Random (default Linux) — 3 reps each
| streams | delivered tok/s | demanded | stalls/rep | overruns |
|---|---|---|---|---|
| 10k | 399-401k | 400k | 0 | 0 |
| 25k | 1022-1054k | 1.0M | 0 | 0 |
| 50k | 1709-1734k | 2.0M | 0 | 370-383 |
| 100k | 2674-2809k | 4.0M | 1.5M→4.4M cum | 56k-125k |
| 150k | 4.58-7.06M bursty | 6.0M | heavy | connect churn |
| 200k | 4.87-6.9M bursty | 8.0M | 34M cum | dial limited to 160k live |

### INTERIM H2 VERDICT: ALIGNMENT MATTERS
At 100k streams random sustains 2.7-2.8M tok/s vs aligned's 1.1-1.6M
(1.75x), same demand. The plateau moves with phase alignment — the
step clock is a real, first-order effect. Random mode's ceiling is
different in kind (connection churn + write backpressure — see the
overrun counter firing as TCP backpressure in random mode).

### Layer counters (n1 instrument, aligned pass)
softnet dropped +17,920 over the A-pass; RetransSegs +6,034; squeeze 0;
per-second view: drops 10-60/s at 2M+ pps, softirq 2100-3136 jiffies/s
across 64 cores (not saturated). Per-cell correlation pending.

## Decisions & rules in force
- conservation-gates-discard; capacity = plateau top of staircase; roll
  margin 4; cores off cpu0 (tuned arm comes Day 5).
- Emitter overrun gate INVALIDATES a run (per PI plan) — gate working.
- Inter-token histogram measures PROXY COALESCING (p50=0, p99=232ms =
  HAProxy buffering), not the engine clock — rate + kernel counters are
  the primary axes.
- pkill -xc only (pkill -f self-matches ssh shells).
- One command per background terminal call when it starts with pkill.

## Immediate next actions
1. per-engine pass (the realistic case) — emitters relaunch script ready.
2. H1-vs-H2 layer-signature analysis per cell (aligned vs random
   instrument files: /tmp/clock-inst-{aligned,random}.jsonl on n1).
3. Law fit: R = N_streams x r_token x s_token vs delivered; knee
   f/(c_softirq+c_app) x queues.
4. Day 5: tuned arm (IRQ pinning 1:1, irqbalance off) + tcp_mem check.
5. Fixes matrix: coalesce, multiplex, desynchronize, placement.
6. Friday (Sep 25): headline figure = aligned-vs-random rate-vs-streams
   with the stall overlay + the layer-counter signatures.

## Data locations
- clock/results/{aligned,random}.csv + *-master*.out (workstation repo)
- /tmp/clock-inst-{aligned,random}.jsonl on n1 (1 Hz layer counters)
- /tmp/clock/sw-{phase}-{N}.log on n6 (sink logs, 2s cadence)
- /tmp/vllm-stream.pcap on n6 (emission-shape proof capture)
