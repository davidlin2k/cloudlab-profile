# Claims ledger

| ID | Claim | Evidence | Level | Status | Last reviewed |
| --- | --- | --- | --- | --- | --- |
| C-001 | Phase alignment (aligned vs random vs per-engine) does not change delivered throughput through a proxy at 25k-75k streams under one-token-one-segment emission. | C1-CLOCK.1 | H | Pending | 2026-09-24 |
| C-002 | The decode step clock is smeared at the wire above a few thousand streams; the arrival signature is a 25ms sawtooth, not instant incast. | C1-CLOCK.2 | H | Pending | 2026-09-24 |
| C-003 | The host stack fails on per-token user-space work before kernel receive limits at this scale (HAProxy 13.2 cores at 1.88M tok/s; softnet drops 0.002%, squeeze 0). | K-series, AN-001 | H | Contested | 2026-09-24 |
| C-004 | Since 6.5 the inline default cuts the app to 0.20% of offered under flood (95% CI 0.20-0.20, n=2, at 2x knee). | p1-LADDER-3, fig1-3-draft checkpoint, F-p1-LADDER-1 | H | Pending | 2026-09-24 |
| C-005 | Co-location is slower even at low load (Pending a mechanism) | F-p1-LADDER-2; smoke46 W1 130k p50 108.5 us co-located vs 11.5 us separated (n=1/arm); W2 p50 104.5 [27.5,144.5] vs 55.2 [28.5,107.5] us (n=3) | H | Pending | 2026-09-24: revised per PI (DR-003 records); mechanism owed before it enters any claim -- perf sched + adaptive-rx A/B (DR-003 decision 8). Prior claim text: "Co-location costs low-load latency; separation removes it" |
| C-006 | Per-thread accounting hides 26-42% of the app core near the collapse region (390k, n=3). | rows-fig1-3/fig1-3b, F-p1-LADDER-3 | H | Pending | 2026-09-24 |
| C-007 | Each placement's knee follows from two measured per-packet costs + SMT slowdown (form F, within 25%). | analysis/p1_fig4.py preview: 64 B misses 42-91% | A/H | Contested | 2026-09-24 |
| C-008 | Threaded NAPI wedges under sustained flood on this host: all placements, 24/24 cells at 790k, onset t=2..68, C-state independent. | wedge-m0/m1 (24 cells), AN-003, wedge-ab-verdict checkpoint | H | Pending | 2026-09-24 |
| C-009 | The ladder stays within [Y]% of inline latency at low load and sustains [Z]x the default's goodput under overload. | pending Figs 5-8 | - | Pending | 2026-09-24 |
| C-010 | The affinity bailout causes the wedge | AN-003 + wdiag v2 A/B (pre-registered DR-002) | H | Pending | 2026-09-24 |
| C-011 | Unpinned threaded NAPI wedges | AN-003 (kthread affinity 0-63 observed); wdiag v2 unpin arm | H | Pending | 2026-09-24 |

