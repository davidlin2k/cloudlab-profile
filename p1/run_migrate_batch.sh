#!/bin/bash
# P1 migration-arm batch: M-A (8 cells) then M-B (8 cells), one at a time.
exec > /root/p1/migrate/batch.log 2>&1
echo "=== P1 MIGRATION BATCH START $(date -u +%FT%TZ) ==="
bash /root/p1/migrate_arm.sh MA 8
echo "=== MA DONE rc=$? $(date -u +%FT%TZ) ==="
sleep 10
bash /root/p1/migrate_arm.sh MB 8
echo "=== MB DONE rc=$? $(date -u +%FT%TZ) ==="
echo "=== BATCH COMPLETE $(date -u +%FT%TZ) ==="
