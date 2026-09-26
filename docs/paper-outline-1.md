# Paper outline (PI document, relayed verbatim 2026-09-26, ~22:0xZ)

Companion to decisions/DR-010.md (the run order) and
decisions/DR-009A-caution.md (the calibration). RQ1 gates everything.

---

# Paper outline (internal, draft v0)

## RQ1 (causality — run first; if this fails, no paper on this mechanism)

**Question:** does the driver's placement-correction path (stop-and-rearm
when busy off-CPU), rather than the off-CPU location itself, strand
eligible receive work?

**Design:** two arms, same placement, different completion behavior.
Thread pinned to the SAME off-CPU core; arm A is the driver as is,
arm B keeps polling. Readiness probe: completion entry ready but
unserved during gaps.

**Causal claim:** "holding placement fixed, replacing the
stop-and-rearm path with keep-polling restores service of ready work"
— i.e. the mechanism, not the location, causes the stall. If the
two-arm test doesn't show causality, there is no paper on this
mechanism.

## RQ2 (mechanism characterization)

**Question:** what exactly does the driver do differently on vs off the
expected CPU, and what restart guarantee does each path rely on?

On-CPU: keep polling. Off-CPU: stop, rearm, rely on an interrupt
restart that threaded NAPI does not deliver to the same thread.
Document both paths in source; the formal semantics make the assumed
guarantee precise.

## RQ3 (significance/realism)

**Question:** under what realistic load patterns does this cause
observable stalls?

Current evidence is one synthetic single-queue flood (790k pps) plus
reproduction in the harness. Before investing in the audit tool and
repairs, sweep triggers: burst patterns, multiple queues, rates near
the knee. If only an extreme flood triggers it, the paper is small.
Run RQ1 first; then RQ3's trigger sweep decides how big the paper can
be.

## RQ4 (generality — the contract)

**Question:** which drivers share the stop-and-rearm idiom, and does
the class prediction hold?

Five drivers found by grep (mlx5, mlx4, i40e, iavf, gve) with
divergent restart strategies. The audit tool verifies the idiom and
its restart semantics mechanically. mlx4 waits like mlx5 (predict:
latch); i40e/iavf force an interrupt (predict: churn, no latch); gve
DQO re-arms (predict: churn). Only after RQ1 and RQ3 confirm.

## RQ5 (repair evaluation)

F1 (driver-local re-trigger), F2 (core kthread pin), F3 (contract
repair) — measured on eliminating stranded work, with the livelock
invariant check. Only after RQ1 confirms.

## RQ6 (formal semantics, supporting role)

Model the handoff/restart semantics that RQ2 documents; derive the
sufficient restart guarantee; show the repair satisfies it. This is
support for the empirical result, not an independent contribution.
