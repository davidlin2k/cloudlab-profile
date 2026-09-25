# 2026-09-25 -- DR-005 operative; task 1 smoke + batch in flight

## Direction (DR-005, committed operative)

The PI memo redirects the program to the wedge/metastability
contribution (starved-ring self-sustaining loop; if the queue stays
dead after the load drops, a metastable failure inside the kernel's
receive path). Earlier results become motivation. The older PI review
is preserved as decisions/DR-005-pi-review.md. Paused per the memo:
the IRQ-time-accounting rebuild (builds killed, trees kept), DNS, XDP
admission, workshop writing (resumes after task 1's verdict).

## Task 1 (the metastability test)

- specs/p1-METASTABLE.md frozen before any run (arms, floods, the
  wdiagtrace wedge detector unchanged, outcome classes verbatim).
- p1/metastab.sh (the memo's five exact changes), p1/metastab_eval.py
  (rows + the pre-registered class), p1/metastab_batch.sh (5 rounds,
  interleaved) -- all committed before running.
- Smoke (DR-005 rule: smoke before any batch):
  - B316 (baseline): PASS -- cell.env, counters.log at 1 Hz, exactly
    one verdict (RECOVERED at +6 s), PROBE-OK adv=300,099.
  - M316: WEDGE at +20 s (rx7 frozen at 12,305,689,984, oob rising),
    REDUCE to 316k at +31 s, verdict NOT-RECOVERED-120s, probe
    PROBE-DEAD adv=0. Mechanism snapshot files captured (the
    devlink rx diagnose returned 'kernel answers: Invalid argument'
    -- recorded in the cell; the fw reporter's diagnose works, so the
    syntax is right and the kernel's rx handler refuses on this
    platform; debugfs CQs expose no producer/consumer indices).
- Step-4 reset saga (reported to the PI per "any queue that needed a
  reset, reported immediately"): the dead queue survived the threaded
  0->1 toggle (probe adv=0) and `ethtool -L combined 32` + full
  pre-flight (adv=0) while the wire was provably alive (+790,177
  rx_packets_phy in one probe window, delivered to no queue). It
  revived only after a genuine channel recreation (32->16->32) +
  pre-flight (probe adv=80,067). Correction recorded: rx7_packets
  does NOT zero across channel recreation, so the "first reset was a
  no-op" inference is withdrawn -- evidence is probe behavior only.
  Logs: M2-1/step4-reset.log, step4-reset2.log.
- My script bug found and fixed mid-batch: metastab.sh's trailing
  bare `wait` hung forever on the endless tracewatch sampler (cells
  completed their work but never exited). Fixed (wait only for the
  snapshot pid), plus the evaluator's recovery window capped at
  REDUCE+120 s, plus the batch skips cells that already have a probe
  verdict. Committed, redeployed, batch restarted cleanly.

## Other tasks pushed early

- Task 6 second-driver list (due Oct 2): notes/p2-CLNODES.md from the
  CloudLab hardware docs -- ice: c6620 (Utah, 132), d760/d760-hbm;
  i40e: c6420 (Clemson, 72), c4130; bnxt: d6515, d750, rs440. The
  Clemson r650 carries Mellanox NICs only per the docs.
- Task 6 design note (due Oct 5): specs/p2-RXFUZZ.md with the memo's
  fixed dimensions, schedules, perturbations, oracles, budget,
  minimization (oracle windows pinned).
- Task 4 pre-registrations (due Oct 1): specs/p1-RINGSIZE.md (the
  memo's >=4x hazard prediction) and specs/p1-STRIDING.md (no
  direction supplied -- descriptive rule registered instead).
- Task 2 prep: bpftrace installed (BTF present);
  p1/t2_recovery_probe.sh written (per-CQ completion counts; the
  CQ->RQ/ICOSQ mapping gap recorded since the devlink rx dump is
  unavailable).
- Task 3: local blobless clone at /mnt/davidlin-personal/linux-study
  (5.7G); the memo's extraction produced 1,429 candidates
  (analysis/study/study-candidates.tsv + messages.txt); triage of all
  1,429 full messages delegated in 10 parallel slices (the memo's
  include/exclude rules verbatim); rows land in analysis/study/.

## Next

The 20-cell batch (~15 min out) -> analysis/rows-metastab.csv ->
the pre-registered class per level -> reported BEFORE any
interpretation (the memo's order). Note for the report: the smoke's
M316 queue stayed dead until a manual reset, which triggers the
memo's "stop and tell me before drafting" clause for task 5.
