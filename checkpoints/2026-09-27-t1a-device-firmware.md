# 2026-09-27 — DR-013 week 1: T1a answers DEVICE/FIRMWARE; T1c bound achieved; T1e patch drafted

## T1a (device-state capture) — DONE, ahead of the Sep 30 due date
The instrument (probe v4: the comp-EQ state at ~992 Hz; the v2
logger: the completion-event timeline via the mlx5_eq_comp_int kprobe
+ the hardware-IRQ timeline via the irq:irq_handler_entry tracepoint,
WALL/BEGIN clock anchors) ran 6 pin46 cells. 138 stranded gaps
captured (80 event-silent — the ≥5 requirement met 16×).

**Every gap, both regimes: eq_ci frozen, the EQ EMPTY (zero
device-written EQEs at cons_index), zero hardware IRQ entries, zero
completion events, affinity constant, rx_out_of_buffer climbing by
tens of millions. Branch call per the frozen table: DEVICE/FIRMWARE**
(the vendor-bug-report branch). Branch 1 excluded (nothing to
deliver), branch 2 excluded as the silence's cause (a lost re-arm
would still show EQEs). The CQ is armed (clean parity, consistent
with DR-012's 67/67). notes/p1-T1A-1.md.

## T1c (the workaround bound) — DONE
PT10-9..20: 0/12 wedged, zero stranded gaps in every cell →
**0/20 total: the same-L3 stall rate is bounded below ~14%** (the
bug report's workaround sentence). The fw release-note reading:
after 20.43.3608 the only release (20.43.8002) lists NO bug fixes;
the only CQ fix in the window (CQ refcount underflow, 4055323) is
20.43.2026 — already carried by the node. notes/p1-T1C-fw-notes.md.

## T1e (the patch prototype) — drafted, frozen, awaiting T1d
p1/t1e-napi-thread-cpumask.patch: at napi_kthread_create (the single
creation choke point), default the threaded poller's cpumask to the
L3 siblings of its vector's effective affinity — re-applied on every
(re)creation (the June-2026-RFC lifecycle gap). specs/p1-T1E.md
frozen: prediction 0-1/8 on the patched unpinned arm; the memo's
decision rule.

## Next
- T1d: build v6.18.9 (adb851edb707) + net-next (014d795c7383) on the
  node, pin46 ×8 per kernel, record c326f9c68921's presence.
- T5: the distribution survey is running (subagent).
- T1b: BLOCKED on the c6420 reservation — a CloudLab portal action
  outside this harness; needs the user.
- D1/D2/D3 per the memo's dates; the T1a result puts the vendor
  channel in D1's recipients.
