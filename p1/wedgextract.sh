#!/bin/bash
# wedgextract.sh ARM REP -- extract the two timelines (facts only)
set -u
ARM="${1:?arm}"; REP="${2:-1}"
O=/root/p1/wedgetrace/wedge-$ARM-$REP
D="$O/wedge-$ARM-$REP.dat"
[ -s "$D" ] || { echo "no trace"; exit 1; }
trace-cmd report "$D" > "$O/report.txt" 2>/dev/null
TW=$(awk -F= '/WEDGE/{print $2}' "$O/cell.env" | awk '{print $1}' | head -1)
TS=$(awk -F= '/FLOOD STOP/{print $2}' "$O/cell.env" | awk '{print $1}' | head -1)
TP=$(awk -F= '/PROBE START/{print $2}' "$O/cell.env" | awk '{print $1}' | head -1)
echo "== onset window: wedge at mono $TW (facts only)" > "$O/timeline-onset.txt"
awk -v t="$TW" 'NF>2 {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) {ts=$i; gsub(":","",ts); if (ts > t-1.5 && ts < t+0.5) print}}' "$O/report.txt" | grep -E "napi_poll|irq_handler_entry|softirq|sched_wakeup|sched_switch|mlx5e|napi_complete|__napi_schedule" | tail -200 >> "$O/timeline-onset.txt"
echo "== counters around onset" >> "$O/timeline-onset.txt"
awk -v t="$TW" '/^@ /{ts=$2; show=(ts>t-3 && ts<t+1)} show' "$O/counters.log" >> "$O/timeline-onset.txt"
echo "== recovery window: flood stop at mono $TS, probe at mono $TP (facts only)" > "$O/timeline-recovery.txt"
awk -v t="$TS" 'NF>2 {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) {ts=$i; gsub(":","",ts); if (ts > t-0.3 && ts < t+2.5) print}}' "$O/report.txt" | grep -E "napi_poll|irq_handler_entry|softirq|sched_wakeup|mlx5e|napi_complete|__napi_schedule" | head -120 >> "$O/timeline-recovery.txt"
echo "-- probe window" >> "$O/timeline-recovery.txt"
awk -v t="$TP" 'NF>2 {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) {ts=$i; gsub(":","",ts); if (ts > t-0.2 && ts < t+1.5) print}}' "$O/report.txt" | grep -E "napi_poll|irq_handler_entry|softirq|sched_wakeup|mlx5e|napi_complete|__napi_schedule" | head -80 >> "$O/timeline-recovery.txt"
echo "== counters around recovery" >> "$O/timeline-recovery.txt"
awk -v t="$TS" '/^@ /{ts=$2; show=(ts>t-3 && ts<t+2)} show' "$O/counters.log" >> "$O/timeline-recovery.txt"
wc -l "$O/timeline-onset.txt" "$O/timeline-recovery.txt"
