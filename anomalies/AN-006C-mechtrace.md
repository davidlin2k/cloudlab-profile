# AN-006C: poll/reschedule code-path trace -- the park mechanism,
# confirmed at code level (2026-09-26 ~03:48-03:54Z)

Facts only; per DR-007 the PI reads before interpreting. This is the
trace DR-007's PI review asked for ("if a threaded poll returns
full-budget with pending work and NAPI parks without rescheduling, we
have the root cause") -- with one material correction to the draft
mechanism sentence (section 4).

## Setup

- Fresh specimen: cell M1-b2c-1, WEDGE, NOT-RECOVERED-120s,
  **PROBE-DEAD adv=0** at 03:47:12Z. Same channel addresses as AN-006B
  (verified in the trace harness before tracing; channels were never
  recreated).
- bpftrace kprobes on ch7's napi (0xff2714b410c46710), its RQ CQ
  (mcq 0xff2714b410c44178), napi_complete_done; 60 s passive + 60 s
  with the 10k discovery probe. 74,120 lines
  (analysis/taskB/bc_trace.txt).
- Channel/IRQ wiring: ch7 IRQ = 312 = mlx5_comp7@pci:0000:c3:00.0,
  affinity {cpu 8} (the receiver/application core per the task-1
  wiring). NAPI kthreads are taskset 0-63 (the unpin wiring) and were
  observed running on cpus 8/9/10/17 during the window.
- gro_flush_timeout=0, napi_defer_hard_irqs=0 (no deferred-IRQ timer
  path).
- Source contract (same-source tree): en_txrx.c mlx5e_napi_poll --
  `busy |= work_done == budget`; if busy and
  mlx5e_channel_no_affinity_change(c) (= cpumask_test_cpu(current_cpu,
  c->aff_mask)) then return budget WITHOUT napi_complete_done (core
  repolls); OTHERWISE on the busy+affinity-change path
  `ch_stats->aff_change++; if (work_done == budget) work_done--;` and
  fall through to napi_complete_done. net/core/dev.c __napi_poll:
  work==weight -> repoll=true (threaded loop continues); work<weight ->
  driver-owns completion (here: complete_done) -> threaded kthread
  parks in napi_thread_wait until the next event.

## Trace facts

DEAD regime (first 60 s, no injected traffic; 1,163 polls):

| poll ran on | work returned | napi_complete_done | meaning |
|-------------|---------------|--------------------|---------|
| cpu 8 (in aff_mask), 591 polls | **64** | **never called** | busy path: return budget -> repoll -> keep draining |
| cpu 10/17 (off-mask), 562 polls | **63** | **called, ret=1 (park)** | the detour: work_done-- then complete |
| (other) | 58-62 or 2-20, ~14 polls | called | mixed/short polls |

- aff_change counter: 107,641,150 (pre) -> 107,641,686 (post) =
  **+536** over the window ~= the 562 off-mask polls. The driver's own
  counter corroborates the detour count.
- cc advanced 64 CQEs per poll even when the return was 63 (the
  decrement is in the RETURN VALUE only). This decodes AN-006B's
  "+192 cc over 3 polls = exactly 64/poll": those were budget-exhausted
  polls that returned 63 and parked.
- Events ~= polls 1:1 (17,935 events / 18,889 polls over the full
  window); each parked poll required a new hardware event.
- COMPLETE ret=0 count: 0 (MISSED-race reschedule never happened).

RECOVERY regime (probe traffic, 17,726 polls): cpu 8 = 11,339 polls
(the kthread lands on the affinity CPU under load), work distribution
splits between tiny (2-7: arrival-limited) and near-budget (57-63:
drain bursts); backlog drains; rxrecover at 03:53:48Z found the queue
alive (baseline adv=80,064, ALIVE-NO-RECOVERY-NEEDED). Ladder again
unexercised.

## 4. The corrected mechanism (for the PI's mechanism sentence)

The draft sentence said "a threaded poll exhausts its budget with work
pending but does not reschedule itself." The trace shows something
more specific:

- A full-budget poll on the affinity CPU DOES reschedule (returns 64,
  no completion, repoll) -- the designed path works.
- A full-budget poll OFF the affinity CPU is turned into a 63-return
  by the driver's affinity-change detour (en_txrx.c) and completed --
  napi_complete_done clears SCHED and the kthread parks, with the CQ
  still holding ~60k completions. Draining then waits on the next
  hardware event, which yields at most one more (63-CQE) poll.
- The unpin wiring makes the NAPI kthread mobile; ch7's IRQ affinity
  is a single CPU (8) that is also the receiver/application core. When
  the application occupies that CPU, the kthread polls off-mask, every
  poll parks, and the queue trickles at (event rate x 63) against the
  offered load.

So: the park is driver-intended behavior on the affinity-change path;
the failure is the interaction -- unpinned threaded NAPI + single-CPU
IRQ affinity pinned to the busy application core + a budget-exhausting
backlog. That is a placement-dependent liveness failure, not a
starvation or lost-wakeup bug.

## Open items (unchanged roles)

- Permanence: this specimen self-recovered twice under probe traffic;
  "dead until reset" is not established. PERSIST A-arms zero-load
  probe (PI instruction 4) decides the severity word.
- Minimization (PI instruction 5): which configs reach the backlog
  condition; the latch mechanism no longer depends on it.
- The striding correlation: trigger-condition framing per the PI.

## Artifacts

- analysis/taskB/bc_trace.txt (full trace), bc_pre.txt / bc_post.txt
  (state dumps before/after, incl. aff_change), rxrecover-bc.log,
  b2c-cell.tar.gz (cell M1-b2c-1 + harness logs).
- Node: /tmp/bc_*.txt, /tmp/bc.bt, /root/p1/bc*.log,
  /root/p1/metastab/M1-b2c-1.
