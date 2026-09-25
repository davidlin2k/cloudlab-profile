#!/bin/bash
# t2_batch.sh -- DR-005 task 2: 3 unpin M158 cells with working CQ data
# (t2-1/t2-2 retain the instrument-failure records; reps 3-5 carry the
# pointer-keyed CQ counts). Step-4 recovery runs before every cell.
set -u
exec >> /root/p1/task2/batch.log 2>&1
echo "T2 BATCH START $(date -u +%FT%TZ)"
for rep in 3 4 5; do
  bash /tmp/t2recover.sh
  bash /root/p1/t2_cell.sh "$rep"
done
echo "T2 BATCH DONE $(date -u +%FT%TZ)"
touch /root/p1/T2-DONE
