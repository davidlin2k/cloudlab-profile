# p1-MIGRATE-1: the frozen v1 batch result + the v2 hop batch
# (counts only, per DR-010/DR-011)

FROZEN FORMAT. Node @clnode366, 6.17.8, the task-1 M158 protocol with
TRACE=1 (the wake trace) + the validated readiness probe (999 Hz) in
every cell. specs/p1-MIGRATE.md v1 froze before the run; v2 froze
after the v1 batch completed and governs the HOP batch.

## The frozen v1 batch (the counts that falsified the migration-only
## hypothesis)

| Arm | Wiring | Wedged | owned-gaps | ready-unserved s |
|---|---|---|---|---|
| M-A (unpinned/migrating) | 0-63 | **8/8** | [FILL per-cell] | [FILL] |
| M-B (pinned to 46) | {46} after the wiring | **5/8** | [FILL per-cell] | [FILL] |

Reference pinned cells (RQ1 arm A, the same harness without TRACE=1):
pin10 0/8; pin8 in-mask 0/8 (E2).

**The frozen M-B prediction (0/8) is falsified.** Static pin46
wedged with zero migrations after the pin: migration is not the
necessary condition. The wedge tracks which cpu the poll runs on
(pin10 clean, pin46 wedging, unpinned roaming wedging).

## The DR-011 gap classification (the v1 batch)

[CLASSIFY TABLE -- filled by p1/v1_classify.sh per cell:
event-silent / wake-lost / wake-flowing + the migrations per gap]
[FILL]

MA-1 (analyzed interactively): 5 stranded gaps = 4 event-silent
(0 wake attempts; one with 1 migration inside the window) +
1 wake-flowing (44,316 wakes ~= 44,298 switch-ins, 44,778 polls in
the 76 s window, 11 migrations -- the thread polls at ~585 Hz and
loses to the offered load).

## The v2 HOP-1046 batch (running)

| Cell | Wedged | gaps | owned-gaps | ready-unserved s | gap-starts-at-hop / in-46-residence |
|---|---|---|---|---|---|
| [HOP-1..30] | | | | | [the gap-start-vs-hop analysis] |

The decisive statistic (specs/p1-MIGRATE.md v2): stranded gaps
STARTING within 50 ms of a hop (migration-moment candidates) vs
gaps inside 46-residence segments (residence candidates).

## Honest anomalies during the run

- MB cells' probe cpu histograms show the thread on 46 for ~63% of
  samples with the remainder pre-pin (47/14) -- the pin held after
  the wiring; the pre-pin segment is the runner's discovery window.
- The wake trace's ch7 polls were identified by the napi struct
  address (ch + 10000 DECIMAL = +0x2710); the first analyzer run
  used a hex-10000 arithmetic error and found 0 polls (fixed,
  committed).
- The analyzer's probe/trace alignment uses the tail-50 match; the
  spread was ~7 s in MA-1 (the finder-flood portion of the probe
  csv has no trace counterpart). Treat the per-gap wake counts as
  +/- a few seconds at the edges; the classifications are robust to
  this (the gap windows are 5-76 s).

Counts end here. The v2 batch's table and the final deliverable
fill when the HOP batch lands (~3.5 h from launch).
