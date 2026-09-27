#!/bin/bash
# p1/hop_sweep.sh -- the v2 decisive statistic across all HOP cells.
set -u
OUT=/root/p1/migrate/hop-gaps.txt
: > "$OUT"
for d in /root/p1/migrate/HOP-*/; do
  c=$(basename "$d")
  [ -f "$d/probe.csv" ] || continue
  HC="$d/hops.csv"
  [ -f "$HC" ] || HC="-"
  echo "== $c" >> "$OUT"
  python3 /root/p1/hop_gap_analyze.py "$d/probe.csv" "$HC" 2>/dev/null \
    | grep -E "^SUMMARY" >> "$OUT"
done
echo "HOP SWEEP DONE" >> "$OUT"
