#!/bin/bash
# t2_cell.sh REP -- DR-005 task 2: the mechanism during a stall
# M158 wiring exactly as p1/metastab.sh mode M KEEP=10 (task 1), with:
#   - the state dump at three times: healthy flood (+8 s after FLOOD
#     START), 10 s into the wedge (immediately before REDUCE), and
#     30 s after REDUCE;
#   - the memo's bpftrace per-CQ counter for the whole cell
#     (p1/t2_recovery_probe.sh).
# The devlink rx diagnose is known to return "kernel answers: Invalid
# argument" on this platform (recorded in task 1's cells); every
# attempt at every timepoint is recorded verbatim, and the ethtool -S
# ring/channel counters are captured as the working equivalent.
set -u
REP="${1:?rep}"
IFACE=enp195s0np0
DEV=pci/0000:c3:00.0
O=/root/p1/task2/t2-$REP
mkdir -p "$O"
LOG="$O/cell.env"
echo "CELL START rep=$REP mono=$(awk '{print $1}' /proc/uptime) $(date -u +%FT%TZ)" | tee -a "$LOG"

dump_state() { # $1 = phase label
  local P="$1"
  {
    echo "== DUMP $P mono=$(awk '{print $1}' /proc/uptime) $(date -u +%FT%TZ)"
    echo "-- devlink -j health diagnose $DEV reporter rx"
    devlink -j health diagnose $DEV reporter rx 2>&1
    echo "-- devlink health show $DEV reporter rx"
    devlink health show $DEV reporter rx 2>&1
    echo "-- devlink health dump show $DEV reporter rx"
    devlink health dump show $DEV reporter rx 2>&1
    echo "-- ethtool -S (rx7_/ch7_/oob)"
    ethtool -S $IFACE | grep -E 'rx7_|ch7_|rx_out_of_buffer:|rx_packets_phy:'
    echo "-- /proc/interrupts IRQ 312 line"
    grep -E '^ *312:' /proc/interrupts
    echo "-- JSON fields that exist: (the devlink rx dump output above)"
  } >> "$O/t2-dump-$P.txt" 2>&1
}

# --- wiring: unpin (exactly the task 1 M158 arm) ---
pkill -xc k2_rx 2>/dev/null || true
for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
echo 1 > /sys/class/net/$IFACE/threaded
for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); case "$c" in napi/enp195s0np0-*) taskset -pc 0-63 "${p#/proc/}" >/dev/null 2>&1 ;; esac; done
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
echo 8 > /proc/irq/$IRQ/smp_affinity_list
echo "irq=$IRQ (cpu 8), threaded=1, kthreads 0-63" >> "$LOG"

# --- the whole-cell CQ probe (the memo's bpftrace) ---
bash /root/p1/t2_recovery_probe.sh "$O/cq-events.txt" 330 &
BPID=$!
bash /root/k2/tracewatch.sh "$O/counters.log" &
CW_PID=$!

# --- consumer + the task 1 M158 flood ---
/root/k2/k2_rx --port 7777 --core 8 --secs 400 --skip 0 > "$O/consumer.txt" 2> "$O/consumer.err" &
APP=$!
sleep 1
for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
  o=${pair%%:*}; s=${pair##*:}
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport $s --dport 7777 --rate 158000 --secs 400 --plen 64 --core 4 > /tmp/t2-snd-$o.txt 2>&1 </dev/null &'"
  sleep 0.4
done
TFLOOD=$(awk '{print $1}' /proc/uptime)
echo "FLOOD START mono=$TFLOOD" | tee -a "$LOG"

sleep 8
dump_state healthy-flood

# --- wedge watch (the task 1 detector, unchanged) ---
WEDGE=0
PREV_W=0; PREV_D=0; FLAT=0
for i in $(seq 1 60); do
  sleep 2
  CUR=$(ethtool -S $IFACE | grep -E 'rx7_packets:|rx_out_of_buffer:')
  W=$(echo "$CUR" | awk '/rx7_packets:/{print $2}')
  D=$(echo "$CUR" | awk '/rx_out_of_buffer:/{print $2}')
  DW=$((W - PREV_W)); DD=$((D - PREV_D))
  if [ "$PREV_W" != 0 ] && [ "$DW" -eq 0 ] && [ "$DD" -gt 50000 ]; then FLAT=$((FLAT + 1)); else FLAT=0; fi
  PREV_W=$W; PREV_D=$D
  if [ "$FLAT" -ge 3 ]; then WEDGE=1; TW=$(awk '{print $1}' /proc/uptime); echo "WEDGE mono=$TW rx7=$W oob=$D" | tee -a "$LOG"; break; fi
done
[ "$WEDGE" = 0 ] && echo "NO-WEDGE in 120s" | tee -a "$LOG"
if [ "$WEDGE" = 1 ]; then
  sleep 10
  dump_state wedge-plus-10s
fi

# --- REDUCE to the kept sender, then the task 1 monitor ---
for o in 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
echo "REDUCE mono=$(awk '{print $1}' /proc/uptime) keep=10" | tee -a "$LOG"
sleep 30
dump_state reduce-plus-30s

NEED=$((158000 * 2 * 9 / 10))
PREV_W=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}'); OK=0; REC=0
for i in $(seq 1 60); do
  sleep 2
  W=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  DW=$((W - PREV_W)); PREV_W=$W
  if [ "$DW" -ge "$NEED" ]; then OK=$((OK + 1)); else OK=0; fi
  if [ "$OK" -ge 3 ]; then REC=1; echo "RECOVERED mono=$(awk '{print $1}' /proc/uptime)" | tee -a "$LOG"; break; fi
done
[ "$REC" = 0 ] && echo "NOT-RECOVERED-120s" | tee -a "$LOG"

# --- task 1 step 2.7 probe (does the queue come back at 10k?) ---
for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
sleep 20
P0=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
echo "PROBE START mono=$(awk '{print $1}' /proc/uptime) rx7=$P0" | tee -a "$LOG"
ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 30 --plen 64 --core 4 > /tmp/t2-probe.txt 2>&1 </dev/null &'"
sleep 32
P1=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
ADV=$((P1 - P0))
if [ "$ADV" -ge 270000 ]; then echo "PROBE-OK adv=$ADV" | tee -a "$LOG"; else echo "PROBE-DEAD adv=$ADV" | tee -a "$LOG"; fi

kill $CW_PID 2>/dev/null || true
pkill -xc k2_rx 2>/dev/null || true
echo "T_END mono=$(awk '{print $1}' /proc/uptime)" >> "$LOG"
echo "CELL DONE rep=$REP $(date -u +%FT%TZ)"
