# p1-REARM spec (DR-014 experiment 1) -- pre-registered before any run

## Question

When a ready completion sits stranded (> 50 ms, no event), does the
device register a RE-ISSUED arm doorbell? Two remaining hypotheses
the host cannot currently distinguish: (i) the firmware gets stuck;
(ii) the arm doorbell the host writes never takes effect.

## Trigger (detection, unchanged instrument)

rq1_probe (self-calibrated on the node) flags a strand when: the CQ
holds a ready CQE at its consumer index (owner bit = SW), the EQ is
empty at its consumer index, the poller is not advancing, for
> 50 ms.

## Action (the debug hook, kernel-side)

A debugfs trigger on the receiver; on write, the hook scans the
rq channels and acts on the first stalled one (ready CQE at ci AND
napi not scheduled):
- variant (a) re-arm: re-issue the CQ arm doorbell (the same write
  mlx5_cq_arm performs: arm_db record with a fresh arm sequence
  number and the ARM flag, followed by the doorbell write).
- variant (b) poll: napi_schedule(&rq.napi).

Protocol per strand: variant (a) at T0; wait 500 ms; if no event and
no advance, variant (b) at T0+0.5 s. Record both timings.

## Frozen interpretation (DR-014, verbatim)

| Result | Meaning |
|---|---|
| (a) produces an event within milliseconds | The device never registered the earlier arm. Doorbell delivery or ordering problem on the host or platform side -- a real root-cause path with a possible driver fix (e.g. flushing the posted write after arming) |
| (a) does nothing, (b) resumes the queue and later arms work normally | The device is stuck in its notification logic, but the data path is fine. Firmware, confirmed, with a clean workaround |
| Neither helps | The device is stuck more deeply. Firmware, and the report says so with this evidence |

## Cell plan

- clnode323 (the new receiver; topology == clnode366: cpu8's CCX =
  {8-11,40-43}; IRQ forced to cpu 8; poller pinned to cpu 46 -- the
  pin46 arm), single sender 10.10.1.10, flood 158 kpps / 45 s /
  plen 64, the W1 ntuple rules steering to queue 7 (preflight v2,
  idempotent).
- n = 8 cells. Each cell yields one strand-action opportunity; the
  per-cell record = which variants fired, timings, and whether the
  queue resumed.
- Kernel: net-next HEAD + the rearm debug hook (the watchdog is NOT
  in this build; nothing else changed).
- Time-box: 1-2 days (the memo). The build/bring-up has a 1-day
  hard stop; if the kernel build fails on the new node, the fallback
  is the stock 6.8 kernel (the stall's reproduction on 6.8 is
  unverified -- one smoke cell decides whether the fallback exists).