# 2026-09-27 — Migration arm v2: smoke + full batch launch

## What
Re-run of the migration arm (M-A + M-B) with the v2 harness (per-session WIRE/TAG/NAMESEL variables):
- WIRE pin → CPU 2, `napi_aff` record written (napi/enp195s0np0 → 2). WIRE unpinned → record absent.
- TAG removes the script-name race: every log line carries the cell tag.
- Cell dir `M$NKEEP-$REP` + the smoke dir deleted before launch.

## Smoke (M-A, 1 cell, unpinned, no trace)
- **M-A unpinned wedged on the first smoke cell** (mono 33883 → RECOVERED at 33942) — the migration-arm prediction landed immediately, consistent with the RQ1 val-2/3 + PERSIST pattern.
- Then the wake trace was captured on a second smoke cell (M-A unpinned, 1-cell): trace dat = 7,794,006 bytes.
- napi_aff: 0-63 (unpinned wiring recorded as expected).
- The trace did not break the cell.

## Batch
- 16 cells detached: `migrate_arm.sh MA 8` then `migrate_arm.sh MB 8`, ~3 h.
- Driver source cloned for the wake-path investigation: v6.17, sparse (mlx5 core + includes) at /home/david/workspace/linux-v6.17.

## Next
- Poll the batch (~3 h); when M-A completes, analyze the wake trace (v2 protocol: the kernel's own timestamps via trace-cmd report, the 46-residence gaps, the migration-moment onsets).
- The p1-MIGRATE-2 table fill (counts per cell) when the batch completes.
