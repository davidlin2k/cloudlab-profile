# FINDINGS (append-only)

### C1-CLOCK.1 — 2026-09-24 — level H
With the emitter timer fixed (AN-001), 25k/50k/75k streams through
HAProxy deliver 100% of offered load (0.998-1.032 of 1.0/2.0/3.0
Mtok/s over 27 runs of 75s) with zero drops and zero stall-seconds
per stream, and aligned/random/per-engine phases do not differ; at
100k the split 3.47/3.98/4.02 Mtok/s rests on one outlier rep. Rate
values interim per AN-002.
Supersedes: none · Note: notes/C1-CLOCK-1.md · Figure: F-C1-CLOCK-1

### C1-CLOCK.2 — 2026-09-24 — level H
The decode step is smeared at the wire at these scales: with
one-token-one-segment emission, 50k and 150k "aligned" streams put
p50 = 4.0-4.2% of each 25ms step's packets in its first 1ms at the
proxy NIC (the uniform-phase value is 4.0%; 13.9M and 14.5M packets
captured over 12s), peakedness 1.5-1.6 — the write path serializes
~25k writes per step into a sawtooth, so wire-level incast requires
sender-side coalesce+multiplex.
Supersedes: none · Note: notes/C1-CLOCK-1.md · Figure: pending

