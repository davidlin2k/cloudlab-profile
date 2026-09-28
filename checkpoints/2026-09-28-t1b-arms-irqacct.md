# Checkpoint: T1B arms complete + Day-4 IRQACCT -- 2026-09-28

DR-015.  Experiment davidlin-318237, pin 16afc6a (harness) / 8543ab0
(driver).  Raw data: deep-research-output/rx-placement-admission/
t1b-raw/ (32 cell dirs + results + MANIFEST.sha256; IRQACCT in
stock-195/ and m617-208/).

## T1B arms: 32/32 cells, decision rule resolved

All four arms x 8 cells x 2 pairs completed 20:22-22:04Z in the frozen
randomized block orders (p1/t1b_orders_P1.txt, _P2.txt, seed
20260928/9).  Per-arm tally (t1b_summarize.py):

| arm | cells | stranded | max strand | pkts conserved |
|---|---|---|---|---|
| A (SMT sib, cpu38) | 8 | 0 | 0.0 ms | 8/8 exact |
| B (same sock, cpu10) | 8 | 0 | 0.0 ms | 8/8 exact |
| C (other sock, cpu24) | 8 | 0 | 0.0 ms | 7/8 exact (1 cell +5 pkts, RX-side dedup) |
| D (unpinned) | 8 | 0 | 0.0 ms | 8/8 exact |

Zero drops in every cell; the DD/pending detector saw live pending
work in ~15-16k rows per cell (i.e. it was armed and sampling the
right thing) and never fired; the PKT fallback never fired.

**Decision (frozen rule, verbatim): "All arms <= 1/8 -- not reproduced
on i40e / Intel Xeon.  Report says exactly that.  Note the confound:
NIC and CPU platform both changed."**

T1a's DEVICE/FIRMWARE call STANDS: the stall did not follow the
threaded-NAPI mechanism onto a different driver/CPU family.  The bug
report can go out as drafted (DR-014 still holds it until the
re-arm/watchdog rows land).

## Day-4 IRQACCT (C-014 on c6420): criterion resolved

| kernel | stat busy | PMU busy (ref/TSC) | ratio |
|---|---|---|---|
| 6.8.0-138 stock (IRQ_TIME_ACCOUNTING unset, NO_HZ_FULL=y, NO nohz_full= arg) | 0.45 s | 47.31 s | **105x** |
| 6.17.8-061708 (same kernel as the r6615) | 7.95 s | 11.40 s | 1.4x |

**An undercount appears with IRQ_TIME_ACCOUNTING unset AND no
nohz_full= on the cmdline -> per the memo: the criterion is
IRQ_TIME_ACCOUNTING-unset alone; C-024 widens.**

The 6.17.8 leg (1.4x) doubles as an instrument control: same NIC, same
pair, same pps -- the gap follows the kernel config, not the platform.

## Notes
- i40e vs mlx5 comparability: the cell protocol is identical
  (158k pps, 64 B, one steered queue, threaded NAPI, IRQ-core pin);
  the detector differs by design (DD-bit probe instead of the mlx5
  CQ/EQ probe) because the mechanisms differ (DR-015: i40e re-enables
  via register write, not CQ arm/EQ).
- The ~2.7% sent-vs-received gap is in the SENDER's k5blast count
  (identical in every cell, both pairs); receiver-side accounting is
  exactly conserved and port discards are 0.
- The T1e lesson held: on c6420 the IRQ core's sibling (A) is as clean
  as every other arm -- no strand anywhere.

## Next
- Fri per schedule: write notes/p1-T1B-1.md (negative result +
  accounting result + confound note); the confound-breaker (xl170,
  Broadwell + ConnectX-4 Lx) is pre-verified in
  notes/confound-breaker-xl170.md but NOT required -- the memo orders
  it only for a clean sweep, and this sweep is clean, so the PI may
  want it; flag the question in the note rather than running it.
- r6615 lane: clnode323 still down (console owed); the spec addendum
  (phenotype-B trigger) is committed.
