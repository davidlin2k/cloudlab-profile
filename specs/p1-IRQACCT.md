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

v1.1 (2026-09-25, amended BEFORE any run): the experiment is a MATCHED
PAIR of local rebuilds of 6.17.8 from the same source and the same build
host toolchain -- one with the platform config (/boot/config-6.17.8-
061708-generic) as base (LOCALVERSION=-base) and one with exactly one
substantive change, CONFIG_IRQ_TIME_ACCOUNTING=y (LOCALVERSION=-irqacct).
The pair isolates the config: the build-host toolchain differs from the
Ubuntu build of the platform kernel (gcc 15.3.0 against 15.2.0, binutils
2.42 against 2.45, and the RUST options drop in both trees), but it is
identical across the pair, so the flip is the only variable. Verified
diff of the two trees' .configs: only `# CONFIG_IRQ_TIME_ACCOUNTING is
not set` -> `CONFIG_IRQ_TIME_ACCOUNTING=y` plus the dependent
`CONFIG_HAVE_SCHED_AVG_IRQ=y`.
- Source check (DR-005, recorded 2026-09-25 before the build):
  init/Kconfig:585: config HAVE_SCHED_AVG_IRQ -- depends on
  IRQ_TIME_ACCOUNTING || PARAVIRT_TIME_ACCOUNTING. The PI's expectation
  holds: without IRQ_TIME_ACCOUNTING there is no scheduler IRQ pressure
  view.
- Reference measurements (the paper's established numbers) stay the
  platform kernel's: AN-007 (the /proc/stat gap), the matrix's thread
  accounting, AN-005/AN-006 (the placement behavior). The pair tests the
  predictions against its own -base arm first.

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
