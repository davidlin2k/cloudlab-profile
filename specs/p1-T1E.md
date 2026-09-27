# p1-T1E: the workaround as a fix (DR-013 addendum T1e), pre-registered

Frozen 2026-09-27 (~2x:xxZ) BEFORE the run. Source: decisions/DR-013.md
addendum T1e, verbatim. 3 days, AFTER T1d. Base: the net-next tree
built in T1d (the patch applies there and to 6.18.y if needed).

## The patch

p1/t1e-napi-thread-cpumask.patch (draft in the repo): at the single
thread-creation choke point (napi_kthread_create, net/core/dev.c),
default the threaded poller's cpumask to the L3 siblings of its
vector's effective affinity (single-cpu effective affinity only).
Re-applied on every (re)creation -- the reset-destroys-the-thread
gap the June 2026 RFC discusses. No napi_config interaction.

## The pre-registered prediction

The addendum: "Pre-register the prediction first. The only prior is
pin10's 0/8." -- PREDICTION: the patched UNPINNED arm stalls 0-1/8
(the thread defaults to the IRQ core's L3 siblings; same-L3 pinning
measured 0/8 twice, 0/20 with T1c), i.e. the patch reproduces the
workaround without any userspace pinning.

## The run

The UNPINNED arm (the MA wiring -- unpin; the arm that stalled 8/8
in AN-006 and 4/8 in MIGRATE-2 v2), n = 8, cells T1E-1..8, the
standard probe + classify join, on the patched kernel (built after
T1d; the current-kernel runs in T1d provide the unpatched current
comparison).

## The decision rule (the addendum, verbatim)

- 0-1/8 -> send the patch with the report as an RFC.
- >= 3/8 -> placement alone doesn't fix it; drop the patch, keep
  the data.
- 2/8 is the memo's implicit gap: record it and ask the PI.

## Deliverable

notes/p1-T1E-1.md (counts only): the arm's wedge count, the
classification, and the patch's cpu placement check (the poller
threads' cpus from the cpu histograms -- the patch must place ch7's
thread in {8-11, 40-43}).