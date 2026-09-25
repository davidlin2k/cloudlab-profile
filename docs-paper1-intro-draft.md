# Paper 1: introduction (draft)

Drafted per the skeleton's rule 3 ("Draft the introduction the week
Figure 1 exists"; Fig. 1 has been Draft since 2026-09-24). NSDI full
paper, twelve pages. Internal until the PI review.

---

## 1. Introduction

A general-purpose kernel runs a server's networking in two books. The
first is the application's own threads: their CPU time is visible to the
scheduler, to accounting, and to the application. The second is receive
work -- softirq, NAPI, and driver execution -- which runs outside any
thread the application owns. The second book is invisible and expensive.

It is expensive in three measured ways. Under a flood on a queue whose
interrupt core the application shares, the application receives 0.2% of
offered load at twice its knee [F-p1-LADDER-1; Fig. 1]. Per-thread
accounting hides 26-42% of the application core's cycles near that
collapse [F-p1-LADDER-3; Fig. 3], so a capacity model built from thread
time alone over-predicts the knee by 53% [p1-LADDER.4; Fig. 4]. And
request-path wakeups queue behind the same work: 34-60 us of scheduler
wait where separated placement costs 4 us under UDP, and 47 us against
3 us under TCP [p1-LADDER.2, p1-LADDER.6; Fig. 2].

Linux has switched global policies in this space twice: inline
processing for latency, then deferral to kthreads for protection, and
6.5 returned to inline by default. Each policy fails in one regime. The
failure is not an accident of scheduling; it is a placement problem. When
the receive side and the application share a core, invisible work eats
the application's capacity and delays its wakeups; when they are
separated, the receive side becomes the interrupt bottleneck at its own
measured ceiling (~1.2 us per packet on our NIC) but the application is
protected [p1-LADDER.1].

This paper makes three claims. (1) Collapse: inline co-location collapses
past a knee and deferral caps near half a core, while separation drains
more [Figs. 1-3]. (2) Model: each placement's collapse point is
predictable from two measured per-packet costs, once the hidden softirq
share is corrected -- 2.8% and 6.2% miss at 64 B [Fig. 4]. (3) Design: a
predictive placement ladder built on stock per-NAPI threaded mode -- the
application's core, then its SMT sibling, then another core -- moves the
receive side before the knee [Fig. 5].

The measurement platform is Linux 6.4 (backported per-NAPI threading) on
a 32-core AMD Genoa server with a ConnectX-6 Dx, one RSS queue, five
sender nodes, and three workloads: a UDP incast flood, UDP request and
response for latency, and memcached under mutilate (open loop, 90% GETs).
Every figure comes from a script in analysis/; every run maps to a figure
in the skeleton.

Two findings bound the story honestly. The threaded-NAPI stall -- 25 of
48 matrix cells and 24 of 24 unpinned-sender cells stall under
threaded NAPI [p1-LADDER.2, AN-006] -- has timelines but no root cause
yet, and its report is held for the PI. And under TCP the collapse does
not cross: memcached plateaus at 169% and 194% of the knee's goodput
rather than collapsing (the transport-independence claim is Dropped per
the skeleton's rule 4, C-016); what crosses to TCP is the co-location
cost and SLO degradation [Fig. 7].

Roadmap: Section 2 ... Section 3 (collapse, Figs. 1-3) ... Section 4
(model, Fig. 4) ... Section 5 (design, Figs. 5-6) ... Section 6
(memcached and robustness, Figs. 7-9) ... Section 7 (related work) ...
Section 8 (discussion: the stall, other NICs, upstream).
