# Paper 1 skeleton (contract of record)

Written backwards from the paper: every run the student does maps to a
figure here. Source: PI issuance, 2026-09-24 (session bg_013552_b7f304,
message 5960, verbatim). Maintained copy: the Status column and the
abstract placeholders are updated per the contract below.

## Title and abstract

Bracketed values are placeholders; each one names the figure that will fill it.

**Title options:**

1. Separate, Don't Defer: Receive Overload Protection Without the Latency Cost
2. Linux Gave Up Receive Overload Protection; Getting It Back Without Paying Latency
3. Climbing the Ladder: Predictive Receive Placement for Overloaded Linux Hosts

**Abstract:**

> Since Linux 6.5, the default receive path no longer protects applications from receive overload. When a flood arrives on a queue whose interrupt core the application shares, the application receives 0.2\% of the offered load (95\\% CI 0.20–0.20, n=2, at 2× the knee) on a modern 32-core server \[Fig. 1\]. Linux has switched between two global policies, processing packets inline for latency or deferring them to a thread for protection, and each fails in one regime. We show that the choice belongs to each queue at runtime, and that the right response to load is to separate network processing from the application rather than defer it on the same core \[Figs. 1–3\]. On memcached over TCP the same co-location penalty appears as SLO collapse (attainment 0.829 against 0.999 separated at 1.5× the knee, n=3) and 15\% more goodput separated at 2× the knee (369k against 320k QPS), though the throughput collapse itself does not cross to TCP \[Fig. 7\]. The load at which each placement collapses is predictable from two measured per-packet costs \[Fig. 4\]. \[Name\], a \[N\]-line controller built only on stock kernel interfaces, predicts each queue's knee and moves its NAPI processing from the application's core to its SMT sibling and then to another core before the knee is crossed \[Fig. 5\]. On UDP floods and memcached, \[Name\] stays within \[Y\]% of inline processing's latency at low load and sustains \[Z\]× the default's goodput under overload \[Figs. 6–8\].

## Claim and contributions

**The claim in one line:** under receive load, separate network processing from the application before a predictable knee, instead of deferring it on the same core after overload is detected.

1. **Characterization.** The receive-overload trade-off measured on a modern chiplet server across kernel policies (before and after the 6.5 revert) and placements, with the scheduler's blind spot for softirq time quantified. Figures 1–3.
2. **Model.** Each placement's collapse point predicted from two measured per-packet costs, plus the SMT slowdown, and validated across packet sizes and placements. Figure 4.
3. **Design.** A predictive placement ladder built on stock per-NAPI threaded mode: the application's core, then its SMT sibling, then another core. Figure 5.
4. **Evaluation.** UDP and memcached, floods, bursts and many queues, on two platforms, against every static policy, IRQ suspension and busy polling. Figures 6–10.

## Figures

Ten figures and two tables carry the paper. A run that feeds none of them waits until the PI approves it.

| Figure | Shows | Claim it carries | Produced by | Status |
| --- | --- | --- | --- | --- |
| Fig. 1 | Goodput against offered rate (0.25–2.5 × knee), one line per policy: inline, same-core deferral (pre-6.5 kernel, and threaded on the same core), threaded on the sibling, threaded on another core | Inline collapses past the knee; deferral caps near half a core; separation drains more | D1 | Draft (2026-09-24: dataset complete, 111 rows; DR-001 OPEN -- claim partially fails on the threaded rungs (rule 4); P1 line pending kernel session) |
| Fig. 2 | Low-rate p50 and p99 round trip per policy | Protection costs latency at low load; the ladder's first rung doesn't | D1 | Draft (2026-09-24: dataset complete; W2 3-rep CIs + W1 full-delivery nugget, note 3) |
| Fig. 3 | CPU time per packet by core and by thread, per policy | Where the cycles go, and how per-thread accounting hides softirq work | D1 | Draft (2026-09-24: dataset complete; hidden softirq share 26–42% at 390k, mean 33%) |
| Fig. 4 | Predicted against measured knee, across 3 packet sizes and 3 placements | The collapse point is predictable from two measured costs | D1 plus knee cells | Draft (2026-09-25: knee model recomputed on the PMU basis -- 2.8% miss co-located, 6.2% separated at 64 B [p1-LADDER.4]; chain6's 162 cells were killed per DR-003, the recompute replaces them. C-007 re-promotion pending. TCP scope: model Refuted there (C-017)) |
| Fig. 5 | Time series under a ramp and under bursts: rung chosen, goodput, latency | The ladder moves before the knee without flapping | C1 | Not run (p1ctl.py controller + W5 harness ready; must survive AN-003 wedge) |
| Fig. 6 | Goodput under SLO and p99 against load, the ladder against every static policy | Within 10% of the best static rung at every load | C1 | Not run |
| Fig. 7 | memcached: goodput under SLO against load, every policy plus IRQ suspension and busy polling | It holds for TCP and a real application | L1 | Running (2026-09-25: W3 45 cells done, P0/P0X/BP x 5 loads x 3 reps. Separation Supported (C-015): SLO frac 0.999 vs 0.829 at 1.5x knee, +15% goodput at 2x. Collapse-does-not-survive-TCP: the transport claim is Dropped per rule 4 (C-016 Refuted, kill criterion fired). Model-for-TCP Refuted (C-017). P1/P5/P7 policies pending. See notes/p1-W3.md) |
| Fig. 8 | memcached with a UDP flood on the same queue: SLO attainment against flood rate | The ladder protects a service under attack | Robustness | Not run |
| Fig. 9 | 8, 16 and 32 queues with independent controllers: goodput and controller CPU | It scales across queues | Robustness | Not run |
| Fig. 10 | Figure 1 repeated on the Intel r650 | The trade-off isn't specific to Genoa | Platform | Blocked: no Intel r650 in this allocation (all 6 nodes Genoa r6615) - PI decision needed |
| Table 1 | Linux's softirq policy history, 2016–2025 | Motivation | Literature | Final, 5 reps |
| Table 2 | Controller overhead: CPU, switch latency, lines of code | Practicality | C1 | Not run |

## Evaluation matrix

About 870 runs, roughly 22 machine hours at 90 s each, spread over eight weeks.

| Workload | Definition |
| --- | --- |
| W1 | UDP incast flood onto one queue: the K2AGG setup, five senders, port-authored, consumed by `k2_rx` |
| W2 | UDP request and response at low rate with `k3mot`, for latency |
| W3 | memcached under mutilate, open-loop, 90% GETs, 32-byte values |
| W4 | W3 with a UDP flood arriving on the same queue |
| W5 | Load that ramps, bursts and steps, for time series |

| Policy | Definition |
| --- | --- |
| P0 | Inline softirq: Linux 6.17 default |
| P1 | A pre-6.5 kernel: ksoftirqd deferral on the same core |
| P2 | Threaded NAPI, kthread on the consumer's core |
| P3 | Threaded NAPI, kthread on the consumer's SMT sibling |
| P4 | Threaded NAPI, kthread on another core |
| P5 | IRQ suspension |
| P6 | Busy polling |
| P7 | The ladder controller |

**Metrics, every run:** goodput; goodput under SLO, with the SLO fixed at 10× the idle p99; p50, p99 and p99.9; drops at each layer; CPU per packet on each core; rung switches per second.

| Figures | Workloads | Policies | Load points | Platform | Reps | Runs | Week |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1–3 | W1, W2 | P0–P4, plus P0 with the consumer on another core | 6, from 0.25 to 2.5 × knee | Genoa | 3 | \~110 | 1 |
| 4 | W1 at 64, 512 and 1400 bytes | P0, P3, P4 | 6 | Genoa | 3 | \~160 | 2–3 |
| 5 | W5: ramp, bursts, step | P0, P2, P4, P7 | 3 patterns, 180 s each | Genoa | 3 | 36 | 4 |
| 6 | W1, W2 | P0, P2, P3, P4, P7 | 8 | Genoa | 3 | 120 | 4 |
| 10 | W1 | P0, P2, P4 | 6 | Intel r650 | 3 | 54 | 4 |
| 7 | W3 | P0, P1, P2, P4, P5, P6, P7 | 8 | Genoa | 3 | 168 | 5–6 |
| 8 | W4 | P0, P2, P5, P7 | 4 flood rates | Genoa | 3 | 48 | 7 |
| 9 | W1 on 8, 16 and 32 queues | P0, P2, P7 | 3 queue counts | Genoa | 3 | 27 | 7 |
| Final | The decisive cells of Figures 1, 6 and 7 | As above | As above | Both | 5 | \~150 | 8 |

P1 needs a reboot into the older kernel, so batch every P1 run together.

## Outline and page budget

Twelve pages, NSDI format; the introduction is drafted the week Figure 1 exists.

| Section | Pages | Content | Carries |
| --- | --- | --- | --- |
| 1 Introduction | 1.5 | The regression, the trade-off, the trick, the headline results | Fig. 1 |
| 2 Background | 1 | NAPI, softirqs, threaded NAPI, the 2016 change and the 2023 revert | Table 1 |
| 3 The trade-off on modern hardware | 2.5 | The collapse, the latency cost, where cycles go, the knee model | Figs. 1–4 |
| 4 Design | 2 | The ladder, predicting each rung's capacity, switching without flapping | — |
| 5 Implementation | 0.5 | A user-space controller over netlink and CPU affinity | Table 2 |
| 6 Evaluation | 3 | Against static policies, memcached, floods, many queues, the Intel platform | Figs. 5–10 |
| 7 Discussion | 0.5 | Scope for TCP, power states, other NICs, upstreaming | — |
| 8 Related work | 1 | One paragraph per neighbor | — |

## Related work

Every neighbor gets one sentence that says what we do differently and which figure shows it matters.

- **Receive livelock** ([Mogul and Ramakrishnan, TOCS 1997](https://pdos.csail.mit.edu/6.828/2026/lec/l-net.txt)) was fixed with polling and feedback. We show its modern form returned with the 2023 revert, and add placement as the lever (Figs. 1, 4).
- **Linux's 2016–2023 deferral** ([2016](https://lwn.net/Articles/698807/), [2023 revert](https://lkml.iu.edu/hypermail/linux/kernel/2305.1/02264.html)) triggered on ksoftirqd activity and split the same core. We trigger on predicted capacity and move work off the application's core (Figs. 1, 5, 6).
- **Threaded NAPI** ([2021](https://lwn.net/Articles/833221/); [per NAPI, 2025](https://lists.openwall.net/netdev/2025/02/05/4)) supplies the mechanism. We supply the policy: when to thread, and where to place the thread (Figs. 5, 6).
- **IRQ suspension and busy polling** need application changes and spend CPU while polling. The ladder needs neither (Fig. 7).
- **Snap, NetChannel, Shenango and Caladan** ([Caladan](https://usenix.org/conference/osdi20/presentation/fried)) grow and shrink packet-processing cores in new stacks or bypass runtimes. We use the stock kernel stack and its stock interfaces (Table 2).
- **NMAP and GSIM** ([NMAP](https://par.nsf.gov/servlets/purl/10395074), [GSIM](https://lkml.iu.edu/hypermail/linux/kernel/2601.1/09052.html)) coordinate frequency or interrupt rate with network processing. We decide where receive work runs.
- **Hanford et al. and Cai et al.** ([2013](https://www.es.net/assets/pubs_presos/ndm2013-paper1Hanford.pdf), [SIGCOMM'21](https://www.cs.cornell.edu/~ragarwal/pubs/network-stack.pdf)) each measured one side of the co-location trade-off. We show both sides on the same hardware and predict the boundary (Figs. 1, 4).
- **Zuo et al.** (SIGCOMM'26) fix scheduling among threads sharing one core. We decide which core receive work shares.
- **Nous** ([LSF/MM/BPF 2025](https://bpfconf.ebpf.io/bpfconf2025/bpfconf2025_material/Nous%20-%20LSFMMBPF%202025.pdf)) proposes BPF mechanisms for where and when packet processing runs. The ladder is a policy those mechanisms could host.

## How to use this skeleton

The skeleton is the contract between the runs and the paper: it changes only when a figure's result changes.

1. **Every spec names its figure.** A run that feeds no figure needs the PI's approval first.
2. **After each result note,** set the figure's status, and replace its placeholder in the abstract with the measured number and interval.
3. **Draft the introduction the week Figure 1 exists,** and rewrite the abstract whenever a figure moves to Draft or Final.
4. **If a figure's claim fails, don't bend the story.** Mark it Dropped, record a decision, and change the claim list.
5. **The Friday memo's figure of the week comes from this list.**

## Placeholder fills (contract rule 2)

| Placeholder | Figure | Value | Filled |
| --- | --- | --- | --- |
| \[X\]% of the offered load | Fig. 1 | 0.20% goodput share at 2x knee (95% CI 0.20-0.20, n=2; 1300k: 0.13% [0.05, 0.21]) | 2026-09-24 |
| \[Name\] | Fig. 5 | candidate: the p1ctl.py ladder controller (name TBD with PI) | — |
| \[N\]-line controller | Table 2 | p1ctl.py = 157 lines as built | — |
| \[Y\]% of inline latency at low load | Figs. 6–8 | pending | — |
| \[Z\]× the default's goodput | Figs. 6–8 | pending | — |

## Session-added notes (outside the PI text)

- W2 was implemented with k4send/k2_rx --echo (k3mot's rig role), same
  wire format; recorded in specs/p1-LADDER.md.
- AN-003 (threaded-NAPI lost-wakeup wedge) discovered 2026-09-24: Fig. 1
  must carry wedge markers for P3/P4 at >=790k and the model needs a
  wedge-probability column; Fig. 5's ladder must survive or avoid it.
- Fig. 10 is blocked by the allocation (6x Genoa r6615, no Intel r650).
- 2026-09-24 dataset-complete headline: the separation that drains under
  flood is P0X (app moved, processing inline): 97.5%/74.2% of offered at
  1.5x/2x knee vs the default's 9.0%/0.2%; the threaded rungs wedge
  (C-008) and sit at 0-36% there. DR-001 (proposed) revises Fig. 1's
  claim accordingly -- rule 4, PI's call.
