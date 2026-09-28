#!/bin/bash
# p1/t1f_cells.sh -- DR-014 experiment 1: the rearm test, cells 2..8,
# the pin46 arm, sequential, REARM=1 (specs/p1-REARM.md).
set -u
for i in 2 3 4 5 6 7 8; do
  echo "== T1F-$i START $(date -u +%FT%TZ)"
  REARM=1 bash /root/p1/migrate_run.sh "T1F-$i" MB
  echo "== T1F-$i END $(date -u +%FT%TZ)"
done
echo "T1F-CELLS-DONE $(date -u +%FT%TZ)"
