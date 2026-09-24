# Introduction — draft 1 (2026-09-24)

NSDI 12-page format, 1.5-page budget; carries Fig. 1. Numbers are from
the Fig. 1–3 draft set (checkpoints/2026-09-24-fig1-3-draft.md); each is
final when its figure is Final. Editor's notes in [brackets] mark
claims awaiting a figure's adjudication.

---

Since Linux 6.5, the default receive path no longer protects
applications from receive overload. When a flood arrives on a queue
whose interrupt core the application shares with it, the application
receives 0.2% of the offered load (95% CI 0.20–0.20, at twice the rate
the host can sustain) on a modern 32-core server [Fig. 1]. Not "degrades
gracefully." Not "loses some packets." The application's goodput
collapses to noise while the machine spends every cycle it has on the
packets it cannot deliver. Receive livelock, exiled from kernels thirty
years ago by polling and backoff [Mogul and Ramakrishnan 1997], came
back the moment Linux stopped deciding where receive work runs.

Linux has, in fact, decided this twice. From 2016 to 2023 it deferred
packet processing to ksoftirqd whenever softirq work piled up, splitting
the same core between the application and the network stack [Table 1].
The deferral protected application progress — the original commit
reports the receive path going from 2 Kpps to 900 Kpps under load — at
the price of latency and, as we show, of a capacity cap near half a
core. In 2023 the mechanism was reverted: modern kernels process
packets inline again, for latency, and give up the protection. Both
policies are global, static, and chosen at compile time. Each fails in
one regime: inline collapses past the knee; deferral caps throughput and
taxes every round trip [Figs. 1–3].

We argue the choice is neither global nor static. It belongs to each
queue, at runtime, and the right answer is not "when to defer" but
"where to run." Under receive load, separate network processing from
the application before a predictable knee, instead of deferring it on
the same core after overload is detected. Separation is available today
on stock kernels: per-NAPI threaded mode lets each queue's NAPI work
run in its own kernel thread, and that thread can be placed anywhere.
The application keeps its core; the network gets one. Nothing is
deferred, so nothing pays the deferral's latency tax: at low load with
full delivery, a separated host answers in a p50 of 11.5 µs where the
co-located default answers in 108.5 µs — 9.4× — and at overload it
drains where the default starves [Figs. 1, 2].

The question a queue must answer is when to separate, and for that we
need the knee. Each placement — inline, threaded on the application's
core, on its SMT sibling, on another core — has a collapse point set by
two measured per-packet costs, the application's and the network's,
plus the SMT slowdown for the sibling rung [Fig. 4]. [EDITOR'S NOTE:
Fig. 4 is under adjudication (2026-09-24 checkpoint): the two-cost
model misses the 64-B knees by more than its stated 25% on current
rows, and the miss tracks the below-socket drop path and a
threaded-NAPI failure mode the model does not include. If the miss
holds on clean cells, this paragraph's claim is cut to the measured
costs and the drop-path bound, per skeleton rule 4.] Wherever the knee
sits, it can be bracketed from in-situ per-packet costs that a
controller measures on the live queue without instrumenting the kernel.

[Name], a [N]-line controller built only on stock kernel interfaces,
does exactly this: it predicts each queue's knee and moves its NAPI
processing from the application's core to its SMT sibling and then to
another core before the knee is crossed [Fig. 5]. The ladder is
predictive rather than reactive — placement changes land before
collapse, because after collapse the controller's own measurements are
stale — and it switches with hysteresis, so a queue that hovers at its
knee does not flap. On UDP floods and on memcached, [Name] stays within
[Y]% of inline processing's latency at low load and sustains [Z]× the
default's goodput under overload [Figs. 6–8], across queue counts
[Fig. 9] and on a second server platform [Fig. 10].

This paper makes four contributions:

1. **Characterization** (Figs. 1–3). The receive-overload trade-off
   measured on a modern chiplet server across kernel policies, before
   and after the 6.5 revert, and across placements — including where
   the cycles actually go: at the collapse point the scheduler's
   per-thread accounting hides 26–42% of the application's core.
   We also identify and characterize a failure mode of threaded NAPI
   itself: under flood, a queue's NAPI thread can lose its wakeup and
   stall the queue permanently, dropping the offered load at the ring
   [AN-003; wedge markers in Fig. 1].

2. **Model** (Fig. 4). Each placement's collapse point from two
   measured per-packet costs and the SMT slowdown. [Under
   adjudication — see editor's note above.]

3. **Design** (Fig. 5). A predictive placement ladder on stock
   per-NAPI threaded mode: the application's core, then its SMT
   sibling, then another core.

4. **Evaluation** (Figs. 6–10). UDP and memcached, floods, bursts and
   many queues, on two platforms, against every static policy, IRQ
   suspension and busy polling.

---

Notes for the next pass (not paper text):

- Fig. 1 exists as Draft: intro drafted per contract rule 3. Rewrite
  the abstract and this draft whenever a figure moves to Draft or
  Final (rule 3).
- [X], [Name], [N], [Y], [Z] mirror the skeleton's placeholder fills
  table; [X] is now filled there (0.2%), the rest await Figs. 5–8 and
  the PI's naming call.
- The 0.2% figure's operating point is twice the measured knee (P0,
  64-B UDP incast, five senders to one queue). If the final knee moves
  (fig1-3c re-runs), the sentence's parenthetical changes, not the
  number's spirit: the number is "the application is cut off."
