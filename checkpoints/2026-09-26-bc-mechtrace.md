# Checkpoint 2026-09-26: B-C poll/reschedule trace -- mechanism confirmed
# at code level (with a correction), sent to the PI same hour

## What ran

Per the PI's instruction 2 ("trace mlx5e_napi_poll's return value and
whether napi_complete_done is called on the budget-exhausted polls"):
cell M1-b2c-1 (PROBE-DEAD adv=0, first attempt), then a bpftrace
kprobe/kretprobe trace on ch7's napi for 60 s passive + 60 s with the
10k probe. 74,120 lines; concurrent state dumps; aff_change counter
read before/after.

## The verdict (facts in anomalies/AN-006C-mechtrace.md)

- On the affinity CPU (cpu 8 = IRQ 312's mask = the receiver core),
  full-budget polls return 64, skip napi_complete_done, and repoll --
  the designed keep-draining path WORKS.
- Off-mask (cpus 10/17), the same budget-exhausted polls take the
  driver's affinity-change detour (en_txrx.c: aff_change++, work_done--
  -> 63) and fall through to napi_complete_done -- ret=1 every time --
  clearing SCHED and parking the kthread with ~60k completions still
  in the CQ. 535 parked detour polls in the dead window; aff_change
  delta +536 ~= the 562 off-mask polls.
- AN-006B's "exactly 64 CQEs per poll" decodes: cc advances 64 (the
  consumption), the return is 63 (the decrement is return-only).
- COMPLETE ret=0 (MISSED-race rescue) never fired.

## The correction to the draft mechanism sentence

It is not "the poll fails to reschedule itself after a full budget."
A full-budget poll DOES reschedule -- but only when it runs on the
IRQ-affinity CPU. Off it, the driver's own affinity detour converts
the full-budget poll into a completed-and-parked poll. The failure is
the interaction: unpinned threaded NAPI (the unpin wiring) + single-CPU
IRQ affinity pinned to the busy application core + a budget-exhausting
backlog. Placement-dependent liveness failure -- the paper's core
claim, now with a code-level mechanism.

## Also done per the PI's instructions

- Instruction 4: specs/p1-PERSIST.md Amendment A -- A0 arm with a true
  zero-load 300 s quiet window and pre-registered PERMANENT-LATCH vs
  DEEP-TRICKLE outcome rules.
- Instruction 5: minimization relaunch (role: which configs reach the
  backlog condition) -- launched after this checkpoint; eval prints
  the minimal wedging set per hit + the 6-hit intersection; the
  069/089 threaded question stays under the A4 same-hour rule.
- Instruction 1 honored: AN-006B not rewritten; AN-006C is a new file.
- Disclosure: still gated on the PI's review; striding reframed as
  trigger condition per the PI's instruction 3 (draft not started
  until the PI answers this trace).

Committed and pushed to origin/main; mirrored to deep-research-output.
