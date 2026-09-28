#!/bin/bash
# p1/t1b_driver.sh -- run one pair's 16 T1B cells (specs/p1-T1B.md).
# Usage (as root, ON the DUT):
#   t1b_driver.sh <PAIR P1|P2> <SENDER_IP> <DUT_IP> <IFACE> <IRQCPU>
# Block orders come from /root/p1/t1b_orders_<PAIR>.txt (frozen,
# committed in the repo before the first cell).  One results row per
# cell is appended to /root/p1/t1b/results-<PAIR>.csv.
set -u
PAIR=${1:?P1|P2}; SENDER=${2:?sender ip}; DUTIP=${3:?dut ip}
IFACE=${4:-enp24s0f1np1}; IRQCPU=${5:-6}
T=/root/p1/t1b
mkdir -p "$T"
RES=$T/results-$PAIR.csv
LOG=$T/driver-$PAIR.log
echo "cell,arm,verdict,max_strand_ms,pkts_delta,sent,drops_delta,pending_rows,rows" > "$RES"
ORDS=$T/t1b_orders_$PAIR.txt
[ -s "$ORDS" ] || { echo "T1B-DRIVER-$PAIR-FAIL: $ORDS missing"; exit 1; }

for b in 1 2 3 4; do
  line=$(sed -n "${b}p" "$ORDS")
  for arm in $line; do
    cell=${PAIR}-B${b}-${arm}
    echo "== $cell arm=$arm $(date -u +%FT%TZ)" | tee -a "$LOG"
    env IFACE=$IFACE SENDER=$SENDER DUTIP=$DUTIP IRQCPU=$IRQCPU Q=7 \
      bash /root/p1/t1b_run.sh "$cell" "$arm" >> "$LOG" 2>&1
    D=$T/$cell
    meta=$(cat "$D/probe.meta" 2>/dev/null)
    verdict=$(echo "$meta" | grep -oE "verdict=[a-z-]+" | cut -d= -f2)
    ms=$(echo "$meta" | grep -oE "max_strand=[0-9.]+" | cut -d= -f2)
    read -r pkts0 pkts1 drops0 drops1 pend rows < <(
      awk -F, 'NR>1{r++; if(r==1){p0=$8; d0=$10} p=$8; d=$10; if($7=="1") pe++}
               END{print p0+0, p+0, d0+0, d+0, pe+0, r+0}' "$D/probe.csv" 2>/dev/null)
    sent=$(ssh -n -o BatchMode=yes -o ConnectTimeout=8 \
             -o StrictHostKeyChecking=no "davidlin@$SENDER" \
             "tail -1 /tmp/flood-$cell.txt 2>/dev/null" 2>/dev/null \
             | grep -oE "sent=[0-9]+" | cut -d= -f2)
    echo "$cell,$arm,${verdict:-none},${ms:-0},$((pkts1-pkts0)),${sent:-0},$((drops1-drops0)),$pend,$rows" >> "$RES"
    sleep 30
  done
done
echo "T1B-DRIVER-$PAIR-DONE $(date -u +%FT%TZ)" >> "$RES"
echo "T1B-DRIVER-$PAIR-DONE"
cat "$RES"