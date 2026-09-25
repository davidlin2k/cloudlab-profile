#!/bin/bash
# wdiagtrace.sh ARM REP -- DR-004 task 3 wedge tracing cell (v2)
# fixes over v1: unpin arm pins IRQ 312 to CPU 8 (the matrix's wiring);
# tracer reset before record (stuck helpers caused EBUSY); trace-cmd
# helpers killed by exact comm after each cell.
set -u
ARM="${1:?arm}"; REP="${2:-1}"
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
O=/root/p1/wedgetrace/wedge-$ARM-$REP
mkdir -p "$O"
T0=$(awk '{print $1}' /proc/uptime)
echo "CELL START arm=$ARM rep=$REP mono=$T0 $(date -u +%FT%TZ)"

case "$ARM" in
  ali-P4) NICPU=9; IRQC=9 ;;
  unpin)  NICPU=none; IRQC=8 ;;
  *) echo "bad arm"; exit 2 ;;
esac

pkill -xc k2_rx 2>/dev/null || true
pkill -xc k5blast 2>/dev/null || true
for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
for p in $(pgrep -x trace-cmd); do kill -9 $p 2>/dev/null; done
sleep 1
echo 1 > /sys/class/net/$IFACE/threaded
for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); case "$c" in napi/enp195s0np0-*) taskset -pc 0-63 "${p#/proc/}" >/dev/null 2>&1 || true ;; esac; done
NAPI_PID=none
for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); if [ "$c" = "napi/enp195s0np0-8263" ]; then NAPI_PID="${p#/proc/}"; fi; done
if [ "$NICPU" != none ]; then taskset -pc "$NICPU" "$NAPI_PID" > "$O/ni-pin.txt" 2>&1; else taskset -pc 0-63 "$NAPI_PID" > "$O/ni-pin.txt" 2>&1; fi
echo "$IRQC" > /proc/irq/$IRQ/smp_affinity_list
sleep 1
echo "irq=$IRQ napi_pid=$NAPI_PID" > "$O/affinity-pre.txt"
echo "smp_affinity_list: $(cat /proc/irq/$IRQ/smp_affinity_list)" >> "$O/affinity-pre.txt"
echo "effective_affinity_list: $(cat /proc/irq/$IRQ/effective_affinity_list 2>/dev/null || echo n/a)" >> "$O/affinity-pre.txt"
echo "napi_aff: $(awk '/Cpus_allowed_list/{print $2}' /proc/$NAPI_PID/status 2>/dev/null)" >> "$O/affinity-pre.txt"

echo nop > /sys/kernel/tracing/current_tracer 2>/dev/null || true
trace-cmd record -C mono -b 262144 -o "$O/wedge-$ARM-$REP.dat" -e napi:napi_poll -e irq:irq_handler_entry -f "irq == 312" -e irq:softirq_entry -f "vec == 3" -e irq:softirq_exit -f "vec == 3" -e sched:sched_wakeup -e sched:sched_switch -e sched:sched_migrate_task -p function -l mlx5e_napi_poll -l mlx5e_completion_event -l napi_complete_done -l __napi_schedule &
TRACE_PID=$!
bash /root/k2/tracewatch.sh "$O/counters.log" &
CW_PID=$!
sleep 1

/root/k2/k2_rx --port 7777 --core 8 --secs 300 --skip 0 > "$O/consumer.txt" 2> "$O/consumer.err" &
APP=$!
sleep 1
for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
  o=${pair%%:*}; s=${pair##*:}
  ssh -n -o ControlPath=/tmp/p1mux-%r@%h -o ControlPersist=600 -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport $s --dport 7777 --rate 158000 --secs 200 --plen 64 --core 4 > /tmp/wdiag-snd-$o.txt 2>&1 </dev/null &'"
  sleep 0.4
done
TFLOOD=$(awk '{print $1}' /proc/uptime)
echo "FLOOD START mono=$TFLOOD" | tee -a "$O/cell.env"

WEDGE=0
PREV_W=0; PREV_P=0; FLAT=0
for i in $(seq 1 60); do
  sleep 2
  CUR=$(ethtool -S $IFACE | grep -E 'rx7_packets:|ch7_poll:')
  W=$(echo "$CUR" | awk '/rx7_packets:/{print $2}')
  P=$(echo "$CUR" | awk '/ch7_poll:/{print $2}')
  DW=$((W - PREV_W)); DP=$((P - PREV_P))
  if [ "$PREV_W" != 0 ] && [ "$DW" -gt 50000 ] && [ "$DP" -eq 0 ]; then FLAT=$((FLAT + 1)); else FLAT=0; fi
  PREV_W=$W; PREV_P=$P
  if [ "$FLAT" -ge 3 ]; then WEDGE=1; TW=$(awk '{print $1}' /proc/uptime); echo "WEDGE mono=$TW wire=$W poll=$P" | tee -a "$O/cell.env"; break; fi
done
if [ "$WEDGE" = 0 ]; then echo "NO-WEDGE in 120s" | tee -a "$O/cell.env"; fi

if [ "$WEDGE" = 1 ]; then
  sleep 10
  TS=$(awk '{print $1}' /proc/uptime)
  echo "FLOOD STOP mono=$TS" | tee -a "$O/cell.env"
  for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
  sleep 20
  TP=$(awk '{print $1}' /proc/uptime)
  echo "PROBE START mono=$TP" | tee -a "$O/cell.env"
  ssh -n -o ControlPath=/tmp/p1mux-%r@%h -o ControlPersist=600 -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 60 --plen 64 --core 4 > /tmp/wdiag-probe-10.txt 2>&1 </dev/null &'"
  sleep 62
  echo "PROBE END mono=$(awk '{print $1}' /proc/uptime)" | tee -a "$O/cell.env"
fi

kill $TRACE_PID 2>/dev/null || true
sleep 3
for p in $(pgrep -x trace-cmd); do kill -9 $p 2>/dev/null; done
kill $CW_PID 2>/dev/null || true
pkill -xc k2_rx 2>/dev/null || true
echo "T_END mono=$(awk '{print $1}' /proc/uptime)" >> "$O/cell.env"
echo "CELL DONE $ARM rep$REP $(date -u +%FT%TZ)"
