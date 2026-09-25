#!/bin/bash
# metastab_batch.sh -- DR-005 task 1 step 3 batch
# Order (the memo): B316, M316, B158, M158, repeated for 5 rounds.
# The smoke cells are rep 1 of B316 (B2-1) and M316 (M2-1); this batch
# runs B316/M316 reps 2-5 and B158/M158 reps 1-5, so every cell type
# ends with exactly 5 reps.
# After every M cell that ends PROBE-DEAD (or NOT-RECOVERED), the DR-005
# step 4 recovery runs and is logged in the cell's directory: stop
# senders, threaded 0 -> 5 s -> 1, probe; if still dead a genuine
# channel recreation (32 -> 16 -> 32) + the full pre-flight (RSS table
# capture, IRQ 312 -> CPU 8, threaded NAPI on), then probe again. The
# queue-7 port map is verified by the probe itself (sport 32704 must
# advance rx7).
set -u
REPO=/mnt/davidlin-personal/cloudlab-profile
exec >> /root/p1/metastab/batch.log 2>&1
echo "BATCH START $(date -u +%FT%TZ)"

recover() { # $1 = cell dir
  local CELL="$1" IFACE=enp195s0np0
  echo "STEP4 $(date -u +%FT%TZ) cell=$CELL"
  for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
  pkill -xc k2_rx 2>/dev/null || true
  echo 0 > /sys/class/net/$IFACE/threaded; sleep 5; echo 1 > /sys/class/net/$IFACE/threaded; sleep 5
  P0=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 8 --plen 64 --core 4 > /tmp/batch-probe.txt 2>&1 </dev/null &'"
  sleep 10
  P1=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  echo "probe after threaded toggle adv=$((P1 - P0))" | tee -a "$CELL/step4-reset.log"
  if [ $((P1 - P0)) -ge 14000 ]; then echo "STEP4 RECOVERED-BY-THREADED-TOGGLE" | tee -a "$CELL/step4-reset.log"; return; fi
  ethtool -L $IFACE combined 16; sleep 3; ethtool -L $IFACE combined 32; sleep 3
  ethtool -x $IFACE > "$CELL/step4-rss.txt" 2>&1
  echo 1 > /sys/class/net/$IFACE/threaded
  IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
  echo 8 > /proc/irq/$IRQ/smp_affinity_list
  sleep 2
  P2=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 8 --plen 64 --core 4 > /tmp/batch-probe2.txt 2>&1 </dev/null &'"
  sleep 10
  P3=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  echo "probe after channel recreation adv=$((P3 - P2))" | tee -a "$CELL/step4-reset.log"
  if [ $((P3 - P2)) -ge 14000 ]; then echo "STEP4 RECOVERED-BY-CHANNEL-RECREATION" | tee -a "$CELL/step4-reset.log"; else echo "STEP4 STILL-DEAD -- escalate" | tee -a "$CELL/step4-reset.log"; fi
}

run_cell() { # $1=MODE $2=KEEP $3=REP
  NKEEP=$(echo $2 | wc -w)
  local CELL=/root/p1/metastab/$1$NKEEP-$3
  if grep -q 'PROBE-' "$CELL/cell.env" 2>/dev/null; then
    echo "== cell $1 '$2' rep $3 SKIP (already has its probe verdict)"; return
  fi
  echo "== cell $1 '$2' rep $3 $(date -u +%FT%TZ)"
  bash /root/p1/metastab.sh "$1" "$2" "$3"
  if [ "$1" = M ]; then
    if grep -q 'PROBE-DEAD\|NOT-RECOVERED' "$CELL/cell.env" 2>/dev/null; then
      recover "$CELL"
    fi
  fi
}

for r in 1 2 3 4 5; do
  if [ "$r" != 1 ]; then run_cell B "10 11" $r; fi   # rep 1 = the smoke
  if [ "$r" != 1 ]; then run_cell M "10 11" $r; fi
  run_cell B "10" $r
  run_cell M "10" $r
done
echo "BATCH DONE $(date -u +%FT%TZ)"
