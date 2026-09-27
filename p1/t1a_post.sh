#!/bin/bash
# p1/t1a_post.sh -- per-T1A-cell post: the DR-011 classification +
# the T1a per-gap branch calls. Outputs t1a.txt per cell dir and
# echoes the summaries.
set -u
for n in 1 2 3 4 5 6; do
  C=/root/p1/migrate/T1A-$n
  [ -d "$C" ] || continue
  PID=$(grep -m1 -oE 'napi_pid=[0-9]+' "$C/cell.log" | cut -d= -f2)
  CHA=$(grep -m1 -oE 'ch7=0x[0-9a-f]+' "$C/cell.log" | cut -d= -f2)
  NA=$(python3 -c "print(hex(int('$CHA', 16) + 10000))")
  python3 /root/p1/migrate_analyze.py "$C/probe.csv" \
    /root/p1/metastab/M1-T1A-$n/metastab-M1-T1A-$n.dat "$PID" "$NA" \
    > "$C/analyze.txt" 2>/dev/null
  python3 /root/p1/t1a_analyze.py "$C/probe.csv" "$C/analyze.txt" \
    "$C/eqint.log" "$C/probe.meta" >> "$C/t1a.txt" 2>&1
  echo "== T1A-$n"
  grep -E "probe:|CLASS SUMMARY" "$C/analyze.txt"
  cat "$C/t1a.txt"
  echo
done