#!/bin/bash
# p1/pin_sweep_arm.sh -- DR-012 step 3: the locality pin sweep, detached.
# Runs PT10 x8 then PT24 x8 sequentially (one run at a time), each cell
# the MIGRATE harness with the SWEEP wiring (SWEEP_CPU env -> pinN).
set -u
for tag in PT10 PT24; do
  for i in 1 2 3 4 5 6 7 8; do
    SWEEP_CPU="${tag#PT}" bash /root/p1/migrate_run.sh "$tag-$i" SWEEP \
      >> /root/p1/migrate/arm-$tag.log 2>&1
    sleep 5
  done
  echo "PIN SWEEP $tag DONE (8 cells)" >> /root/p1/migrate/arm-$tag.log
done
echo "PIN SWEEP COMPLETE $(date -u +%FT%TZ)" >> /root/p1/migrate/arm-PT24.log
