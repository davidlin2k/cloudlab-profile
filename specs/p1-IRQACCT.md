# Spec p1-IRQACCT: the IRQ-time-accounting decisive experiment

Pre-registered 2026-09-25 (UTC), BEFORE any run, per the standing rules
("Pre-register before running. A spec change after runs start is a new
version"). Authorized by DR-005 ("Decisive experiment (1-2 days)").
Method chosen 2026-09-25 by [student]; every deviation becomes v2.

## What is approved (DR-005, verbatim)

Rebuild 6.17.8 with CONFIG_IRQ_TIME_ACCOUNTING=y. Pre-register:

| Question | Prediction |
| --- | --- |
| Does /proc/stat see the work? | The 166x gap closes to within 2x of the performance counters |
| Does thread accounting change? | Thread-level time stops absorbing receive work |
| Does the scheduler avoid the interrupt core? | With an unpinned consumer under flood, it moves the consumer off core 8 and avoids the collapse |

## Platform and run

- Kernel: the platform kernel (6.17.8-061708-generic, mainline) rebuilt
  from the 6.17.8 source with the running config as base and exactly one
  change: CONFIG_IRQ_TIME_ACCOUNTING=y (verify .config diff shows only
  that line and its dependents).
- Source check first (DR-005): grep -n HAVE_SCHED_AVG_IRQ init/Kconfig;
  record whether it depends on IRQ_TIME_ACCOUNTING.
- Baseline = the existing measurements on the current kernel
  (AN-007 for the /proc/stat gap; the matrix's thread accounting; the
  AN-005/AN-006 unpinned-sender runs for the placement behavior).

## The three runs (one per prediction)

1. `/proc/stat` versus performance counters on the interrupt core under
   the W1 flood at 390k (the AN-007 protocol, same window): record
   core 8 busy seconds from /proc/stat and from perf per-CPU counters.
   Pass: the ratio is within 2x. (Baseline: 166x.)
2. Thread accounting on the same cell: schedstat thread time against the
   PMU-basis per-packet cost (the Fig. 3 pipeline). Record what share of
   receive cost thread-level time absorbs now. (Baseline: 43-55%.)
3. Unpinned consumer under flood (the AN-005/AN-006 unpinned protocol):
   record the consumer's placement (which core it runs on), whether it
   leaves core 8, and delivered goodput vs the offered rate at 2x knee.
   Pass: the consumer moves off core 8 and the collapse is avoided.

## Interpretation rule (DR-005, verbatim)

If the scheduler then avoids co-location, "visibility-aware placement"
already exists behind a config option most kernels don't set. If it does
not, this becomes the baseline the November 13 prototype must beat. Facts
first; the note records measurements and states the outcome of each
prediction; no mechanism explanation beyond DR-005's own.
