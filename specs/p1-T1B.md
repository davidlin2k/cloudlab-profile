# p1-T1B spec -- cross-platform stall replication (DR-015) -- FROZEN

## Question

Does the complete-then-rearm stall reproduce on a different NIC
driver (i40e / Intel X710) and CPU platform (Intel Xeon Gold 6142)?
T1a called the stall DEVICE/FIRMWARE on mlx5/AMD (notes/p1-T1A-1.md).
If i40e stalls the same way, that call is wrong and the bug report
cannot go out as drafted (DR-015).

## Hardware

4x Clemson c6420: 2x Intel Xeon Gold 6142 (16c each, 64 threads),
384 GB, Intel X710 10GbE (i40e). Two DUT/sender pairs from one
experiment: pair1 = rx + tx0; pair2 = tx1 (promoted DUT, re-run
setup.sh with role=rx) + tx2 (sender). The DUTs get the 6.17.8
mainline kernel (see below); the senders keep the stock kernel.

## Kernel (both DUTs)

Install the same Ubuntu mainline build the r6615 ran:
6.17.8-061708-generic (the mainline PPA debs), so only the NIC and
platform differ from the r6615 runs. Record /proc/cmdline + uname on
every cell.

## Steering (DUT)

i40e Flow Director rules via `ethtool -N`: udp4, the sender's IP and
sport -> dst-port 7777 -> one fixed queue (queue 7 by convention).
IDEMPOTENT install exactly like p1/preflight.sh v2: add a rule only
if missing; log the rule count and adds per cell (AN-010: rule adds
reprogram the device flow table).

## Configuration (DUT, per cell)

threaded NAPI on; the flooded queue's IRQ affinity forced to one CPU
(the "IRQ core", fixed for the whole experiment); the poller's
placement per arm (below) via the poller thread's affinity (taskset
on the napi thread, the r6615 mechanism).

## Arms (n = 8 each; 32 cells total across the 2 pairs)

| Arm | Poller placement (relation to the IRQ core) | r6615 analog |
|---|---|---|
| A | the IRQ core's SMT sibling | cpu 40 (5/8) |
| B | a different physical core, same socket | cpu 10 (0/20) |
| C | a core in the other socket | cpu 24 (5/8) |
| D | unpinned (default) | unpinned (4/8-8/8) |

Sibling/core/socket IDs come from the platform dump
(notes/platform-c6420.md), NOT assumed.

## Protocol per cell (identical to the r6615 cells)

158k pps UDP flood, 64 B packets, dst-port 7777, one queue; the
flood runs the same duration as the r6615 cells (20 s) inside the
same 330 s readiness-probe window; the cell harness = a port of
p1/migrate_run.sh with the i40e discovery.

## Detector

Primary (the ported probe, time-boxed to 2 days): read the RX
descriptor at the ring's next_to_clean and check the descriptor-done
bit. STRANDED = the DD bit set while next_to_clean is frozen for
more than 50 ms. The probe samples ~1 kHz like rq1_probe and writes
the same CSV schema plus the i40e columns (next_to_clean, dd, the
drop counters).
Fallback (coarse, if the port is not working by Oct 1): the queue's
rx_packets frozen while the port's drop counters climb.
EVERY CELL RECORDS WHICH DETECTOR IT USED (the detector column).

## Blocks and randomization

Each pair runs 4 blocks; each block = one cell of EVERY arm in
randomized order (a fresh shuffle per block). Both pairs see every
arm equally. Per-cell logs: the rule adds, the rule count, the arm,
the block, the detector, the verdict.

## Decision rule (verbatim from DR-015)

| Result | Meaning | Consequence |
|---|---|---|
| Any arm >= 3/8, with the probe confirming stranded descriptors | Not mlx5-specific; a host-side threaded-NAPI mechanism is implicated | T1a's device/firmware call must be revisited before the report goes out. STOP and tell the PI |
| All arms <= 1/8 | Not reproduced on i40e / Intel Xeon | Report says exactly that. Note the confound: NIC and CPU platform both changed |
| Anything else | Inconclusive | Report as inconclusive |

A clean i40e result is expected under either device-side explanation
(the firmware stuck, or the arm doorbell not taking effect): i40e
re-enables interrupts through a register write, not mlx5's CQ arm +
event queue, so it does not share the suspect mechanism.

## Analysis and record

Verdicts per arm from the cell CSVs (the rq1_summarize-style
classification); the run record = notes/p1-T1B-1.md; the raw data +
a sha256 manifest backed up off-node BEFORE the nodes are released
(DR-015: release only after the note is committed and the manifest
verifies).

## Follow-ups queued after this run (DR-015)

Day 4 (Thu): the C-014 accounting measurement on the c6420 stock
kernel (the AN-007 method: the hardware counters vs /proc/stat busy
time on the IRQ core under flood; the IRQ_TIME/NO_HZ_FULL/cmdline
recorded; the C-024 widening or re-derivation per the memo).
Only if every arm is clean: the xl170 (Intel + mlx5) confound
break, arms A/C/D, n = 8 -- VERIFY xl170's NIC on the hardware page
first (the docs page lists xl170 = a ConnectX-4 25G dual port ✓ mlx5).