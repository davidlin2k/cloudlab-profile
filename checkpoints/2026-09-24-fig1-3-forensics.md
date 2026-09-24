# 2026-09-24 — fig1-3 forensics, AN-003 wedge, re-run launched

Status: Figs 1–3 in analysis. One full 105-cell matrix run (fig1-3),
decoded to 99 rows; three anomaly classes found and closed or recorded;
clean re-run (fig1-3b, 72 cells) + wedge-condition matrix (wedge-m, 24
cells) running on rx as chain2 (started 07:00Z, done ~09:16Z).

## What is settled today

1. Landing and rig are exact: port-authored Toeplitz map lands 100,000/
   100,000 on queues 7/1/29, zero elsewhere (lp.sh); senders pace within
   0.01% of target with enobufs=0; per-hop conservation closes at low
   and mid load (P0: 9,221,392 / 9,230,000 at 130k).
2. The "46% delivery" anomaly (P0X/P2/P3/P4 at 130–525k) is NOT physics:
   it is SO_REUSEPORT flow-splitting with a straggler consumer from the
   previous cell. Exact 2/5 quantization in P0X rep1 (3,686,241/9,230,000
   with the wire carrying 9,230,028 and zero socket drops). With the
   hardened kill-verify harness, smoke46 shows P0/P0X/P2 all at 99.9%
   delivery and datagrams of exactly 64 bytes (no GRO merging). All
   affected rows are being re-run (fig1-3b).
3. AN-003 (NEW, recorded): threaded-NAPI lost-wakeup wedge under flood.
   At >=790k with the NAPI kthread on a remote core (P3 sibling, P4
   other core) the queue's NAPI stops dead and permanently: kthread
   run-time delta exactly 0.000, wait-time 0, IRQ 312 masked-frozen,
   rx_out_of_buffer grows ~750k/s (the wire is fine; sender TX counters
   clean; zero pause at both ends). P3/P4 wedged 7/8 at >=790k; P3-525k
   rep3 wedged (1/3). Same-core threading (P2) was immune 3/3 in the
   matrix but wedged once in the p1wedge chain where C-states were not
   pinned - the trigger is state-sensitive (candidates: C-states,
   threaded 0/1 cycling history, kthread affinity history). The wedge-m
   matrix (P2/P3/P4 x PIN_IDLE on/off x 4 reps, interleaved order) is
   the deciding experiment and is running now.
4. deliv parse bug (pkts substring-matches mpkts) fixed in p1_analyze.
5. Low-load latency nugget (Fig 2, provisional n=1): W1 130k at 100%
   delivery: P0X (app on core 9, inline on 8) p50 11.5us vs P0 108.5us
   vs P2 114.5us. Separation removes the low-load latency cost entirely.

## Decisions in force

- Binaries frozen since fig1-3 (one implementation across arms). The
  post-freeze edits are instrument-only (byte counter, SO_RXQ_OVFL
  ground truth, manifest defaults) and applied uniformly to every arm
  and every re-run; noted as spec v2 instrument revision.
- Wedged runs are KEEP (they are the result, not a rig fault). Fig. 1
  will carry wedge markers; the knee model gets a wedge-probability
  column (feeds the Fig 4 note and Fig 5's design: the ladder must
  either survive the wedge or re-arm NAPI on rung switch).
- Fig. 10 is blocked (no Intel r650 in this allocation) — PI decision
  needed; every other figure is runnable on this block.

## Next actions

1. chain2 finishes ~09:16Z: analyze wedge-m (AN-003 verdict: does
   PIN_IDLE change wedge probability?) then fig1-3b; regenerate Figs
   1–3 with wedge markers; fill [X] in the abstract.
2. P1 kernel session (mainline v6.4.0 debs staged in /root/p1/kdeb,
   p1-kernel.sh arms the next boot) — the Fig 1 deferral line + the P1
   arms of Fig 7. Batch every P1 cell together per the skeleton.
3. Fig 4 knee cells (3 sizes x 3 placements, 162 runs in lists/fig4.txt)
   after Figs 1–3 freeze.
4. Fig 5: W5 profiles + p1ctl.py; must demonstrate wedge handling.

## Data locations

- Contract: ~/deep-research-output/rx-placement-admission/paper1-skeleton.md
  (status column maintained; placeholder-fill table added).
- Matrix rows: rx:/root/p1/rows-fig1-3.csv (99 rows, superseded by the
  fig1-3b merge); local copy analysis/rows-fig1-3.csv.
- Runs: rx:/root/p1/results/{fig1-3,smoke46,wedge-m,fig1-3b,wedge-P*}/
- Anomaly: cloudlab-profile/anomalies/AN-003.md (AN-002 is the clock
  program's sampler anomaly).
- Note: cloudlab-profile/notes/p1-LADDER-1.md (forensics section added).

## Addendum 08:00Z — wedge-m block tossed, chain status

- The first wedge-m block is TOSSED: PIN_IDLE was not encoded in the cell
  name, so the pin=1 and pin=0 runs overwrote each other per rep (the
  surviving data is pin=0 half-collapsed). Clean re-run queued as chain3
  with tags wedge-m0/wedge-m1 (= the pin label), interleaved policy
  order, to start when fig1-3b completes. Rule: anything varying mid-run
  gets its variable in the TAG.
- Contained mystery: in the tossed block, some consumers died at
  t=14-20s without a summary (empty consumer.txt, last win line at the
  death second, no dmesg entry, recvmmsg and histogram paths verified
  non-fatal and guarded). The earlier chains' logs and the process tree
  rule out concurrent drivers. Cause unresolved; watch for recurrence in
  fig1-3b and chain3. Affected runs are in the tossed block only so far.
- fig1-3b (the W1 re-run, 72 cells) is healthy and sequential (~117 s
  per cell from 07:38Z; expected CHAIN2-DONE ~10:05Z). Then chain3
  (24 cells, ~47 min) completes the wedge A/B. chain3 will be launched
  manually (the setsid waiter did not survive the launching ssh).
