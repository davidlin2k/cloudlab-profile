# D1 (DRAFT v3, complete): mlx5 threaded-NAPI stall under sustained flood
# Status: DRAFT -- the PI approves before anything is sent (DR-013 D1;
# DR-014 additionally holds the report until the re-arm/watchdog rows
# land).  Every factual line traces to a committed artifact.
# Supersedes the v2 skeleton (its TBDs are filled: T1d and T1b below).
#
# Recipients (the memo): netdev + the mlx5 maintainers from
# scripts/get_maintainer.pl on the mlx5 core/en paths; the vendor
# channel ADDED per T1a's device/firmware verdict (notes/p1-T1A-1.md).
#
# T1a's verdict (2026-09-27): during every event-silent gap the comp
# EQ is EMPTY (no device-written EQE at the frozen cons_index), the
# hardware IRQ count does not move, the CQ is armed with pending
# owned completions, and rx_out_of_buffer climbs by tens of millions.
# Per the pre-registered table (specs/p1-T1A.md): device/firmware.

Subject: [BUG] mlx5: threaded-NAPI receive queue goes event-silent for
         0.3-280 s under sustained flood; completions pending in an
         armed CQ, comp EQ empty, IRQ not asserted

Environment (exact):
- kernels: 6.17.8 (custom build of the v6.17.8 stable tree), 6.18.9+
  (adb851edb), net-next 7.3.0-rc4+ (014d795c7) -- the stall reproduces
  on all three (T1d, n=8 pin46 per kernel: 8/8, 8/8)
- NIC: ConnectX-6 MT28908, fw 20.43.3608 (DEL0000000010)
- host: CloudLab Clemson c6525-25g (r650-class), EPYC 9354P 32-core,
  4 NUMA nodes x (8 cores, SMT2) = 64 hw threads; the NIC on node 1
  (cpus 8-15, 40-47); L3 domains {8-11,40-43}, {12-15,44-47}
- NIC driver: mlx5_core (module), threaded NAPI enabled, default
  channels=32 (the flooded queue: ch7, irq 312, irq home cpu 8)
- reproducer: one command (k5blast flood + threaded NAPI + the pin;
  shipped with the D4 tool release)

What is observed (the headline facts):
1. Under sustained UDP flood (158k pps, 64 B, one queue), the
   queue's polling thread stops being served: ready completions sit
   in the CQ with the ownership bit flipped while the consumer
   index is frozen. The largest single event-silent stretch
   recorded: 279.6 s (T1A-1); the typical range 0.3-10.5 s;
   self-recovery. (notes/p1-MIGRATE-2.md, notes/p1-ARM_SN-1.md)
2. >= 60,842 completions stranded in one cell (the ready-unserved
   count; MIGRATE-2 MB arm). The stall is placement-dependent:
   pin46 (adjacent CCX, same NUMA) 8/8 wedged; pin10 (same L3 as
   the IRQ core) 0/20; unpinned 4/8; pin24 (far NUMA) 5/8 with 33.5
   stranded gaps/cell. The wedge rate is NOT monotone in distance;
   the asymmetry is specific to the 46/8 CCX pair. (C-021,
   notes/p1-LOCALITY-1.md)
3. T1a device-state capture (specs/p1-T1A.md, notes/p1-T1A-1.md):
   during EVERY gap -- eq_ci frozen; the comp EQ EMPTY (zero
   device-written EQEs at the frozen cons_index); zero hardware IRQ
   entries on the vector (tracepoint irq:irq_handler_entry); zero
   completion events; the CQ armed (adb_sn == arm_sn&3, 1982/1983
   samples); rx_out_of_buffer climbing by 60M+ while the queue sits
   unserved. Per the pre-registered decision rule: device/firmware.

What is ruled out (one line each, with its artifact):
- The affinity bailout: refuted by the pre-registered A/B
  (AN-006; C-010).
- The arm_sn stale-doorbell race: refuted -- 0 stale-arm candidates
  in 67 stranded gaps; the device accepted the arm then went silent
  (notes/p1-ARM_SN-1.md; C-020).
- RQ1 arm A (the sw scheduler starvation variant): refuted (the
  RQ1 A/B; notes/p1-RQ1*.md TBD exact note).
- Core wake-path loss (wake-lost): rare, not the mechanism (4/308
  MIGRATE-2, 1/67 ARM_SN, 2/138 T1A; the wake-lost class never
  dominates).
- The host CPU scheduler moving the thread: the placement facts
  above INCLUDE the pinned arms; the stall persists on a pinned
  cpu (46; 63% of post-gap samples).
- Interrupt-delivery loss on an armed+non-empty EQ: excluded by
  T1a (the EQ is empty -- nothing to deliver).

T1d (current code) and T1b (the second NIC) results:
- T1d: the stall reproduces on 6.18.9+ (adb851edb) and on net-next
  7.3.0-rc4+ (014d795c7) -- 8/8 wedged in the pin46 arm on each
  (notes/p1-T1D-1.md; C-023).  Not fixed upstream.
- T1b: the identical protocol on i40e / Intel Xeon (X710-DA2, 2x16c
  Gold 6142, same 6.17.8 build) shows 0/8 stranded in every arm --
  the IRQ core's SMT sibling, same-socket, other-socket, and
  unpinned, 2 DUT/sender pairs x 4 randomized blocks, with a
  descriptor-level readiness detector (DD bit at next_to_process)
  armed and sampling in every cell (notes/p1-T1B-1.md; C-025).
  NOTE the confound: NIC and CPU platform changed together.  This
  cross-check is consistent with a mlx5/device-side failure (T1a's
  call); it does not by itself exclude a generic interaction, and
  an Intel+mlx5 platform (CloudLab xl170) would close that gap.

Workaround: pin the threaded-NAPI poller to the same L3 as its IRQ
core: 0/20 cells stalled (95% upper bound about 14%; p1-T1C).
(The T1e in-kernel variant -- auto-placing the poller in the IRQ's
L3-sibling cluster -- did NOT hold up: 5/8 wedged with the patch
mechanism verified live; C-022.  The workaround is a configuration,
not a patch.)

Upstream context (the DR-013 addendum):
- The June 2026 threaded-NAPI lifecycle RFC (resets destroy the
  thread); the merged napi_config IRQ-affinity series covers bnxt,
  ice and idpf -- not the thread.
- The September 2026 mlx5e XSK-path race fix in the same
  complete-then-rearm window (c326f9c68921) does not touch our
  non-XSK path (absent from the measured 6.17.8 tree by grep; the
  T1d record covers 6.18.9 / net-next).

Attachments: the stall dataset (timelines, probe CSVs, checksums --
the D4 release), the reproducer, the per-figure scripts.

Notes for the PI's review (NOT part of the report):
- The fw release-note reading: after 20.43.3608 no EQ/CQ/event fix
  is claimed by any release (notes/p1-T1C-fw-notes.md) -- the
  vendor may still have internal fixes; that is their call.
- The T1a instrument limits (the eq_update_ci MMIO commit is not
  host-readable) are stated in the report's "what we measured"
  section, not hidden.
