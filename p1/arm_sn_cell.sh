#!/bin/bash
# p1/arm_sn_cell.sh -- one DR-012 step-2 cell: migrate_run.sh <cell> <arm>
# plus the eq-filtered completion-event logger, re-derived per cell from
# the discovered ch address. The logger starts as soon as the ch address
# appears (post-discovery), so it covers the probe window.
set -u
CELL="${1:?cellname}"; RUNARM="${2:?HOP|SMOKE}"
D=/root/p1/migrate/$CELL
bash /root/p1/migrate_run.sh "$CELL" "$RUNARM" &
RP=$!
CH=""
for i in $(seq 1 90); do
  CH=$(grep -m1 -oE 'ch7=0x[0-9a-f]+' "$D/cell.log" 2>/dev/null | cut -d= -f2)
  case "$CH" in 0x[0-9a-f]*) break;; esac
  sleep 2
done
LP=""
case "$CH" in
  0x[0-9a-f]*)
    EQ=$(sudo python3 /root/p1/eqdump.py "$CH" 2>/dev/null \
         | grep -oE 'EQ=0x[0-9a-f]+' | cut -d= -f2)
    case "$EQ" in
      0x[0-9a-f]*)
        echo "LOGGER eq=$EQ cell=$CELL $(date -u +%FT%TZ)"
        bash /root/p1/arm_sn_logger.sh "$EQ" "$D/eqint.log" 450 &
        LP=$!
        ;;
      *) echo "LOGGER-FAIL eq-empty $CELL";;
    esac
    ;;
  *) echo "LOGGER-SKIP ch-not-found $CELL";;
esac
wait $RP
[ -n "$LP" ] && { kill "$LP" 2>/dev/null; sleep 1; pkill -x bpftrace 2>/dev/null; }
echo "CELL $CELL ARM_SN WRAP $(date -u +%FT%TZ)"
