# Checkpoint 2026-09-26: DR-007 Task B complete -- state dump captured, B3 = (A)

## Answer to "did you find the root cause"

The Task B state dump is DONE (the DR-007 priority deliverable) and it
answers B3: **(A) -- completions are pending with no adequate event**,
with a twist that sharpens the picture:

- The wedged CQ held ~60,842 unconsumed completions (owner-parity walk
  from cc, valid RESP_SEND opcodes, 0 unwritten slots) while NAPI sat
  parked (LISTED|THREADED, no SCHED/MISSED) -- the healthy control
  channel read 0 pending.
- BUT the CQ was not silent: events kept arriving (+3/8 s), NAPI kept
  polling (+3/8 s), and each poll consumed exactly one 64-CQE budget
  (+192 cc, +192 packets, pending -192) and stopped -- 60k completions
  remained. Delivery trickled at ~24-83 pps against 790k offered.
- No UMR was outstanding (ICOSQ pc==cc), no congst_umr, no
  buff_alloc_err, RQ still ENABLED with 63 posted buffers.
- The queue self-recovered between 03:20:23Z and 03:23:25Z (probe
  traffic correlated); rxrecover found it alive; post-recovery CQ
  pending = 0.

Read the addendum BEFORE interpreting: anomalies/AN-006B-statedump.md
(facts only, per DR-007).

## Where this leaves the program

- B1 (dead specimen): cell M1-b2-2, PROBE-DEAD adv=0, dump taken
  4.5 min later inside the metastable window. M1-b2-1 self-recovered
  late (PROBE-OK) and was discarded.
- B0: p1/b2_dump.py (committed before running) + DWARF builds; the
  rebuilt-vmlinux address mismatch forced runtime-only address
  discovery (bpftrace -> channel -> priv, netdev-name-confirmed) --
  recorded in the addendum's caveats.
- B5: ladder unexercised (self-recovery won); logged as
  ALIVE-NO-RECOVERY-NEEDED.
- Artifacts: analysis/taskB/* (dead/recovered dumps, counter traces,
  recovery log, cell tarball) -- off the node, committed.

## Next per DR-007 order

1. Minimization pass (relaunch; the 6 hit cells; intersection table +
   069/089 threaded question -> A4 same-hour rule).
2. AN-006 addendum delivered to the PI (this one) -- mechanism sentence
   after the PI reads it.
3. PERSIST Task A (Mon Sep 28); kappa merge completion; disclosure
   draft remains gated on 2 and 3.

Committed: b2_dump.py fixes, AN-006 addendum pointer, AN-006B
addendum, artifacts; pushed to origin/main.
