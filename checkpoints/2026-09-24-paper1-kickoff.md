# CHECKPOINT — Paper 1 (p1-LADDER) kickoff: preflight, instruments, harness
Written: 2026-09-24 02:50 UTC · Experiment davidlin-317389 · repo cloudlab-profile (main)

## Status: rig validated end-to-end; calibration batch (cal-1) in flight
New program of record: **Paper 1 "Separate, Don't Defer"** (PI skeleton,
2026-09-24). Spec: `specs/p1-LADDER.md` v1 (approved with the skeleton).
Everything below is measured on the six-node r6615 Genoa block (rx =
clnode366, tx0-tx4 = 10.10.1.10-14), kernel 6.17.8-061708-generic.

## Verified this session
1. **RSS authoring exact.** Known key set (DPDK reference key via
   `ethtool -X hkey`), identity indirection, wire-order Toeplitz
   (queue = hash & 31). Probe: 3 flows predicted for q7/q1/q29 each
   landed 100,000/100,000 packets on the predicted queue, 0 elsewhere.
   Port table: `k2/porttable-p1.txt` (5 senders, W1 dport 7777 /
   W2 dport 7778, all authored to queue 7).
2. **Placement map.** Target queue 7 = comp7 (IRQ 312) -> cpu 8 (pin_irqs
   convention comp_i -> cpu i+1). App core 8 (NUMA node 1 = NIC node,
   L3 id 4); SMT sibling 40; other core 9 (same CCD). P0X = app on 9.
3. **NAPI thread identity solved.** Threaded NAPI creates
   `napi/enp195s0np0-<napi-id>` kthreads; the queue-7 thread identified
   by schedstat probe (+399 ms / 6592 slices for a 200k-pkt blast =
   ~2 us/pkt NAPI-side, 1300x the runner-up). Fallback map (netlink
   `netdev.h` NETDEV_A_QUEUE_NAPI_ID) available for Fig 9.
4. **Instruments extended** (k2_rx): rx-ts->dequeue latency histogram
   (p50/p90/p99/p99.9/max), SO_RXQ_OVFL socket drops, 1s window rates,
   echo mode (W2 server), self schedstat (app ns/pkt, frequency-proof),
   ref-cycles covariate, --skip warmup, and the SO_RCVTIMEO deadline
   re-check (the old loop blocked forever on an empty socket). k4send:
   --dump raw RTT histogram (merged percentiles across 5 senders).
5. **Harness validated 8/8 gates** (p1cell.sh: conservation, landing,
   floor, generator on W1 and W2 smoke cells). Run manifests written per
   `results/p1-LADDER/<date>/<cell>/rep<k>/manifest.json` (harness-owned).
   Conservation in the W1 smoke is exact: 1,100,000 sent = 1,095,293
   consumed + 4,707 socket drops (start transient; stock 208KB rcvbuf
   kept — uniform across arms). W2 smoke: 30k/30k RPCs, RTT p50 29 us
   (canary >= 10 us passes), server rx->dequeue p50 9.5 us.

## Anomaly class caught before it poisoned data
The clock program's in-flight D2 emitter fleet (12 clockemit on tx1-3, a
second clocksink on tx4) was still running at kickoff: the first landing
probe showed ~150-210k pkts/queue background. Killed all six nodes
clean; probes now exact. Preflight now requires the all-node stray sweep
(the skill's rule; this is its proof case). Harness lesson recorded:
sender-log fetches need retries (throttled ssh drops them silently — the
3-of-5-summaries parse bug found in smoke, now guarded by a
missing-log gate).

## Decisions & rules in force
- Paper 1 skeleton = the contract (per its "How to use this section").
  Spec v1 predictions: P0 < 50% of offered at 2.5x knee; ordering
  P4 > P3 > P2; P4 knee ~= min(f/c_net, f/c_app) ~= 2x P0 knee; low-load
  W2 p99: P0 within 10% of P4, P2 >= 2x P0. Spec v2 will restate
  predictions from measured costs after cal-1 (reason recorded there).
- Placement semantics: IRQ home of the target queue stays cpu 8 in ALL
  arms; the ladder variable = where NAPI processing runs (inline on 8 /
  kthread on 8 / 40 / 9). Documented in the spec.
- No cpufreq driver on this block (SBIOS lacks _CPC): idle states capped
  via /dev/cpu_dma_latency=0 and cycles + ref-cycles recorded per run as
  the frequency covariate. Arms run back-to-back.
- Gates as in the spec; emitter-equivalent pacing gate via k5blast spin
  pacing (achieved rate within 3%, enobufs == 0); pkill -xc only.

## Known gaps / dependencies
- Fig 10 (Intel r650): NOT in this allocation (all six nodes are r6615).
  Needs a second allocation or node swap — flagged to the PI.
- P1 (pre-6.5 kernel) arms: one reboot batch, Ubuntu mainline 6.4.x
  install queued after Figs 1-3 data collection starts (batched per the
  skeleton's rule).
- W1 latency quantization: k2_rx's recvmmsg batch cycle adds ~half-cycle
  to rx->dequeue; fine for SLO-goodput (idle p99 measured with the same
  instrument) — the honest latency story is W2 round trip (Fig 2).

## In flight
- cal-1 (13 short cells): P0 W1 knee sweep 150k-800k pps, placement
  sanity (P2/P3/P4 @ 450k), P0 W2 capacity peek 30k-400k rps. On rx:
  /root/p1/results/cal-1/, batch log /root/p1/batch-cal-1.log.
- Next: c_net/c_app extraction -> knee model -> Fig 1-3 matrix
  (W1 6 arms x 6 loads x 3 reps + W2 low-rate latency arms) -> P1 kernel
  batch -> Fig 4 matrix.

## Data locations
- Harness + kit: cloudlab-profile/{p1/,k2/,specs/p1-LADDER.md}
- Per-run evidence: rx:/root/p1/results/<TAG>/<CELL>/rep<k>/ (manifest,
  consumer, senders, cpu.log 1Hz per-core/per-thread, nic/stat snapshots)
- Raw results stay on rx; derived summaries pulled per milestone.
