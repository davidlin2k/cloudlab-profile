# p1-CTRLSTALL -- control-plane stall under receive overload (DR-004 task 2)

**Version:** 1 (2026-09-25, pre-registered BEFORE runs; changing this
after runs start requires a new version)
**Question.** In P0 under flood, ordinary threads on the interrupt core
get about 0.2% of it (fig1-3 rows). Per-CPU kernel workers are ordinary
threads. Does receive overload stall the control plane?

## Prediction (frozen)

At 2x the knee in P0 (flood 790k pps = 2.02x the 390k knee), each
operation below takes over 1 s wall time. **Falsified if all stay under
2x their idle baseline.**

Operations (timed with `/usr/bin/time -f %e timeout 120 sh -c`):

1. `ip link add dummy0 type dummy && ip link del dummy0`
2. `ip netns add t1 && ip netns del t1`
3. `echo 1 > /proc/sys/vm/drop_caches`

## Design

- 5 runs per operation per arm; arms in order: idle, P0 flood, P0X
  flood (contrast). One p1cell per operation per flood arm (P0/P0X,
  W1, 790000, 64 B); operations run inside the measure window,
  timed on rx over the control network (the ssh path IS the control
  plane here).
- Timeout rule (the memo's): anything hitting the 120 s timeout stops
  the flood immediately and is recorded as censored at 120 s.
- Sample unit: one operation invocation. Report per arm/operation:
  all 5 times, the median, and the max.

## Gates

The cell's usual gates (conservation, landing, generator) apply to the
flood cells; the operation timing is the measurement.

## Outcomes

- All 15 flood-arm times < 2x their idle medians -> falsified.
- Any operation > 1 s under P0 flood -> prediction holds -> new claim
  (C-015) drafted in the result note.
- Timeout at 120 s -> the strongest form of the effect; recorded and
  reported to the PI in the Friday memo.

## Records

Result note notes/p1-LADDER-2.md (this set), FINDINGS entry, and the
claim ledger change if the prediction holds. Level H.
