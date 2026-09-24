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

### ~~INTERIM H2 VERDICT~~ RETRACTED (PI review, 2026-09-23 21:40 UTC)
The 1.75x at 100k came from random-mode runs the overrun gate itself
invalidates (56-125k overruns). The only clean comparison (50k) shows
NO alignment effect (aligned 1.74-1.77M vs random 1.71-1.73M). Higher
rate with 13-40x more stalls is bursty catch-up, not better service.
CONFOUNDS TO RESOLVE BEFORE ANY VERDICT:
(1) Emission-policy confound: aligned striped-writers vs random
    per-stream writers differ in backpressure handling - the modes must
    share ONE emitter, ONE queue policy, ONE writer pool.
(2) Silent tick-dropping found in the aligned path: time.Ticker's
    1-capacity channel drops ticks when writers block - "zero overruns
    while delivering 1.5M of 8M demanded" is the emitter skipping steps,
    the overrun gate cannot see it.
(3) Achieved alignment unmeasured: at high N the write pass spreads the
    burst across the step; verify packets-per-100us at the proxy NIC.
(4) The kernel is NOT the limiter at this scale: softnet drops 0.002%,
    squeeze 0, retrans +6k total, softirq 2.1-3.1k jiffies/s on 64
    cores. H1 unsupported yet. The 1.5M tok/s plateau with low proxy
    CPU points at user space (HAProxy event loop, emitters, or sinks).
    ExaServe's retrans explosion NOT reproduced (fan-in 3 vs 128). PI
    verdict: no claim until per-hop accounting + bypass test locate
    the limiter.

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

## Rig fixes after PI review (2026-09-23 22:00 UTC)
- clockemit v3 = ONE emitter, THREE schedules per PI spec C: 1ms-slot
  wheel (aligned=slot 0, random=uniform, per-engine=engine slot), per-
  stream queue depth 4 with DROP-OLDEST + drops counter (backpressure
  is measured, never silent), one handler goroutine per stream draining
  its queue. Gate: drops>0.1% OR slot_overruns>0 OR CPU>90% of cores;
  slow_writes>1ms counted. V2's silent tick-dropping (time.Ticker cap-1
  channel) is gone by construction (wheel never skips a slot).
- clocksink: multi-endpoint mode for the bypass test (comma-separated
  host:port list).
- HAProxy: stats socket /run/haproxy/admin.sock (bin/bout/scur per
  section, Run_queue) + pidstat -t per-thread CPU.

## PI run spec A-D (plan of record)
A. Per-hop accounting at 50k/150k aligned: emitter writes/s + drops +
   slow_writes + CPU; HAProxy bin/bout per section + per-thread CPU +
   run queue; sink rate + CPU. Conservation at each hop: the hop where
   the rate drops is the bottleneck. (IN FLIGHT: ab_runs.sh)
B. Bypass: sink -> emitters directly. Plateau vanishes = HAProxy is
   the limit; plateau stays = endpoints, fix the rig first. (IN FLIGHT)
C. Unified emitter + achieved-alignment measurement: packets per 100us
   at the proxy NIC (12s hw-timestamped capture per cell in ab_runs).
D. Rerun phase matrix 25k/50k/75k/100k x 3 modes x 3 reps, new gates
   only; report rate + stall-seconds per stream. (after A-C)
Fan-in follow-up (after limiter found): more source IPs / backend
ports / fewer proxy queues to test the retransmission explosion.
Friday figure: aligned plateau + per-hop accounting + bypass result
(no phase-effect claim until D passes with the unified emitter).

## Findings 2026-09-23 late (A/B with unified emitter v3, full 12-fleet)
A(50k, aligned, through HAProxy): emit 1.877M tok/s -> receive 1.879M
  (conservation 1.001); emitter drops=0, slow_writes=0, ~3% of a core;
  HAProxy pidstat = 1,324% CPU (13.2 cores!) at 1.88M tok/s with
  worker threads ~85% each; kernel counters quiet.
B(50k, bypass, sink->emitters direct): 1.847M tok/s - the ~1.85M
  ceiling STAYS without the proxy. Per the decision table: the limit
  is in the endpoints, not HAProxy. (HAProxy's 13-core per-token tax
  would be the NEXT ceiling above this.)
THE ENDPOINT CEILING IS THE TIMER: direct probe at 150k (12.5k
  streams/emitter) over 10s: steps +290 = 29.0 steps/s vs the
  intended 40.0, and tok/s per stream = 29.0 = exactly the step rate.
  The Go 1ms ticker's cap-1 channel silently DROPS ticks when the
  scheduler delivers late at 12.5k+ goroutines/process. Same drop
  class as v2's shared ticker, one level down. FIX BUILT: absolute-
  deadline loop (time.Sleep to t0+k*1ms; late passes execute late,
  never skipped; slot_overruns now measures lateness >500us as a
  SIGNAL per spec C). Also: aligned mode skips the map walk on the 24
  empty slots (96% less scheduler work).
Bypass ITL signature: p50=26ms (the raw step clock) vs proxy p50=0
  coalesced / p99 232ms (HAProxy batching) - the proxy's automatic
  coalescing is directly visible (PI point 5 confirmed).

## Achieved-alignment measurement (PI point 3) — THE SMEAR (2026-09-24 00:40 UTC)
burst_analyze on the proxy-NIC captures (A/B run):
- 50k "aligned": fraction of each 25ms step's packets in its first
  1ms = p50 0.042 (random-phase baseline = 0.040). peakedness 1.5.
- 150k "aligned": p50 0.040. peakedness 1.6.
THE STEP IS ALREADY A SMEAR AT THE WIRE. One-token-one-segment at
50k streams = 25k write() syscalls per 1ms slot = the write path
serializes the "burst" across ~the whole step regardless of phase.
Achieved wire alignment ~uniform at both scales.
Consequences:
(1) The aligned-vs-random contrast at 50k+ is NULL BY CONSTRUCTION -
    any D-matrix null result must be reported WITH the per-cell
    achieved-alignment measure as the explanation.
(2) Wire-level incast requires the fix set: per-step coalesce +
    MULTIPLEX (one connection carrying all streams' frames in one
    write per step is the only way a step fits in <1ms). The blue-
    print's fix #1 is not an optimization, it is the ENABLER of a
    burst at all. Desynchronization acts at the enqueue level.
(3) Segmentation ratio is load-dependent: vLLM at low rate = 1
    segment/frame (validated); at 1.9M tok/s the capture shows
    ~1.16M segs/s carrying 1.88M frames/s = 1.6 frames/segment
    (sender-side batching). "One token one segment" holds only at
    low rates.
(4) What the clock DOES produce at the wire: a 25ms sawtooth arrival
    process (phase-locked rate waves) even when smeared - the host's
    "smooth independent arrivals" assumption is still violated, but
    as periodic rate modulation, not as instant incast. This reframes
    the mechanism and must be stated as measured.

## Data locations
- clock/results/{aligned,random}.csv + *-master*.out (workstation repo)
- /tmp/clock-inst-{aligned,random}.jsonl on n1 (1 Hz layer counters)
- /tmp/clock/sw-{phase}-{N}.log on n6 (sink logs, 2s cadence)
- /tmp/vllm-stream.pcap on n6 (emission-shape proof capture)

## D matrix, first pass (2026-09-24 02:00 UTC) — INTERIM (see AN-002)
Unified emitter v3 + absolute-deadline wheel, 3 modes x 25k/50k/75k/
100k x 3 reps, medians over reps (1s-window rate field — inflated by
backlog catch-up; superseded by the tokens-diff rerun in flight):
| streams | aligned | random | per-engine | offered |
|---|---|---|---|---|
| 25k | 1.000M | 0.999M | 0.998M | 1.00M |
| 50k | 2.001M | 1.992M | 2.032M | 2.00M |
| 75k | 2.988M | 3.013M | 3.005M | 3.00M |
| 100k | 3.471M* | 3.983M | 4.019M | 4.00M |
All rows pass the emitter gates (drops ~0). *aligned 100k carries one
frozen rep and one 2.97M outlier. READING: with the timer fixed there
is NO plateau and NO phase effect at 25k-75k (100% of demand in every
mode); at 100k the 87%-vs-100% gap rests on one bad rep. Combined
with the measured wire smear (achieved alignment ~uniform), the honest
pre-rerun reading is: no detectable phase effect at the wire at these
scales. AN-001 supersedes the old plateau numbers; AN-002 supersedes
these rate values.

Record system adopted (lab handbook): cloudlab-profile/ now carries
specs/ notes/ anomalies/ decisions/ reports/weekly/ CLAIMS.md and the
append-only FINDINGS.md; AN-001 and AN-002 filed. Raw pcaps stay on
disk (5.6GB) and out of git.

Next: D2 tokens-diff rerun (in flight) -> spot burst captures per
cell for the achieved-alignment covariate -> fan-in escalation for
the retransmission signature -> coalesce+multiplex emitter (the
enabler of real wire bursts).
