#!/bin/bash
# p1batch.sh -- run a queue of p1-LADDER cells sequentially (root on rx).
# usage: p1batch.sh LISTFILE TAG
# LISTFILE lines: POLICY WORKLOAD RATE PLEN REP [WARM] [MEAS]
# Blank lines and #comments skipped. Detach it:
#   nohup bash /root/k2/p1batch.sh /root/k2/list.txt TAG \
#     > /root/p1/batch-TAG.log 2>&1 &
set -u
LIST=${1:?list}; TAG=${2:?tag}
echo "BATCH START $TAG $(date -u +%FT%TZ) list=$LIST"
while read -r pol work rate plen rep warm meas; do
  case "$pol" in \#*|"") continue ;; esac
  bash /root/k2/p1cell.sh "$pol" "$work" "$rate" "$plen" "$rep" "$TAG" ${warm:-10} ${meas:-60} \
    || echo "CELL FAILED: $pol $work $rate $plen $rep"
done < "$LIST"
echo "BATCH DONE $TAG $(date -u +%FT%TZ)"
