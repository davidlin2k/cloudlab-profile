#!/bin/bash
# p1/t1a_arm.sh -- DR-013 T1a: N pin46 cells, one at a time, each
# with the T1A probe (v4) + the v2 logger. The spec's stop rule:
# run until >= 5 event-silent gaps are captured; stop at the
# time-box (Wed Sep 30).
set -u
N="${1:-6}"
for i in $(seq 1 "$N"); do
  bash /root/p1/t1a_cell.sh "T1A-$i" >> /root/p1/migrate/arm-T1A.log 2>&1
  sleep 5
done
echo "T1A DONE ($N cells) $(date -u +%FT%TZ)" >> /root/p1/migrate/arm-T1A.log