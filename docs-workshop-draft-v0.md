# Invisible Receive Work: What Linux Pays for It Under Overload

Draft v0, 2026-09-25 (the full draft gate is Oct 9; this pulls it ahead
for the PI review). Internal until approved. Every sentence with a number
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

## 6. The threaded-NAPI stall

Survival curves (Fig. 4): under per-device threaded NAPI, 25 of 48
matrix cells and 24 of 24 unpinned-sender cells stall (the unpinned case
is the fastest: 8 of 8 runs stall, onsets 9-19 s) [p1-LADDER.2, AN-006].
What we ruled out: the mlx5 IRQ affinity "polling after interrupt"
bailout is not sufficient -- the pre-registered A/B (affinity 0,0 vs
default) wedged on its own criteria at 790k in both arms of every
placement (12 of 12), so adaptive-rx and interrupt coalescing are not
necessary for the stall either [C-010, AN-005, AN-003]. Status: the
onset and recovery timelines have been delivered as facts
(checkpoints/2026-09-25-wedge-timelines); interpretation is held for the
PI's read of the timelines, and the draft of a netdev report exists but
is not public.

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
| 1 | goodput against load | analysis/p1_figures.py | Draft |
| 2 | the blind standard metric; corrected costs predict the knee (UDP) | analysis/p1_fig_model.py | Draft |
| 3 | wake-delay distributions | analysis/p1_fig_wakedelay.py | Draft |
| 4 | wedge survival curves | analysis/p1_fig_wedge.py | Draft |

## Review flags (do not ship without the PI's call)

- C-004 and C-006 are Pending in the ledger; their sentences cite finding
  IDs per the rule. Promote at review or cite findings only.
- C-007 re-promotion (its revised numbers appear in sections 1 and 4).
- The W3 TCP outcomes (the kill criterion, the failed predictions) have no
  section in the memo's plan; they appear here only as section 5's TCP
  numbers. Add or drop?
- Section 6's text and Fig. 4 are internal until the netdev report is
  approved.
