# p1-T1C: the workaround bound (DR-013 item T1c), pre-registered

Frozen 2026-09-27 (~1x:xxZ) BEFORE any run. Source: decisions/DR-013.md
T1c, verbatim. Runs AFTER the T1a instrument is developed but the
cells themselves need only the existing harness, so the 12 cells run
detached while the T1a instrument is built (one run at a time on the
node; no T1a cell starts until these finish).

## The cells

12 more same-L3 (pin10) cells on clnode366: PT10-9..PT10-20, the
MIGRATE/LOCALITY harness unchanged (the task-1 M158 protocol,
TRACE=1 + the readiness probe, the SWEEP wiring with SWEEP_CPU=10,
migrate_run.sh). Same flood and duration as p1-LOCALITY. The pin10
verdict rule is the summarize wedge rule (a 200 s continuous
ready-unserved wedge) as used for PT10-1..8.

## The decision rule (frozen, the memo's)

0/8 (PT10-1..8) only bounds the stall rate below 37%;
0/20 bounds it below about 14%. The bug report's workaround
sentence needs the latter. If ANY of the 12 new cells wedges, the
bound is computed from the combined 20 cells and recorded as-is
(no curve, no theory).

## The second T1c item (no node time)

Read the ConnectX-6 (MT28908) firmware release notes for versions
after 20.43.3608 for any EQ, CQ or event fix, and record the
result facts-only in notes/p1-T1C-fw-notes.md. DO NOT flash
firmware on CloudLab nodes.

## Deliverable

The bound enters D1's workaround sentence. Counts go into
notes/p1-CLOSEOUT.md and the D2 section-6 rewrite (facts only).