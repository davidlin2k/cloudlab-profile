#!/bin/bash
# p1/sweep_classify.sh -- classify the DR-012 step-3 sweep cells
# (the trace join per cell), counts into sweep-classify.txt.
set -u
OUT=/root/p1/migrate/sweep-classify.txt
: > "$OUT"
for c in PT10-1 PT10-2 PT10-3 PT10-4 PT10-5 PT10-6 PT10-7 PT10-8 \
         PT24-1 PT24-2 PT24-3 PT24-4 PT24-5 PT24-6 PT24-7 PT24-8; do
  PID=$(grep -m1 -oE 'napi_pid=[0-9]+' /root/p1/migrate/$c/cell.log | cut -d= -f2)
  CHA=$(grep -m1 -oE 'ch7=0x[0-9a-f]+' /root/p1/migrate/$c/cell.log | cut -d= -f2)
  NA=$(python3 -c "print(hex(int('$CHA', 16) + 10000))")
  python3 /root/p1/migrate_analyze.py \
    /root/p1/migrate/$c/probe.csv \
    /root/p1/metastab/M1-$c/metastab-M1-$c.dat "$PID" "$NA" 2>/dev/null \
    | grep -E 'probe:|CLASS SUMMARY' | sed "s/^/$c /" >> "$OUT"
done
echo "SWEEP CLASSIFY DONE" >> "$OUT"
cat "$OUT"
