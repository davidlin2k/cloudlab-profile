# Invisible Receive Work: What Linux Pays for It Under Overload

Draft v1, 2026-09-29 (supersedes v0, 2026-09-25; the full draft gate is
Oct 9). Applies the DR-013 decisions on the four v0 review items:
claims cited per DR-005, the "What TCP does not carry" paragraph added,
section 6 rewritten to current facts (C-019 through C-023, T1a/T1b),
title confirmed. Internal until approved. Every sentence with a number
cites a finding ID per DR-004; figures are Draft (scripts in analysis/).

## Abstract

On a general-purpose kernel, receive work runs outside any thread the
application can see, and three measured costs follow. First, throughput
collapses: at 1.5x the knee, co-located admission loses 90.9% of offered
load and loses 99.8% at 2x [F-p1-LADDER-1]. Second, models built from
thread accounting are wrong by exactly the invisible work: a knee model
from two measured per-packet costs misses by 53% and falls to 2% once the
hidden softirq share (h = 33%) is corrected [p1-LADDER.4]. Third, wakeups
wait behind the same invisible work: request-path wake delays run
34-60 us co-located against 4 us separated under UDP and 47 us against
3 us under TCP [p1-LADDER.2, p1-LADDER.6]. We report a measurement study
of receive-work placement on Linux 6.4 (AMD Genoa, ConnectX-6 Dx), with
the interrupt core as separation's measured ceiling and the threaded-NAPI
stall as its open question.

## 1. Introduction

Networking costs appear in two books. The application's thread time is
visible to it; the softirq, NAPI, and driver work that delivers its
packets is not. This paper measures what the second book costs when the
two are kept on one core, and what separation buys.

Three costs are measured directly. The collapse: co-located admission
delivers 9.0% of offered at 1.5x the knee and 0.2% at 2x, while moving
only the receive side to another core delivers 97.5% and 74.2%
[F-p1-LADDER-1]. The model error: per-thread accounting hides 26-42% of
the app core's cycles near the collapse region (mean 33%) [F-p1-LADDER-3],
so a capacity model built from thread time alone over-predicts the knee by
53% [p1-LADDER.4]. The wake delay: when a request arrives on the same
core as its waiter, the waiter runs tens of microseconds late (34-60 us
under UDP, 47 us under TCP) against 3-4 us when the receive side is
separated [p1-LADDER.2, p1-LADDER.6].

The contributions are (1) a controlled collapse curve on stock Linux with
policy-level separation at the device queue [p1-LADDER.1]; (2) the hidden
share of receive work, measured two ways, and its correction to a knee
model that then lands within 2% and 9% of the measured knee at 64 B
[p1-LADDER.3, p1-LADDER.4]; (3) wake-delay distributions over 1.2 million
wake events attributing the co-location penalty to scheduler wait behind
receive processing [p1-LADDER.2, p1-LADDER.6]; and (4) the threaded-NAPI
stall: 25 of 48 matrix cells and 24 of 24 unpinned-sender cells stall
under threaded NAPI, with the mlx5 poll-affinity bailout ruled out by a
pre-registered A/B [p1-LADDER.2, AN-006, C-010].

## 2. Background

NAPI polls the device from interrupt context (softirq) or, since 5.12,
optionally from a per-device kthread ("threaded NAPI"); the 2016 IRQ
affinity work and the 2023 NAPI-threaded-by-default discussion changed
where that work runs but not who accounts for it. Receive processing
therefore executes in a context that carries no application task identity:
scheduler wait, CPU time, and cache footprint are attributed to a kthread
or to nothing at all.

## 3. Collapse and separation

Goodput against offered load, five senders into one RSS queue (Fig. 1):
inline co-location collapses past the knee (9.0% delivered at 1.5x,
0.2% at 2x, 95% CI +/- 0.1, n = 2) while separated admission holds
97.5% and 74.2% (95% CI 96.8-98.2 and 69.8-78.0, n = 3)
[F-p1-LADDER-1]. The lower-cost UDP request path collapses identically:
27% delivered at 1.2x under co-location [p1-LADDER.2].

Separation has a measured ceiling. At the highest sustained rate the
interrupt core sits at 100% busy at ~1.2 us per packet while the
application core runs ~85%: once the receive side saturates its own core,
the trade becomes the old interrupt-core bottleneck [p1-LADDER.1]. The
knee the model predicts is the load where that first happens; the
0.5x-margin projection of the design section follows from it (55-65%
projected margin) [p1-LADDER.4].

## 4. Invisibility makes models wrong

CPU time per packet, by core and by thread (Fig. 2a): the standard
metric is blind to receive work. /proc/stat attributes 0.6% of it to
the interrupt-only core (0.22 s of stat CPU against 36.53 s of
PMU-measured receive work; a 166x undercount) [AN-007, C-014], and
per-thread accounting (schedstat) sees 43-55% of the app core's
receive cost across placements [F-p1-LADDER-3, C-006]. Only the
PMU-basis corrected metric sees the whole per-packet cost, and that is
the quantity the knee model needs.

The model makes the cost concrete. From the corrected per-packet
costs (app and net), the co-located knee is F = 1e9 / (c_app + c_net)
and the separated form splits the terms across the two cores -- no
fitted constant anywhere. At 64 B the UDP predictions land within 2.8%
(co-located: 451.0k predicted against 438.6k measured) and 6.2%
(separated: 767.0k against 818.0k) [p1-LADDER.4]. On TCP the same
constant-cost form fails, exactly where cost depends on load: it
under-predicts the measured knees 3.06x and 3.16x (62.0k/82.4k
predicted against 190k/260k measured) [C-017]. Standard tooling cannot
see the quantity the model needs: the corrected metric is not
optional.

## 5. Invisibility makes wakeups wait

Wake-delay distributions (scheduler wait after wakeup), 1.2 million wake
events (Fig. 3): under UDP the request path wakes in 34-60 us co-located
against 4 us separated; under TCP the memcached worker wakes in 47 us
co-located against 3.2 us separated [p1-LADDER.2, p1-LADDER.6]. The
tails follow the same split: 1242-3502 us co-located against 892-906 us
separated under UDP, 791 us against 1088 us under TCP (the separated
TCP tail is scheduler-tail, not receive work). The NAPI kthread wakes in
3 us in both placements: the delay attaches to the request path, not to
the kernel's own receive thread.

What TCP does not carry. The collapse does not survive TCP: at 2x the
knee, TCP admission delivers 169% (co-located) and 194% (separated) of
knee goodput -- a capacity plateau, not the UDP cliff -- so the flow-
control kill criterion fires and the UDP collapse is transport-
specific [C-016]. The corrected-cost knee model also fails on TCP,
missing the measured knees 3.06x and 3.16x: TCP's per-request receive
cost depends on load (16.1 us at 20k to 3.3 us at 300k), so the
constant-cost form is UDP-scoped [C-017]. And TCP's co-location latency
tax does not multiply: the p99 ratio at the knee is 1.45x, not the 5x
the UDP wake-delay magnitudes would suggest [C-018]. What TCP does
carry is separation's service benefit: at 1.5x the knee, separated
admission holds SLO fraction 0.999 against 0.829 co-located with p99
645 vs 1475 us [C-015]. Reporting the refutations is part of the
result: the invisible-work accounting applies to the transport where
receive work is the bottleneck, and its limits are measured, not
assumed.

## 6. The threaded-NAPI stall

Survival curves (Fig. 4): under per-device threaded NAPI, 25 of 48
matrix cells and 24 of 24 unpinned-sender cells stall (the unpinned case
is the fastest: 8 of 8 runs stall, onsets 9-19 s) [p1-LADDER.2, AN-006,
C-011]. What we ruled out, in order: the mlx5 IRQ affinity "polling
after interrupt" bailout is not sufficient -- the pre-registered A/B
(affinity 0,0 vs default) wedged on its own criteria at 790k in both
arms of every placement (12 of 12), so adaptive-rx and interrupt
coalescing are not necessary for the stall either [C-010, AN-005,
AN-003]; the driver's stop-and-rearm placement-correction path is not
the cause -- under a forced 10<->46 core hop, 27% of stranded-gap
onsets begin within 2 ms of an observed migration (null: 2/100) and
63% of post-gap samples sit on the destination core, but the causal
contract/restart-strategy arm came back 0/8 with the pin verified, so
the migration-race mechanism is refuted [C-019, notes/p1-CAUSAL-1];
the arm_sn stale-doorbell race is not the cause -- the device accepts
the arm (doorbell record == frozen counter through every gap) and then
raises no completion event while the queue sits ready (0 stale
candidates in 67 stranded gaps) [C-020]; and the stall is not a
distance gradient -- it is specific to the IRQ core's CCX-sibling
pair: 0/8 (same L3) < 5/8 (far NUMA) < 8/8 (adjacent CCX), burden
ordered 0.5 < 7.75 < 33.5 s per cell [C-021]. Placing the poller
inside its IRQ's L3-sibling cluster does not fix it: with the patch
mechanism verified live, the unpinned arm still wedged 5/8 [C-022].
The stall is unfixed on current code: 8 of 8 wedged on 6.18.9+ and on
net-next 7.3.0-rc4+ [C-023].

The stall is a characterized, unexplained liveness failure with a
placement workaround (keep the poller and its IRQ off the adjacent-CCX
pair, or pin both to one core). It is not mlx5-specific in the driver
sense that would make it a one-vendor bug: the same protocol run on an
i40e / Intel Xeon platform (X710, 2x16c Gold 6142) shows 0 of 8
stranded in every arm -- SMT sibling of the IRQ core, same-socket,
other-socket, and unpinned -- with the descriptor-level readiness
detector armed in every cell [C-025]; the NIC and CPU platform changed
together, so the cross-check narrows the mechanism to the
mlx5/AMD-generation combination rather than to threaded NAPI at large.
The device-side evidence (the accepted arm and the missing completion
event [C-020]) and the vendor report are held for the PI's approval
before anything is public.

## 7. Agenda

Two directions follow. Visibility-aware placement: if the kernel exposed
per-NAPI CPU attribution to the scheduler and to cpuset placement, the
ladder (app core, then SMT sibling, then another core) could move the
receive side on predicted capacity, and the model's corrected knee is
the switch point [p1-LADDER.4]. Upstream work: the threaded-NAPI stall
needs a public report with the timelines attached, once the PI approves.

## Related work

Mogul and Ramakrishnan (1997) established that softirqs run at interrupt
time and can starve processes; Iron (NSDI'18) showed kernel-bypass NIC
services changing these trade-offs; threaded NAPI's rationale (2021)
argues for the kthread placement we test; Brouer (2023) tracks the
XDP/NAPI roadmap; Zuo et al. (SIGCOMM'26) study XDP stalls that resemble
our wedge.

## Figures

| Fig | shows | script | status |
|---|---|---|---|
| 1 | goodput against load | analysis/p1_figures.py | Draft (QA pass) |
| 2 | the blind standard metric; corrected costs predict the knee (UDP) | analysis/p1_fig_model.py | Draft (QA pass, v2 per DR-005) |
| 3 | wake-delay distributions | analysis/p1_fig_wakedelay.py | Draft (QA pass) |
| 4 | wedge survival curves | analysis/p1_fig_wedge.py | Draft (QA pass) |

Final-figures pass due Oct 6 (DR-013): re-run all four scripts against
the current rows CSVs, confirm the section 4 anchors reproduce
(app 906-1407 ns, real 2026-2935 ns, thread 43-55%, /proc/stat 0.60%),
and re-QA annotations.

## Review flags (resolved per DR-013, kept for the record)

- v0 items 1-2: claims cited per DR-005 (C-004 as written, C-007 at
  2.8%/6.2% UDP 64 B, C-006 superseded to 43-55% / 0.6%).  Only
  Supported claims appear; the ledger rows are current.
- v0 item 3: resolved -- the "What TCP does not carry" paragraph is in
  section 5 (C-016/C-017/C-018 refutations + C-015's surviving
  benefit).
- v0 item 4: title confirmed (the memo's).
- OPEN (DR-014 hold): section 6 names the vendor-report hold; nothing
  public until the PI approves after the re-arm/watchdog rows land.
- Section 6's Fig. 4 remains the wedge A/B matrix; the T1e/T1d/T1b
  placement arms are cited in text, not plotted (one figure per
  measured matrix remains the rule).
