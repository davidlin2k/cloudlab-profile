# Track A workshop paper: outline (DR-004; due 2026-09-29, drafted 2026-09-25)

Six pages. Established results only. Rules: every sentence with a number
cites a finding ID; every figure comes from a script in analysis/; only
Supported claims in the claim list (negative results are reported as
pre-registered outcomes, see Section 5 -- PI's call on including them).

## Title options (pick at review)

1. Separate, Don't Defer: Receive Overload Protection Without the Latency Cost
2. The Receive Overload Regression, and Predictable Placement as the Fix

## 1. Introduction (1 page)

- The regression in one paragraph: since Linux 6.5 the default receive path
  processes packets inline on the interrupt core; when a flood lands on the
  application's core the application receives 0.20% of the offered load
  (95% CI 0.20-0.20, n=2, at 2x the knee) [p1-LADDER.1; abstract fill,
  Fig. 1 data].
- The headline fix: moving the application off the receive core delivers
  97.5% and 74.2% of the offered load at 1.5x and 2x knee against the
  default's 9.0% and 0.2% [p1-LADDER.1, rows-fig1-3.csv].
- The mechanism sentence: co-location's latency cost is scheduler wait
  behind receive processing -- 50 us vs 4 us wake delay on TCP (12.5x) and
  34-60 us vs 4 us on UDP [p1-LADDER.2, p1-LADDER.6; C-012].
- Contributions (numbers cited in later sections): (a) the characterization
  across placements and kernel policy; (b) a knee model from two measured
  per-packet costs (2.8% and 6% miss) [p1-LADDER.4]; (c) TCP evidence on
  memcached with a pre-registered kill criterion that kills the
  transport-independence claim [p1-LADDER.6]; (d) the measurement lesson:
  stock per-CPU accounting undercounts receive work 166x on this kernel
  [p1-LADDER.3, AN-007; C-014].

## 2. Background (0.5 page)

NAPI, softirqs, threaded NAPI, the 2016 deferral and the 2023 revert --
Table 1 condensed to the workshop's space. No new numbers.

## 3. The trade-off on modern hardware (1.5 pages)

- Fig. 1 (analysis/p1_figures.py): goodput vs offered, one line per
  placement. The default collapses past the knee; separation drains; the
  threaded rungs stall under sustained overload (25 of 48 cells plus 24 of
  24; unpinned threaded NAPI fastest at 8 of 8 with onsets 9-19 s)
  [p1-LADDER.2; C-008, C-011]. Wedge markers per AN-003/AN-006.
- Fig. 2: low-rate p50/p99 per placement. The protection cost is latency:
  the first ladder rung pays none [p1-LADDER.2].
- Fig. 3 (analysis/p1_figures.py): CPU per packet by core. The hidden
  softirq share is 26-42% (mean 33%) at 390k pps and invisible to
  /proc/stat on this kernel (no CONFIG_IRQ_TIME_ACCOUNTING, NO_HZ_FULL);
  the PMU basis is required [p1-LADDER.3; C-014].
- Mechanism paragraph: perf sched shows the worker's wake wait behind the
  receive work (50/4 us TCP at 0.25x knee; 34-60/4 us UDP) with the NAPI
  kthread waking in 3 us in both placements [p1-LADDER.2, p1-LADDER.6].

## 4. Predicting the knee (1 page)

- Fig. 4 (analysis/p1_figures.py): predicted vs measured knee over packet
  sizes and placements. With the corrected busy metric the knee follows
  from two measured costs: 2.8% miss co-located (F = 451.0k vs 438.6k),
  6.2% separated (767k vs 818k) at 64 B [p1-LADDER.4; C-007 pending PI
  re-promotion -- flag at review].
- Scope sentence (negative result, Section 5 material): the same model
  built from low-load costs misses the TCP knee by 3.1x because the TCP
  per-request cost falls with load (16.1 us at 20k to 3.3 us at 300k)
  [p1-LADDER.6; C-017 Refuted].

## 5. TCP evidence and pre-registered negative results (1 page)

- Fig. 7 (first rows, analysis script to be named per the rule): memcached
  -t 1 under mutilate, 5 loads x 3 reps. Separation beats co-location at
  every load above the lightest: SLO frac 0.999 vs 0.829 and p99 645 vs
  1475 us at 1.5x knee; +15% goodput at 2x knee (369k vs 320k)
  [p1-LADDER.6; C-005, C-015].
- The kill criterion paragraph (PI's call): we pre-registered a criterion
  that would kill the transport-independence claim if goodput plateaued at
  2x knee. It plateaued at 169%/194% of knee goodput; the claim is Refuted
  and Dropped from the story (skeleton rule 4). What crosses to TCP is the
  co-location cost and SLO degradation, not the collapse
  [p1-LADDER.6; C-016, C-018].
- Method point: pre-registration kept every surprise from bending the
  story (AN-008: no knee to 130k before the saturation definition; three
  of four predictions failed on their own rules) [AN-008; specs/p1-W3MEMC].

## 6. Design sketch and discussion (1 page)

- The ladder (design only, no evaluation claims -- C-009 suspended): the
  application's core, then its SMT sibling, then another core, switched on
  predicted capacity via netlink and CPU affinity (p1ctl.py, 157 lines).
- Discussion: TCP scope (Section 5's boundary), power states (the
  low-load latency floor anomaly), other NICs (Fig. 10 blocked on the
  r650 allocation), upstreaming (a netdev report is drafted; no public
  mention before the PI approves it).
- Related work condensed to 3 sentences (the skeleton's list, one clause
  each): receive livelock's modern form; threaded NAPI supplies the
  mechanism, we supply the placement policy; IRQ suspension and busy
  polling need application changes (our BP arm: p50 41 us at 0.25x knee
  but SLO frac 0.807 at 1.5x vs separated 0.999) [p1-LADDER.6].

## Figure/script audit (rule: every figure from a script in analysis/)

| Fig | script | status |
|-----|--------|--------|
| 1, 2, 3 | analysis/p1_figures.py | Draft (QA pass 2026-09-24/25) |
| 4 | analysis/p1_figures.py (knee model recompute) | Draft (task 1) |
| 7 (first rows) | analysis/w3_analyze.py produces rows; the plot script must be added before the paper cites the figure | rows ready, plot script TODO |
| Table 1 | literature table (no script needed) | Final |

## Open items for the PI (2026-09-29 review)

1. C-007 re-promotion (the model numbers enter Section 4 only if promoted).
2. Include the pre-registered negative results (Section 5) or cut to
   positive results only.
3. Title pick; [Name] for the controller; whether the design sketch
   (Section 6) stays without evaluation.
