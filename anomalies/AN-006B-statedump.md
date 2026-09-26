# AN-006B: DR-007 Task B dead-vs-healthy state dump (2026-09-26 ~03:20Z)

Facts only. Per DR-007 the PI reads this before any interpretation.

## Specimen

- Cell M1-b2-2 (`metastab.sh M 10 b2-2`): flood 790k from 10.10.1.10-14,
  WEDGE at +8 s, hold 10 s, REDUCE to .10-only at 158k, NOT-RECOVERED-120s,
  **PROBE-DEAD adv=0**, T_END 03:15:43Z. Queue left dead (no recovery step).
- Earlier cell M1-b2-1 wedged identically but self-recovered late
  (PROBE-OK adv=361,984) and was not used.
- Dump taken 03:20Z (~4.5 min after PROBE-DEAD) via `p1/b2_dump.py`
  (committed 5096714; address discovery runtime-only: bpftrace kprobes
  `mlx5e_napi_poll`/`mlx5e_completion_event` -> channel -> priv, priv
  confirmed by reading the netdev name from memory = enp195s0np0).
- All offsets from pahole on the DWARF of our own v6.17.8 module build;
  kernel-side napi_struct offsets from the same vmlinux build.

## B3 answer: (A) -- a completion IS pending with no (adequate) event

Dead-state ch7 (wedged), all values vs healthy ch0 control:

| field                          | ch7 (wedged)                 | ch0 (healthy)        |
|--------------------------------|------------------------------|----------------------|
| napi.state                     | 0x110 [LISTED,THREADED]      | 0x110 (same park)    |
| rq.state                       | 0x25 [ENABLED,DIM,MINI_CQE_HW_STRIDX] | same        |
| RQ wq_ll head / wqe_ctr / cur_sz | 3 / 2627 / 63 posted       | 31 / 95 / 62 posted  |
| mpwqe umr_in_progress          | 0                            | 0                    |
| ICOSQ cc / pc (outstanding)    | 28018 / 28018 (**0**)        | 1010 / 1010 (**0**)  |
| rq.stats congst_umr            | 0                            | 0                    |
| rq.stats buff_alloc_err        | 0                            | 0                    |
| rq.stats wqe_err               | 0                            | 0                    |
| CQ (cqn 1067, 65536 x 64B) cc  | 2,626,134                    | (cqn 1032) 33,967    |
| CQ pending-walk from cc        | **60,842 consecutive HW-owned, opcode 2 (RESP_SEND)** | 0, opcodes {15:64} (INVALID) |
| CQ invalid (never-written) slots | 0 / 65536                  | 31,569 / 65536       |

The CQ held ~60.8k unconsumed completions when HW stopped writing
(owner-parity walk from cc; the ~4.7k non-owned remainder matches slots
HW last wrote in the previous cycle). SW consumed none since cc.

## The twist: events arrive and polls run -- at 64 CQEs per event

Snapshot deltas (8 s apart, inside the dead dump):

- cc: 2,626,134 -> 2,626,326 (**+192**)
- rq.stats.packets: 20,512,389,611 -> 20,512,389,803 (**+192**, = 64/poll x 3)
- pending-walk: 60,842 -> 60,650 (**-192**)
- ch.stats: events +3, poll +3, arm +3 (one event -> one poll -> one re-arm,
  ~2.7 s apart)
- napi.state unchanged (0x110; SCHED and MISSED never set between polls)
- ICOSQ pc/cc unchanged; umr_in_progress=0 throughout

Counter trace 03:20:03-03:20:23Z (b4): rx7_packets +832 over 20 s
(~83/s) while rx_out_of_buffer stayed frozen at 1,399,296,081;
rx_congst_umr=0, rx_buff_alloc_err=0 throughout.

So the queue was not event-silent: completion events kept arriving, NAPI
polled, and each poll consumed exactly one 64-CQE budget and stopped --
despite ~60k unconsumed completions remaining in the CQ. Delivery
trickled at ~24-83 pps against 790k offered. The cell's 30 s probe read
adv=0 (zero advance) at 03:15:43Z; by the dump the trickle had begun.

## Recovery (B5)

`rxrecover.sh` at 03:23:25Z: baseline probe adv=128,071 (~16k pps
delivered of ~18k pps offered) -> **ALIVE-NO-RECOVERY-NEEDED**. The
queue self-recovered between 03:20:23Z and 03:23:25Z, correlated in
time with the probe traffic, without any recovery step. Post-recovery
dump 03:24:17Z: CQ pending 0, packets +141,897 vs the dead dump, ICOSQ
pc/cc +1,472 -- backlog fully drained.

The ladder (threaded toggle / recreation) was NOT exercised on this
specimen: there was nothing left to recover.

## Instrument caveats (recorded, they do not touch the reads above)

- The rebuilt vmlinux's symbol ADDRESSES do not match the running
  kernel (init_net walk returned foreign memory), so no kernel-symbol
  dereference is used anywhere; every address comes from runtime
  discovery. TYPES from the same-source build are assumed to match
  (same release + config; recorded as caveat).
- mlx5_core_cq of the RUNNING kernel has two extra pointers vs our
  rebuild (vector/irqn at +88/+92); cons_index could not be located,
  so the pending-walk uses cc + owner parity only. Healthy-control
  validation: ch0 reads 0 pending / unwritten slots as INVALID (0xF),
  and the dead deltas close exactly (+192 = -192).
- drgn 0.2.0 (venv) refuses our mismatched-build files by design; the
  dump runs on system drgn 0.0.25 with /proc/kcore as a core-dump
  program. The dump's discovery probe perturbs the dead state minimally
  (10k kbps x 8 s; deliveries counted in the deltas above).

## Artifacts

- analysis/taskB/b2_dead.txt (full dump, 2 snapshots), b2_recovered.txt
  (contrast), b4_counters.txt, b4_post.txt, rxrecover-b2.log,
  b2-cells.tar.gz (cell dirs M1-b2-1/2 + loop log).
- Node copies: /tmp/b2_*.txt, /tmp/b4_*.txt, /root/p1/metastab/M1-b2-*.
