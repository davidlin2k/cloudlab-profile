# DRAFT disclosure v1 -- mlx5: threaded-NAPI affinity bailout parks a
# budget-exhausted poll with a full completion queue (metastable
# receive trickle / effective DoS)

DRAFT -- PI review pending. Route per DR-007/DR-008: private to
security@kernel.org, mlx5 maintainers + netdev CC (get_maintainer.pl
output attached at send time). NOT SENT. Severity wording pending A0
counts. [A0: PENDING -- batch running]

## Summary

On kernel 6.17.8 with a ConnectX-5 (mlx5_core, fw 20.43.3608),
enabling threaded NAPI and loading the queue whose IRQ is affined to a
single busy CPU can drive the receive queue into a metastable state in
which it drains ~24-80 packets/s against ~790k packets/s offered --
indistinguishable from a dead queue for minutes at a time. The queue
self-recovers when load drops or traffic patterns change. The state
signature is unambiguous: tens of thousands of valid, unconsumed
completions in the completion queue (~60,842 observed; owner-walk from
cc, healthy control 0), the NAPI parked with no SCHED/MISSED bit, no
UMR outstanding, ICOSQ fully drained, the RQ enabled with buffers
posted, and per-event polls consuming exactly one 64-CQE budget.

## Mechanism (code path confirmed by trace + a verified-aligned A/B)

mlx5e_napi_poll (drivers/net/ethernet/mellanox/mlx5/core/en_txrx.c)
marks the poll busy when the budget is exhausted (work_done == budget)
and returns the full budget so the core repolls -- unless the poll is
running off the channel's IRQ affinity CPU, in which case the driver
takes the affinity bailout: `ch_stats->aff_change++; if (work_done ==
budget) work_done--;` and falls through to napi_complete_done(). The
decrement makes a budget-exhausted poll LOOK short to the core, so the
core releases the NAPI: it parks, and further draining waits for the
next hardware completion event -- which, with the CQ nearly full,
arrives only after the previous poll frees slots. The fixed point:

    poll 63 off-mask -> complete_done -> park -> event -> poll 63 ...

drains ~one budget per event. With the completion backlog built up by
an overload (790k pps vs a knee near 525k on this platform), the queue
cannot catch up and stays wedged until offered load falls far enough
that one-poll-per-event keeps up.

Trace evidence (74,120 lines, dead regime): on the affinity CPU, 591
budget-exhausted polls returned 64 and repolled (no complete_done);
off-mask, 562 polls returned 63 and EVERY one completed and parked
(napi_complete_done ret=1; the MISSED-race rescue ret=0 fired zero
times). ch_stats.aff_change advanced +536 over the window -- matching
the off-mask poll count. Events tracked polls ~1:1.

The verified-aligned re-run (8/8 cells, manipulation gate: thread
mask == IRQ mask on every 1 Hz sample, aff_change delta 0) shows 0/8
latches: on the affinity CPU the drain works as designed. The unpinned
case is the failure: the threaded NAPI kthread is created unpinned
(fresh-boot E1: 64/64 kthreads with Cpus_allowed_list = 0-63; nothing
in net/core/dev.c binds it), so any workload that occupies the IRQ's
CPU pushes polls off-mask.

## Default exposure

- threaded NAPI kthreads are created with no affinity binding
  (kthread_run, no set_cpus_allowed_ptr) -- confirmed on hardware
  (fresh boot, before any tuning).
- mlx5 does not opt into the core's NAPI affinity automation
  (netif_set_affinity_auto; iavf/ice/idpf do).
- The NAPI documentation's busy-poll advice ("set the CPU affinity of
  this kthread to an unused CPU core") steers users onto an off-IRQ
  core -- the exact trigger condition. The docs' recommended tuning
  creates the failure mode on mlx5/mlx4.

Severity: the queue becomes functionally dead (a >99.99% delivery
collapse) under sustained overload while it remains enabled, posted,
and event-silent-adjacent; it self-recovers when load drops
(PERSIST/A0 arm [PENDING] is deciding permanent-latch vs deep-trickle
counts). Recovery is not immediate: two specimens self-recovered only
minutes after the wedge, and only under probe traffic.

## The class (per-driver restart strategies; from source, to be
confirmed per driver)

The same bailout idiom exists in five mainline drivers: mlx5, mlx4,
i40e, iavf, gve. Their restart strategies differ, and the predictions
are falsifiable:

- mlx4 waits like mlx5 -> predict: same latch.
- i40e forces an interrupt after bailout -> predict: churn, no latch.
- gve DQO re-arms and leans on hardware PBA -> predict: churn.
- iavf: predict: churn.

mlx4 confirmation is planned on CloudLab m400/m510 (ConnectX-3)
[E4: PENDING reservation].

## Why striding was the red herring

Multi-packet (striding) RQ correlated across all 6 fuzz hits and both
ring sizes, but ring size did not matter (8/8 wedge at 1024 and 8192),
and the dead-state dump shows the latch is upstream of the refill
path: ICOSQ pc==cc, no UMR outstanding, no allocation errors, buffers
posted. Striding RQ is a trigger condition (it builds the CQ backlog
shape that makes the parked poll fatal); the latch itself is the
bailout-parks-budget-exhausted-poll interaction with an unpinned
threaded NAPI.

## Fix candidates (built and measured, [E5: PENDING])

- F1 (driver): in the bailout, when the budget was exhausted,
  napi_schedule() and return instead of decrement-and-complete. Short
  polls keep the existing hand-back. (The same restart strategy i40e
  uses; mlx5 already uses napi_schedule on the XSK path.)
- F2 (core): bind the threaded NAPI kthread to its NAPI's IRQ affinity
  mask at creation (n->config->affinity_mask; the core tracks it;
  iavf/ice/idpf opt in via netif_set_affinity_auto). A hint
  (set_cpus_allowed_ptr), still userspace-overridable.

Pre-registered success: 0/8 latches on both (vs >= 3/8 unfixed
baseline), and no livelock regression in the inline-poll
app-on-IRQ-core config (the bailout's original 2017 purpose).

## Reproduction (the essential recipe)

1. ConnectX-5, 6.17.8, single flow steering (we use explicit ntuple
   rules; RSS-key steering is fragile), queue 7's IRQ affined to one
   CPU (comp7 -> CPU 8).
2. echo 1 > /sys/class/net/<dev>/threaded; leave the napi kthreads
   unpinned.
3. Run an application pinned to CPU 8 (the IRQ core) that keeps it
   busy; flood the steered queue at ~790k pps (5 senders x 158k) until
   rx7 goes flat for 3 s (out-of-buffer climbs), hold 10 s, drop to
   ~158k, wait.
4. The queue stays dead at the probe (10k pps, 30 s, advance ~0 vs
   ~300k healthy) while: rx7_packets flat, rx_out_of_buffer climbing,
   ICOSQ pc==cc, RQ enabled, no UMR outstanding.
5. State dump recipe and the b2_dump.py reader available on request
   (kcore + DWARF vmlinux; healthy-control validated).

## Novelty

No prior report found for this failure (lore searches: the exact
identifier, threaded-napi-affinity-stall families, bailout semantics;
[E6: none found -- caveat: web-indexed lore coverage]). The 2026
threaded-NAPI items on record are different (the thread-never-yields
RCU stall -- the opposite failure; XSK unlocked-ICOSQ races; the
PCI-offline soft lockup; kthread-reuse visibility after queue
reduction).

## Not included / boundaries

- The platform's numbers (790k/525k/158k, knee placement) are
  hardware-specific; the mechanism is not.
- No exploit framing: this is a reliability/liveness bug, not a
  privilege boundary.
- The cloudlab-profile artifacts (dump tool, traces, cell logs) are
  available privately on request.

Send-to (get_maintainer.pl on the two touched files) [TO FILL AT SEND]:
mlx5 maintainers, netdev, security@kernel.org (private first per
process).
