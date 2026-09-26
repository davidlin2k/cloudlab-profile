# Decision record DR-010

Provenance: PI memo, relayed verbatim by the user on 2026-09-26
(Saturday, ~22:0xZ, as a pasted text), interrupting the post-PERSIST
analysis. Committed as-is per the standing convention (provenance
header only; memo body unedited). DR-010 SUPERSEDES the execution
order of DR-009: one bounded causal investigation (RQ1) comes first;
the mechanism is NOT yet causally established ("ready-but-unserved
work throughout the gaps" has not been measured); no disclosure, no
broad theory, no OSDI/EuroSys confidence until it lands. Context at
receipt: PERSIST finished 20:33:35Z with A1 2/10 (below its >=3/10
replication threshold) and A7 1/10 (below the >=8/10 confirmatory
prediction) -- the latching rate dropped versus the earlier cells,
independently consistent with the memo's caution.

---

**We have one useful mechanistic insight, but we have not established the discovery that would make it a paper.** I made that harder to see by mixing three projects: CPU placement/accounting, a possible receive-progress bug, and a general formal theory. We should separate them.

The specific insight is:

**The driver's attempt to correct CPU placement may itself interfere with continued packet processing.**

Here is the concrete reasoning. In the inspected mlx5 path:

- When polling is busy on the expected CPU, it can keep polling.
- When polling is busy outside the IRQ-affinity mask, it attempts to finish and rearm notifications.
- That behavior was intended to let another interrupt restart processing on the appropriate CPU.
- With a separately scheduled NAPI thread, another interrupt does **not automatically move that thread** to the interrupt CPU.

Consequently, a mechanism intended to handle a temporary placement mismatch can be encountered repeatedly. **Placement changes which restart mechanism the driver relies on, not merely the cost of executing each packet.**

That source-level interaction is real. Its original placement rationale is also documented, so discovering the rationale alone is not novel. The unresolved question is whether the changed restart dependency actually strands work in your experiments.

Consider a hypothetical queue with 128 ready packets and a polling budget of 64. After processing the first 64, the worker takes the off-mask completion path. What ensures that it processes the remaining 64? If rearming reliably restarts service, this can be healthy. If it does not, available work can wait despite available CPU capacity.

**We have not yet measured that distinction reliably.** Our traces show gaps and CPU-dependent behavior, but the existing readiness measurements do not securely establish that eligible work remained throughout those gaps.

This is where we actually stand:

| What we have | What it establishes |
|---|---|
| Large measured placement effects | Placement materially affects this configuration. |
| A source-level change between continued polling and completion/rearm | A concrete mechanism through which placement could affect progress. |
| Traces consistent with that mechanism | A reason to investigate it, not causal confirmation. |
| A conditional formal counterexample | The proposed failure is possible under specified semantics; those semantics remain unverified on the device. |

**The research destination I recommend is a narrow causal result: determine whether the placement-correction mechanism causes the receive stall, and repair that mechanism while preserving useful scheduling behavior.**

The decisive result would be: keep the worker on the same off-mask CPU, preserve its next polling opportunity, and show that previously delayed eligible work is served. That would distinguish an expensive place to execute from a faulty attempt to stop executing there. It would also explain why pinning helps without treating pinning as the explanation.

If that result holds, we have something worth developing: an execution-mode change invalidated an old assumption connecting interrupts, placement, and continued service. Then the model helps identify sufficient restart guarantees, and the repair tests their practical value.

If it does not hold, **we should stop making this mechanism the center of the paper.** The placement measurements remain useful, but we must investigate their cause separately. We should not keep adding theory to protect the preferred explanation.

Formal verification therefore has a supporting role right now. It should make the concrete handoff and repair precise after we establish their correspondence to the system. It is not currently an independent breakthrough.

My PI judgment is: **this lead deserves one bounded causal investigation; it does not yet justify a broad theory project or confidence about OSDI/EuroSys.** Most of our recent progress has been correcting the evidence and sharpening the question, rather than adding new experimental confirmation. I should have made that distinction explicit earlier.

The question organizing the project should now be only this: **does the mechanism trying to correct placement cause the stall?** Everything else earns its place after that answer.