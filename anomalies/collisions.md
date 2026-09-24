# Collision log (PI decision 10, started 2026-09-24)

One row per collision of independently built controllers and their
assumptions. This log becomes paper 2's dataset: ten minutes a day
keeps it alive. Working thesis (DR-003): *failures happen where
controllers' assumptions collide.*

| Controller A and its assumption | Controller B and its assumption | Condition that violates them | Evidence | Status |
| --- | --- | --- | --- | --- |
| 2017 driver idiom (mlx5e, i40e/iavf, mlx4, gve): NAPI polls on the IRQ's CPU; if not, bail and let the interrupt move polling (softirq assumption) | Threaded NAPI (2021): the scheduler places the poll thread where it is pinned | The kthread polls off the IRQ's CPU under load (P3/P4 rungs; unpinned drift) | AN-003 (24/24 wedges at 790k); ch7_aff_change 22.9M vs 3.9k on ch8; arm/poll 0.75 | Under A/B (wdiag v2; pre-registered in DR-002) |
| Scheduler per-thread accounting: schedstat shows only task time | Softirq/NAPI work runs outside any task | Co-located receive processing: its cost is invisible in app accounting | Fig 3: hidden softirq share 26-42%, mean 33% (C-006) | Measured |
| aRFS: steers flows to the CPU where the application consumes | IRQ affinity policy fixes the interrupt's CPU | aRFS moves processing off the IRQ's CPU (same collision as row 1, by design) | Kernel docs (RFS/aRFS design); not yet measured here | Logged, untested |
| irqbalance: reassigns IRQs to spread load | XPS: pins TX queues to CPUs for locality | irqbalance moves an IRQ XPS deliberately placed (and triggers row 1's bailout through the affinity change) | Not yet measured here | Logged, untested |
