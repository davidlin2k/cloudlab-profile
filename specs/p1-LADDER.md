# p1-LADDER: Receive overload protection by predictive NAPI placement
Owner: student · Approved by PI: 2026-09-24 (skeleton issued with the run order) · Status: running · Version: 1

## Question
Under receive overload, does separating NAPI processing from the application
core (threaded NAPI on the SMT sibling, then on another core) protect
application goodput without the low-load latency cost of same-core deferral —
and is each placement's collapse knee predictable from measured per-packet
costs?

## Hypothesis and prediction
- Hypothesis: inline softirq (6.5+ default) co-locates network processing
  with the application and collapses past a knee; same-core deferral
  (ksoftirqd / threaded NAPI on the same core) protects progress but caps
  near half a core and taxes latency; separating the two onto sibling /
  other core drains more, and each placement's knee follows from two
  measured per-packet costs (c_net, c_app) plus the SMT slowdown.
- Prediction, with numbers:
  1. At 2.5x the inline knee (plen 64, W1): P0 goodput < 50% of offered;
     P2 (same-core thread) 50-65% (CFS split); P3 (sibling) > P2;
     P4 (other core) >= 90% of offered (predicted knee ratio
     min(f/c_net, f/c_app) / (f/(c_net+c_app)) ~= 2 when c_net ~= c_app).
  2. Low load (0.25x knee, W2 round trip): P0 p99 within 10% of the
     P4 p99 (inline is the latency floor); P2 p99 >= 2x P0 (same-core
     deferral is the latency cost); P3 between.
  3. Model (form F, two-worker queue per placement): knee_pred =
     1e9/(c_app+c_net) (P0/P2, one logical CPU serializes the two
     workers), (2/s)*1e9/(c_app+c_net) (P3, both workers on one
     physical core; s = SMT slowdown factor, m = 2/s capacity factor),
     1e9/max(c_app,c_net) (P4) within +/-25% of measured knee across
     plen 64/512/1400 (Fig 4). Per-packet costs are the placement's
     own in-situ measurements (ns/packet); form F is falsified if a
     predicted knee misses measured by >25% -- claim Dropped per the
     skeleton contract, not re-fit after the fact.

- Calibration anchors (cal-1 + calsmt, 2026-09-24, plen 64): knee(P0)
  ~= 525k pps (100% delivery at 450k, 57% at 600k) anchors the load
  grid (130k..1300k pps = 0.25..2.5x knee). Costs at 450k pps:
  P0 c_app=1060 c_net=517 ns (form F predicts 634k); P2 983/877;
  P3 1456/1383 in-situ; P4 1133/1138 (predicts 880k). SMT factor
  s = 1.24 (cyc/pkt 220.8->275.0 with the sibling burning; the p2
  pair agrees at 1.24). Sanity already visible at 450k: rx->dequeue
  p50 = 264 us (P0) vs 254 us (P2) vs 15.5 us (P3) vs 12.5 us (P4).
  Spec version note: v2 (2026-09-24 03:15Z) adds the calibration
  anchors and the explicit model form (reason: measured costs existed
  only after cal-1). fig1-3 runs started 03:04Z under v1; their
  prediction check uses the v1 numbers above (unchanged in substance).
- Builds on: K2AGG (five-sender port-authored incast rig), K3LOAD,
  K5CAP (k5blast spin pacing), K4PART/AN-001 (timer/gate discipline),
  Mogul & Ramakrishnan TOCS'97 (livelock), the 2016 deferral + 2023
  revert (LWN 698807 / lkml 2305.1:02264), threaded NAPI (LWN 833221,
  per-NAPI netdev 2025-02), Cai et al. SIGCOMM'21, Hanford et al. NDM'13.

## Setup
- Nodes and roles: rx = clnode366 (10.10.1.1, machine under test);
  tx0-tx4 = 10.10.1.10-14 (clnode366 block davidlin-317389; five
  spin-paced senders). All orchestration node-to-node over 10.10.1.x.
- Kernel, NIC firmware, key settings: rx on 6.17.8-061708-generic
  (P0 inline default; P2-P4/P7 via threaded NAPI); P1 = Ubuntu mainline
  pre-6.5 (6.4.x, ksoftirqd deferral) in one reboot batch per figure
  group. CX-6 fw 20.43.3608, enp195s0np0 (PCI c3:00.0, NUMA node 1),
  32 channels (max 63), identity indirection, RSS key = DPDK reference
  key (set via ethtool -X hkey; Toeplitz over the wire-order 4-tuple,
  queue = hash & 31 — predicts the map exactly).
- Placement map (pin_irqs convention comp_i -> cpu i+1): target queue 7
  (comp7, IRQ 312 -> cpu 8). App core = 8 (NUMA node 1, L3 id 4);
  SMT sibling = 40; other core = 9 (same CCD/L3). P0X = app on cpu 9,
  IRQ home unchanged. cpu0/32 reserved housekeeping; irqbalance off;
  /dev/cpu_dma_latency = 0 held open during runs.
- Known gap: no cpufreq driver (SBIOS lacks _CPC; amd_pstate fails to
  init) — frequency is hardware-managed. Control: cpu_dma_latency=0,
  record cycles + ref-cycles per packet in every run as the frequency
  covariate, all compared arms run back-to-back.
- Software and versions: k2_rx (W1 consumer / W2 echo server, extended:
  kernel rx-ts latency histogram, SO_RXQ_OVFL, windowed rates), k5blast
  (spin-paced flood), k4send (W2 paced RPC client, RTT histogram, <10us
  floor canary), clock/instrument.py lineage sampler (per-core and
  per-thread CPU, softnet, ethtool -S, sockstat). memcached + mutilate
  for W3/W4 (Figs 7-8) installed before those cells.

## Design
| Factor | Levels |
| --- | --- |
| Workload | W1 flood (5 senders, port-authored to queue 7, k2_rx) |
| | W2 req/resp low rate+load (k4send -> k2_rx --echo) |
| Policy | P0 inline; P0X app elsewhere; P1 pre-6.5 ksoftirqd deferral |
| | P2 thread on app core; P3 thread on sibling 40; P4 thread on core 9 |
| Load | 0.25, 0.75, 1.0, 1.5, 2.0, 2.5 x knee (knee = P0 W1 plen-64) |
| Packet size | 64 (Figs 1-3), 64/512/1400 (Fig 4) |
Reps per cell: 3 (5 for final decisive cells) · Run length: 90 s
(10 s warm-up discarded, 60 s measure) · Warm-up discarded: 10 s.

## Metrics
Primary: application goodput (consumed pkts/s or RPC/s); goodput under
SLO (SLO = 10x the idle p99 of that workload's latency instrument).
Secondary: p50/p99/p99.9 latency (W1: kernel rx-ts -> dequeue, k2_rx;
W2: client round trip, k4send), rung switches/s (P7).
Counters logged: drops at every layer (NIC ring / softnet / socket
SO_RXQ_OVFL), CPU ns per packet by core (/proc/stat) and by thread
(app, ksoftirqd/NAPI kthread via schedstat), cycles + ref-cycles per
packet (k2_rx self-perf), achieved offered rate + enobufs per sender.

## Gates
Conservation: sent == consumed + socket drops + censored (tail), and
consumed + drops == queue-7 counter delta (+/-0.5%) — discard otherwise.
Landing: queue 7 purity >= 97% of queue-side counter deltas.
Physical floor: W2 RTT p50 >= 10us (k4send canary), W1 rx->dequeue
p50 >= 1us (k3mot GATEWARN class) — abort and file an anomaly otherwise.
Generator: achieved rate within 3% of target, enobufs == 0, sender
status line from THIS run's log only.
Experiment-specific: emitter-equivalent scheduler gate (k5blast spin
pacing on-time), idle p99 re-measured per session for the SLO.

## Outcomes
- Pass if: prediction 1 holds at 2.5x for P0/P2/P4 and prediction 3
  holds within +/-25% (Fig 4 cells) — claim "separate, don't defer"
  stands with the model as the predictor.
- Kill if: P4 does not drain > 1.5x P0 goodput at 2.5x knee (the
  separation lever is worthless on this hardware) — record decision,
  change the claim list, do not bend the story.
- Ambiguous if: prediction 2 fails while 1/3 hold (latency cost story
  only) -> next step: busy-poll and IRQ-suspension controls in the
  W2 arms before any latency claim.

## Confounds controlled
Kernel policy (version recorded per run) · idle states
(/dev/cpu_dma_latency=0) · frequency (no driver: cyc/ref-cyc covariate,
back-to-back arms) · SMT (pinned map; P3 explicitly on sibling) ·
NUMA (all placement cores on node 1 = NIC node) · IRQ map (pin_irqs
table, verified per session) · RSS key (set known key per session) ·
irqbalance (stopped+disabled) · GRO (recorded; unchanged across arms) ·
moderation (recorded; unchanged) · generator capacity (spin pacing,
5 senders, per-sender < 35% of one core).

## W3/W4 arms (spec v3, 2026-09-24 — added before any W3 cell ran;
reason: pin the baseline definitions the skeleton names but does not
define, grounded in their source papers)

W3 = memcached under mutilate, TCP, open-loop, 90% GETs, 32-byte
values (skeleton). Grounding and knobs:
- mutilate (leverich/mutilate): agents -T 16 -A on tx0-3, master on
  tx4; open-loop latency via --measure_depth + --measure_qps (master
  samples at a constant slow rate while agents carry load). 90% GETs =
  -u 0.1111 (set:get = 1:9), -V 32 values, -K 32 keys, -r 100000
  records. Build: scons + libevent-dev + gengetopt + libzmq-dev.
- Receive steering invariant: one ntuple rule sends ALL tcp/11211 to
  queue 7 (ethtool -N flow-type tcp4 dst-port 11211 action 7), so W3
  exercises the SAME instrumented queue as W1/W2 under every policy.
  This also answers mutilate's ephemeral-port limitation (connections
  would otherwise hash across queues).
- App = memcached -t 1 pinned to the policy's app_cpu: one server
  thread keeps c_app (W3's per-op cost, measured at low load) a
  property of the policy, exactly as in the W1/W2 model. The Fig 7
  prediction then reuses form F with W3-measured costs.

P5 (IRQ suspension) = Damato/Karsten "Suspend IRQs during application
busy periods" (net-next 2024, patchew 20241103052421 v5..v9): set
napi_defer_hard_irqs=100, gro_flush_timeout=200us, irq_suspend_timeout
large (their recipe: 20s) via netdev-genl, and the app sets
prefer_busy_poll on its epoll context (EPIOCSPARAMS) with
busy_poll_usecs=0, budget=64. It REQUIRES an app-side epoll ioctl, as
the related-work sentence says. Verification needed at first quiet
window: irq_suspend_timeout availability on 6.17.8 (netdev-genl family
present?) and the memcached/libevent epoll path (shim or 10-line patch
to issue EPIOCSPARAMS; the series' own evaluation modified memcached's
epoll_wait path).
P6 (busy polling) = the series' "fullbusy" baseline: prefer_busy_poll +
busy_poll_usecs=1000, budget=64, defer_hard_irqs=100,
gro_flush_timeout=5s, and a 1ms epoll timeout in the app.

Both P5 and P6 are applied to the SAME consumer app as the other arms
(k2_rx --echo for W2; memcached path for W3) so arms differ only in the
placement/mode variable (evidence-standards: one implementation).
p1pol.sh gains P5/P6 cases AFTER chain6 exits (never edit a script a
running driver execs, even fresh per cell -- the exec window races the
write).

## Budget
Runs: ~230 for Figs 1-3 + Fig 4 knee cells (of the skeleton's ~870
total incl. Figs 5-10 and final reps) · Machine hours: ~6 h phase 1
(90 s/run) · Calendar days: phase 1 = 1 day (P1 batched in one reboot
cycle) · Nodes: 6.
