#!/bin/bash
# p1/t1d_run.sh -- DR-013 T1d: the pin46 arm, n=8, on the CURRENTLY
# RUNNING kernel (call after booting the target kernel). Cells
# T1DA-* / T1DB-* named by TAG; the standard probe + classify join.
# Usage: t1d_run.sh <T1DA|T1DB>
set -u
TAG="${1:?T1DA|T1DB}"
for i in 1 2 3 4 5 6 7 8; do
  SWEEP_CPU=46 bash /root/p1/migrate_run.sh "$TAG-$i" SWEEP \
    >> /root/p1/migrate/arm-$TAG.log 2>&1
  sleep 5
done
echo "T1D $TAG DONE (8 cells, $(uname -r)) $(date -u +%FT%TZ)" \
  >> /root/p1/migrate/arm-$TAG.log