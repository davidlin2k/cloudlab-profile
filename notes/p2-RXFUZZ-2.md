# p2-RXFUZZ-2: minimization pass over the 6 night-1 hits (2026-09-26, 04:00-09:36Z)

Facts only. rxfuzz.py minimize --cell <hit> per hit: each dimension reset
singly to the task-1 default (all others held at hit values); dims whose
reset removed the hit are reported as the "minimal dimensions (reset
removes the hit)" = the minimal wedging set per hit; then 3 confirmation
cells on the reduced config (kept dims at hit values, reset dims at
defaults). Full log: node /root/p2/minimize-all.log,
analysis/rxfuzz-minimize-1.log (committed copy).

## The table (per-hit minimal wedging sets)

| cell | minimal wedging set (reset removes the hit) | reduced-config confirms |
|------|----------------------------------------------|-------------------------|
| 015 | threaded | 3/3 wedged (probe 0, 100845, 0) |
| 038 | adaptive_rx, striding_rq | 1/3 wedged (probe 0; then 300099, 300097 = PROBE-OK) |
| 056 | threaded, napi_placement, adaptive_rx, ring, striding_rq, busy_read, napi_defer_hard_irqs, gro_flush_timeout (all sampled dims) | 0/3 wedged (probes 300098-300100, ceiling) |
| 069 | napi_placement, adaptive_rx, ring, gro, napi_defer_hard_irqs, gro_flush_timeout -- **threaded NOT in the set** | 0/3 wedged (probes 300097, 315314, 300102) |
| 086 | (empty -- no single reset removes the hit) | 3/3 wedged (probe 0, 0, 0) |
| 089 | threaded, napi_placement, adaptive_rx, ring, striding_rq, busy_read, gro_flush_timeout -- **threaded in the set** | 3/3 wedged (probe 0) |

## Intersection across the 6: EMPTY

No single fuzzer dimension is necessary for all six hits (086's set is
empty). Read together with AN-006B/C: the fuzzer's dimensions set up the
backlog condition; the latch lives in the fixed wiring the fuzzer does not
sample (unpinned threaded NAPI + IRQ affinity pinned to the busy
application core). The reduced-config confirms are consistent: 086 and 089
(the A1-family cells) wedge at all-defaults; 056 and 069 families are clean
once the backlog dims are reset.

## Per-hit readings

- 015: threaded necessary (reset threaded->0 removed the hit) -- the plain
  mechanism signature (cell ran threaded=1).
- 038: adaptive_rx AND striding_rq each individually necessary;
  **threaded not required -- the cell still wedged with threaded=0**.
- 056: every sampled dim individually breaks it; the reduced (all-defaults)
  config is clean (0/3).
- 069: six backlog dims necessary; **the threaded reset did NOT remove the
  hit -- 069 wedged with threaded=1 too** (threading-agnostic).
- 086: no single reset breaks it; the all-defaults config wedges 3/3 at
  probe=0 (fast-onset, 4.1 s family -- the plain wedge).
- 089: **threaded=0 (the kernel default value) was necessary** -- resetting
  threaded to 1 removed the hit; the all-defaults config wedges 3/3.

## A4 same-hour flag (per DR-007's rule)

- **069: FIRES** -- `threaded` is NOT in 069's minimal wedging set; the
  cell wedges under both threaded values. By the PI's rule this is the
  evidence that the failure is not specific to threaded NAPI.
- 038: also threading-agnostic (threaded absent from its set).
- 089: the rule as written does not fire (threaded IS in the set), but the
  direction is the other alarming one: the wedge REQUIRES the kernel's
  default threading value (threaded=0).
- Caveats carried from the PI's night-1 review: 069/038/089 are non-plain
  families (adaptive/ring/gro or smt-sibling placement moved), still
  uncontrolled; PERSIST A4/A5 + A0 are the controlled read.

## E7 remainder

The 069 "minimize" half is done (this note); the one-trace half (a
trace on a threaded=0 cell's wedge) is queued per DR-008's priority order.
