#!/bin/bash
# p1/t1e_run.sh -- DR-013 T1e: the UNPINNED arm (MA wiring) on the
# PATCHED kernel, n=8. Cells T1E-1..8. The decision rule (the frozen
# spec): 0-1/8 -> send the patch as an RFC; >= 3/8 -> drop it.
set -u
for i in 1 2 3 4 5 6 7 8; do
  bash /root/p1/migrate_run.sh "T1E-$i" MA \
    >> /root/p1/migrate/arm-T1E.log 2>&1
  sleep 5
done
echo "T1E DONE (8 cells, $(uname -r)) $(date -u +%FT%TZ)" \
  >> /root/p1/migrate/arm-T1E.log