# p1-T1A: who owns the silence? (DR-013 item T1a), pre-registered

Frozen 2026-09-27 (~1x:xxZ) BEFORE any run. Source: decisions/DR-013.md
T1a, verbatim, with the instrument facts pinned from the v6.17.8
source (the node's kernel) and the build-tree DWARF. Due Wed Sep 30;
hard stop 3 working days. pin46 arm, same config as p1-LOCALITY.

## Instrument (extends the existing tools only; nothing new)

1. rq1_probe.py v4 (kcore, ~1 kHz): the existing v3 columns PLUS
   - eq_ci: the comp EQ's cons_index (u32 @ eq+88, DWARF);
   - eq_devw: 4 bits -- for slots i=0..3, is the EQE at
     cons_index+i DEVICE-WRITTEN (unconsumed)? Test per lib/eq.h:61:
     ((owner ^ (eq_ci >> fbc.log_sz)) & 1) == 0 -> device-written.
     EQE addressing per driver.h (frag_buf_get_wqe): ix +=
     strides_offset; frag = ix >> log_frag_strides; addr =
     fbc->frags[frag].buf + ((frag_sz_m1 & ix) << log_stride);
     owner byte @ eqe+63 (DWARF).
   - eq_cqn0: the cqn (BE 24 bits @ eqe+32) of the slot-0 EQE --
     the buffer-addressing cross-check (expect ch7's cqn 1067
     whenever a new EQE exists).
   - eq_nent (fbc.sz_m1+1) and the doorbell ADDRESS recorded once
     at probe start.
   - at 1 Hz (every 1000th sample): rx_phy / rx_oob from
     ethtool -S (rx_packets_phy, rx_out_of_buffer).
2. arm_sn_logger.sh v2 (bpftrace): the existing kprobe:mlx5_eq_comp_int
   (nb filter) PLUS tracepoint:irq:irq_handler_entry filtered to the
   queue vector's irq number. Tag each line E (completion event) /
   I (hardware IRQ entry), with (ts, cpu). BEGIN anchor line: the
   logger's nsecs + strftime wall -- the probe and logger clocks
   join via the wall stamp.
3. The EQ re-arm site: eq_update_ci is a static inline
   (core/lib/eq.h:68) writing __raw_writel to the doorbell MMIO --
   NOT kprobeable. Per the memo, the EQ doorbell record is read
   instead: the host-side cons_index at 1 kHz (above) plus the
   doorbell MMIO address recorded at probe start. A re-arm's
   host-visible trace is the handler's own completion (logger line
   E) and the cons_index advance; the device-side commit of the
   MMIO write is not host-readable -- recorded as an instrument
   limit, branch 2 vs branch 1/3 discrimination uses the state
   table below.
4. The MSI-X handler is irq_int_handler (pci_irq.c:227) -> the
   notifier chain; it is static, so the IRQ timeline uses the
   tracepoint (2), not a symbol.
5. Affinity: /proc/irq/<irqn>/smp_affinity_list sampled at 1 Hz.

## Documented deviations from the memo's literal text

- The port counters (rx_phy / rx_oob) and the affinity are sampled
  at 1 Hz, not 1 kHz: ethtool -S is a firmware-mailbox ioctl; at
  1 kHz it would disturb the cell it measures. The IRQ per-CPU
  count is carried by the tracepoint timeline (exact per event),
  not a 1 kHz file parse (a /proc/interrupts read costs ~1 ms).
- Buffer exhaustion (rx_out_of_buffer climbing) is expected as a
  CONSEQUENCE of no polling; it is logged but never classifies
  (the memo's rule).

## Cells

pin46 arm (MB wiring, the SWEEP harness with SWEEP_CPU=46), the
M158 protocol, TRACE=1, n cells run until >= 5 event-silent gaps
are captured with the v4 probe + v2 logger attached; stop at the
time-box (Wed Sep 30). Each cell's artifacts land in its own
/root/p1/migrate/T1A-<n>/ (probe.csv, eqint.log, analyze.txt).

## Decision rule (frozen, the memo's table verbatim)

| During the gap | Owner | Consequence |
|---|---|---|
| EQ holds new, unconsumed entries, but the vector's interrupt count doesn't move | Interrupt delivery (host or platform) | Report with the IRQ trace; check affinity changes at onset |
| EQ was not re-armed after its last event | Host driver (mlx5 EQ handling) | netdev report with a mechanism; the one branch that could reopen the paper question, which is my call, not yours |
| EQ empty and armed, CQ armed, completions pending | Device/firmware | Vendor bug report |

Classification notes (facts, pre-registered):
- "EQ holds new, unconsumed entries" = eq_devw shows device-written
  EQEs beyond eq_ci during the gap (the owner bits of the slots at
  the frozen cons_index say DEVICE).
- "EQ empty and armed, CQ armed, completions pending" = no
  device-written EQE at the frozen cons_index while the CQ shows
  unconsumed owned CQEs (the probe's cc/own columns) and the last
  logger E line precedes the gap.
- "EQ was not re-armed after its last event" is the residual: the
  last E line precedes the gap, no new EQE exists at cons_index,
  and the doorbell was committed by the handler we saw run --
  i.e. the re-arm state cannot be read directly; this branch's
  evidence is the ABSENCE of the branch-1 signature with a
  handler that demonstrably ran. Recorded as such.

## Deliverable

notes/p1-T1A-1.md (counts only): per captured gap -- the EQ state,
the IRQ delta, the affinity at onset, the counters -- and the
branch call per the frozen table. Feeds D1 and D2 section 6.