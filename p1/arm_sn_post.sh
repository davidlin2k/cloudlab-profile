#!/bin/bash
# p1/arm_sn_post.sh -- per-cell DR-012 step-2 post-processing:
#   1. the DR-011 gap classification (migrate_analyze.py, full output
#      kept in the cell dir),
#   2. the stale-arm statistic (arm_sn_analyze.py) joined with it.
# Usage: arm_sn_post.sh <cell>
set -u
CELL="${1:?cellname}"
D=/root/p1/migrate/$CELL
PID=$(grep -m1 -oE "napi_pid=[0-9]+" "$D/cell.log" | cut -d= -f2)
CHA=$(grep -m1 -oE "ch7=0x[0-9a-f]+" "$D/cell.log" | cut -d= -f2)
NA=$(python3 -c "print(hex(int('$CHA',16)+10000))")
python3 /root/p1/migrate_analyze.py "$D/probe.csv" \
  "/root/p1/metastab/M1-$CELL/metastab-M1-$CELL.dat" "$PID" "$NA" \
  > "$D/analyze.txt" 2>&1
python3 /root/p1/arm_sn_analyze.py "$D/probe.csv" "$D/analyze.txt" \
  > "$D/arm_sn.txt" 2>&1
echo "== $CELL"
grep -E "^probe:|^CLASS SUMMARY" "$D/analyze.txt"
tail -2 "$D/arm_sn.txt"
