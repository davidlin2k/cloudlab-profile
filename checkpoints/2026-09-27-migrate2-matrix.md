# 2026-09-27 — MIGRATE-2: the v2-harness 16-cell matrix closed out

## What
The v2-harness migration arm (M-A unpinned x8, M-B pin46 x8) completed:
batch 04:00-04:48Z, MA re-run 05:08-05:36Z, MB-1 re-run 05:40Z. All 16
cells verified healthy (probe 165k-300k lines, PROBE-OK, same-run trace
joins). Full classification landed 16/16 (308 stranded gaps) after
fixing a trailing-gap IndexError in migrate_analyze.py.

## Verdict
- **M-B (pin46) wedged 8/8** (v1: 5/8); **M-A (unpinned) 4/8** (v1: 8/8).
  The locality asymmetry sharpens: pinning to cpu 46 (no L3 shared with
  IRQ core 8) wedged every v2 cell; pin10 (same L3) was 0/8 in RQ1/E2.
- Classification: 213 event-silent (69%) / 4 wake-lost / 91 wake-flowing.
  **Record correction:** wake-lost is no longer zero — MA-2 contributes
  4 genuine lost wakes (napi_schedule on cpu 8, zero thread wakeups).
  Event-silent still dominates; the stale-arm hypothesis (DR-012 step 2)
  stands as the decisive test.

## Records
- notes/p1-MIGRATE-2.md (counts only, frozen format)
- analysis/migrate2/{migrate2-summ.txt, v1-classify.txt, migrate2-ma2-detail.txt}
- migrate_analyze.py: trailing-gap clamp fix (2 loop bodies)
- p1/arm_sn_logger.sh: v6.17 notifier signature (arg0 = irq_nb = eq+120),
  hex-literal filter; validated live: 2558/2564 ch7 events on cpu 8

## Next
- DR-012 step 2 (the stale-arm test): instrument deployed (probe v3 with
  arm_sn+adb_sn columns + the eq-filtered logger on the node). Smoke cell
  on a healthy queue, then 4 ARM_SN cells (HOP wiring, TRACE=1), one at
  a time. Deliverable: notes/p1-ARM_SN-1.md (counts only).
- Then DR-012 steps 3-5 (locality pin sweep, clean-definition tighten,
  cell-level bootstrap).
