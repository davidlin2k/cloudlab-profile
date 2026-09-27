#!/bin/bash
# p1/pin10_more.sh -- DR-013 T1c: 12 more same-L3 (pin10) cells,
# PT10-9..PT10-20, the LOCALITY harness unchanged, detached.
set -u
for i in $(seq 9 20); do
  SWEEP_CPU=10 bash /root/p1/migrate_run.sh "PT10-$i" SWEEP \
    >> /root/p1/migrate/arm-PT10.log 2>&1
  sleep 5
done
echo "PIN SWEEP PT10 MORE DONE (12 cells, T1c) $(date -u +%FT%TZ)" \
  >> /root/p1/migrate/arm-PT10.log