#!/bin/bash
# wedgfind.sh ARM REP v3 -- queue-7-only windows (per-cell kthread pid)
# enp195s0np0 has one threaded-NAPI kthread per queue; all display as
# comm "napi/enp195s0np" in trace-cmd. Queue 7's kthread pid is recorded
# in the cell's affinity-pre.txt at arm time. Filter = its pid + its IRQ
# (every irq_handler_entry line is irq==312 via the record-time filter).
set -u
ARM="${1:?arm}"; REP="${2:-1}"
O=/root/p1/wedgetrace/wedge-$ARM-$REP
R="$O/report.txt"
[ -s "$R" ] || { echo "no report"; exit 1; }
PID=$(sed 's/.*napi_pid=//' "$O/affinity-pre.txt" | tr -d ' ')
TW=$(grep "^WEDGE mono" "$O/cell.env" | head -1 | sed 's/.*mono=//; s/ .*//')
TS=$(grep "^FLOOD STOP mono" "$O/cell.env" | head -1 | sed 's/.*mono=//; s/ .*//')
TP=$(grep "^PROBE START mono" "$O/cell.env" | head -1 | sed 's/.*mono=//; s/ .*//')
PAT="irq_handler_entry|napi/enp195s0np[-:]${PID}"
grep -E "$PAT" "$R" > "$O/q7-events.txt"
NQ7=$(wc -l < "$O/q7-events.txt")
LAST=$(awk -v t="$TW" '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) {ts=$i; gsub(":","",ts); if (ts+0 < t+0 && (last == "" || ts+0 > last+0)) {last=ts}}} END{print last}' "$O/q7-events.txt")
FIRST=$(awk -v t="$TS" '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) {ts=$i; gsub(":","",ts); if (ts+0 > t+0 && first == "") {first=ts}}} END{print first}' "$O/q7-events.txt")
echo "Q7PID=$PID NQ7=$NQ7 TW=$TW LASTQ7=$LAST TS=$TS FIRSTQ7=${FIRST:-none} TP=$TP"
{
echo "== ONSET (facts only): queue-7 events in [last_q7-0.5s, last_q7+0.3s]"
echo "== queue-7 kthread pid $PID; last q7 event at mono $LAST; detector confirmed at $TW"
awk -v a="$LAST" 'BEGIN{lo=a+0-0.5; hi=a+0+0.3} {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) {ts=$i; gsub(":","",ts); if (ts+0 > lo && ts+0 < hi) print; break}}' "$R" | grep -E "$PAT" | tail -60
echo "== counters around the last q7 event"
awk -v t="$LAST" '/^@ /{ts=$2; show=(ts+0 > t+0-3 && ts+0 < t+0+1)} show' "$O/counters.log"
} > "$O/timeline-onset.txt"
{
echo "== RECOVERY (facts only): queue-7 events in [first_q7-1.5s, first_q7+0.5s]"
echo "== flood stop at mono $TS; first q7 event after stop at mono ${FIRST:-none}; probe start at $TP"
awk -v a="${FIRST:-$TP}" 'BEGIN{lo=a+0-1.5; hi=a+0+0.5} {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) {ts=$i; gsub(":","",ts); if (ts+0 > lo && ts+0 < hi) print; break}}' "$R" | grep -E "$PAT" | head -60
echo "== counters around recovery"
awk -v t="${FIRST:-$TP}" '/^@ /{ts=$2; show=(ts+0 > t+0-3 && ts+0 < t+0+1)} show' "$O/counters.log"
} > "$O/timeline-recovery.txt"
wc -l "$O/timeline-onset.txt" "$O/timeline-recovery.txt"
