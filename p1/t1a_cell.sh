#!/bin/bash
# p1/t1a_cell.sh -- one DR-013 T1a cell: the pin46 arm (SWEEP wiring,
# SWEEP_CPU=46) with T1A=1 (the probe carries the EQ columns) plus
# the v2 logger (the E/I timelines), re-derived per cell from the
# discovered ch address. The logger is NOT killed at the metastab
# wrap: the probe runs 330 s and the logger must cover its window --
# the runner waits for the probe process to exit first.
set -u
CELL="${1:?cellname T1A-n}"
D=/root/p1/migrate/$CELL
T1A=1 SWEEP_CPU=46 bash /root/p1/migrate_run.sh "$CELL" SWEEP &
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
    IRQN=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts \
           | awk '{print $1}' | tr -d ':')
    case "$EQ" in
      0x[0-9a-f]*)
        echo "T1A logger eq=$EQ irq=$IRQN cell=$CELL $(date -u +%FT%TZ)"
        bash /root/p1/arm_sn_logger.sh "$EQ" "$IRQN" "$D/eqint.log" 450 &
        LP=$!
        ;;
      *) echo "T1A-LOGGER-FAIL eq='$EQ'";;
    esac
    ;;
  *) echo "T1A-LOGGER-SKIP ch-not-found";;
esac
wait $RP
# the probe outlives the metastab cell; wait for IT, then stop the logger
while pgrep -f "rq1_probe[.]py.*$CELL" >/dev/null; do sleep 10; done
[ -n "$LP" ] && { kill "$LP" 2>/dev/null; pkill -x bpftrace 2>/dev/null; }
echo "T1A CELL $CELL WRAP $(date -u +%FT%TZ)"