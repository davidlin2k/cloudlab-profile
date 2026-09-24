#!/bin/bash
# p1after.sh -- chain the fig1-3 analysis when the batch prints its
# final BATCH DONE (root on rx). Poll for /root/p1/FIG13-READY.
set -u
LOG=/root/p1/batch-fig1-3r.log
for i in $(seq 1 720); do
  grep -q "BATCH DONE" "$LOG" 2>/dev/null && break
  sleep 30
done
grep -q "BATCH DONE" "$LOG" 2>/dev/null || { echo "TIMEOUT waiting for batch"; exit 1; }
python3 /root/k2/p1_analyze.py fig1-3 > /root/p1/rows-fig1-3.csv 2>/root/p1/rows-fig1-3.err
python3 /root/k2/p1_analyze.py cal-1 > /root/p1/rows-cal-1.csv 2>>/root/p1/rows-fig1-3.err
N=$(grep -c "^fig1-3" /root/p1/rows-fig1-3.csv || true)
FAILS=$(grep -c ", 0," /root/p1/rows-fig1-3.csv 2>/dev/null || true)
echo "rows=$N gate_fail_rows=$FAILS" > /root/p1/FIG13-READY
echo "p1after done: rows=$N"
