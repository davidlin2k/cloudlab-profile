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
| C-010 | The affinity bailout causes the wedge | AN-006: REFUTED by the pre-registered A/B (aligned arms wedge 6/8 with aff_change near zero) | H | Refuted | 2026-09-24 |
| C-011 | Unpinned threaded NAPI wedges | AN-006: unpin arm 8/8 wedge, onsets 9-19 s (fastest of all arms); plus AN-003 | H | Pending | 2026-09-24 |
| C-007 | At 64 B, the co-located knee is predicted within 25% by per-packet costs once the hidden softirq share (h = 0.33, measured independently) is corrected: 2% miss co-located, 9% separated | DR-004 (PI promotion); knee re-grade checkpoints/2026-09-24-recovery-and-knee-regrade.md (supersedes earlier wording) | H | Supported, 64 B only | 2026-09-25 |
| C-008 | Threaded NAPI stalls under sustained overload on this host, in every placement: 25 of 48 cells plus 24 of 24 | DR-004 (PI promotion); AN-006 wdiag matrix + AN-003 (supersedes earlier wording) | H | Supported | 2026-09-25 |
| C-011 | Unpinned threaded NAPI stalls fastest: 8 of 8, onsets 9-19 s | DR-004 (PI promotion); AN-006 unpin arm (supersedes the Pending row) | H | Supported | 2026-09-25 |
| C-012 | Co-location's latency penalty is scheduler wait behind receive processing: 34-60 us wake delay against 4 us separated, unaffected by adaptive-rx | DR-004 (PI promotion); checkpoints/2026-09-24-decision8-latency-mechanism.md; collisions.md row 2 evidence | H | Supported at 130k packets/s, UDP; memcached pending | 2026-09-25 |
| C-013 | Separation's ceiling is the interrupt core: core 8 is 100% busy at about 1.2 us per packet while the application core runs about 85% | DR-004 (PI promotion); fig1-3 rows (analysis/rows-fig1-3.csv) | H | Supported, 64 B | 2026-09-25 |
| C-014 | Our cpuN_busy_s metric excludes softirq executed in interrupt context | DR-004 task 1 open (P0X 390k: cpu8_busy_s 0.16-0.31 s over 60 s although core 8 processes every packet) | - | Pending the task 1 fix | 2026-09-25 |
| C-005 | Co-location is slower even at low load | mechanism now measured (C-012); DR-004: stays Pending until memcached (W3) (supersedes the Pending-a-mechanism row) | H | Pending | 2026-09-25 |
| C-009 | The ladder stays within [Y]% of inline latency at low load and sustains [Z]x the default's goodput under overload | DR-004: the runtime switch is suspended | - | Suspended | 2026-09-25 |
| C-014 | Our cpuN_busy_s metric excludes softirq executed in interrupt context | AN-007: P0X 390k PMU 36.53s vs stat 0.22s (166x); kernel CONFIG_IRQ_TIME_ACCOUNTING=n + NO_HZ_FULL charges sub-tick IRQ bursts to idle (supersedes the Pending row) | H | Supported | 2026-09-25 |
