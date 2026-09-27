#!/bin/bash
# p1/v1_classify.sh -- classify all v1 MIGRATE cells (detached).
set -u
OUT=/root/p1/migrate/v1-classify.txt
: > "$OUT"
for c in MA-1 MA-2 MA-3 MA-4 MA-5 MA-6 MA-7 MA-8 \
         MB-1 MB-2 MB-3 MB-4 MB-5 MB-6 MB-7 MB-8; do
  PID=$(grep -m1 -oE "napi_pid=[0-9]+" /root/p1/migrate/$c/cell.log | cut -d= -f2)
  CHA=$(grep -m1 -oE "ch7=0x[0-9a-f]+" /root/p1/migrate/$c/cell.log | cut -d= -f2)
  NA=$(python3 -c "print(hex(int('$CHA',16)+10000))")
  echo "== $c pid=$PID napi=$NA" >> "$OUT"
  python3 /root/p1/migrate_analyze.py \
    /root/p1/migrate/$c/probe.csv \
    /root/p1/metastab/M1-$c/metastab-M1-$c.dat \
    "$PID" "$NA" 2>/dev/null | grep -E "stranded|CLASS" >> "$OUT"
done
echo "V1 CLASSIFY DONE" >> "$OUT"
