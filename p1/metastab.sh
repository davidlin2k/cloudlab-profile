#!/bin/bash
# metastab.sh MODE KEEP REP -- DR-005 task 1 metastability cell
# A copy of p1/wdiagtrace.sh with exactly the changes in DR-005 step 2:
#  1. args MODE (M|B), KEEP ("10" or "10 11"), REP; out /root/p1/metastab/$MODE$NKEEP-$REP
#  2. only the unpin arm's wiring block is kept
#  3. trace-cmd removed by default; TRACE=1 enables it (M316 rep 1 only)
#  4. senders --secs 400; k2_rx --secs 400
#  5. mode B: only the kept senders, then the monitor 120 s, no flood,
#     no wedge detection
#  6. mode M: after WEDGE hold 10 s; the monitor kills the non-KEEP
#     senders, logs REDUCE, then watches 120 s
#  7. afterwards both modes: stop all senders, wait 20 s, 10k probe from
#     .10 for 30 s; PROBE-OK if rx7 advanced >= 270000
#  8. mechanism snapshot M316 rep 1 only, 30 s after REDUCE
set -u
MODE="${1:?mode M|B}"; KEEP="${2:?keep e.g. \"10\" or \"10 11\"}"; REP="${3:-1}"
WIRE="${4:-unpin}"   # unpin (A1 default) | pin8 (E2 verified-aligned: ch7
                     # kthread pinned to its IRQ core, cpu 8)
THREADED="${5:-1}"   # A4 runs 0 (default inline softirq NAPI)
CORE="${6:-8}"       # k2_rx consumer core (A5 runs a non-IRQ core)
RATE="${7:-158000}"  # per-sender flood rate (A6 runs 105000 = 525k total)
QUIET="${8:-20}"     # seconds after senders stop, before the probe
                     # (A0 runs 300, with a 1 Hz quiet-window sampler)
case "$MODE" in M|B) ;; *) echo "bad mode"; exit 2 ;; esac
case "$WIRE" in unpin|pin8) ;; *) echo "bad wire"; exit 2 ;; esac
case "$THREADED" in 0|1) ;; *) echo "bad threaded"; exit 2 ;; esac
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
NKEEP=$(echo $KEEP | wc -w)
O=/root/p1/metastab/$MODE$NKEEP-$REP
rm -rf "$O"; mkdir -p "$O"
T0=$(awk '{print $1}' /proc/uptime)
echo "CELL START mode=$MODE keep=$KEEP rep=$REP mono=$T0 $(date -u +%FT%TZ)" | tee -a "$O/cell.env"

# --- cleanup (same as wdiagtrace.sh) ---
pkill -xc k2_rx 2>/dev/null || true
pkill -xc k5blast 2>/dev/null || true
for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
for p in $(pgrep -x trace-cmd); do kill -9 $p 2>/dev/null; done
sleep 1

# --- wiring block: unpin (A1) or pin8 (E2 verified-aligned) ---
NICPU=none; IRQC=8
echo "$THREADED" > /sys/class/net/$IFACE/threaded
for p in /proc/[0-9]*; do
  c=$(cat "$p/comm" 2>/dev/null)
  case "$c" in
    napi/enp195s0np0-8263)
      if [ "$WIRE" = pin8 ]; then
        taskset -pc 8 "${p#/proc/}" >/dev/null 2>&1 || true
      else
        taskset -pc 0-63 "${p#/proc/}" >/dev/null 2>&1 || true
      fi ;;
    napi/enp195s0np0-*)
      taskset -pc 0-63 "${p#/proc/}" >/dev/null 2>&1 || true ;;
  esac
done
NAPI_PID=none
for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); if [ "$c" = "napi/enp195s0np0-8263" ]; then NAPI_PID="${p#/proc/}"; fi; done
if [ "$WIRE" = pin8 ]; then
  taskset -pc 8 "$NAPI_PID" > "$O/ni-pin.txt" 2>&1
else
  taskset -pc 0-63 "$NAPI_PID" > "$O/ni-pin.txt" 2>&1
fi
echo "$IRQC" > /proc/irq/$IRQ/smp_affinity_list
sleep 1
echo "irq=$IRQ napi_pid=$NAPI_PID mode=$MODE keep=$KEEP rep=$REP wire=$WIRE" > "$O/affinity-pre.txt"
echo "smp_affinity_list: $(cat /proc/irq/$IRQ/smp_affinity_list)" >> "$O/affinity-pre.txt"
echo "effective_affinity_list: $(cat /proc/irq/$IRQ/effective_affinity_list 2>/dev/null || echo n/a)" >> "$O/affinity-pre.txt"
echo "napi_aff: $(awk '/Cpus_allowed_list/{print $2}' /proc/$NAPI_PID/status 2>/dev/null)" >> "$O/affinity-pre.txt"

# --- tracing only with TRACE=1 (DR-005 step 2.3) ---
TRACE_PID=none
if [ "${TRACE:-0}" = 1 ]; then
  echo nop > /sys/kernel/tracing/current_tracer 2>/dev/null || true
  trace-cmd record -C mono -b 262144 -o "$O/metastab-$MODE$NKEEP-$REP.dat" \
    -e napi:napi_poll -e irq:irq_handler_entry -f "irq == 312" \
    -e irq:softirq_entry -f "vec == 3" -e irq:softirq_exit -f "vec == 3" \
    -e sched:sched_wakeup -e sched:sched_switch -e sched:sched_migrate_task \
    -p function -l mlx5e_napi_poll -l mlx5e_completion_event \
    -l napi_complete_done -l __napi_schedule &
  TRACE_PID=$!
fi
bash /root/k2/tracewatch.sh "$O/counters.log" &
CW_PID=$!
sleep 1

# --- consumer (DR-005 step 2.4: 400 s) ---
/root/k2/k2_rx --port 7777 --core "$CORE" --secs 400 --skip 0 > "$O/consumer.txt" 2> "$O/consumer.err" &
APP=$!
sleep 1

# --- the monitor (DR-005 step 2.5/2.6, verbatim block) ---
monitor() {
NKEEP=$(echo $KEEP | wc -w)
for o in 10 11 12 13 14; do
  case " $KEEP " in *" $o "*) continue ;; esac
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true
done
echo "REDUCE mono=$(awk '{print $1}' /proc/uptime) keep=$KEEP" | tee -a "$O/cell.env"
NEED=$((NKEEP * 158000 * 2 * 9 / 10))   # packets per 2 s sample at 90% of the kept rate
PREV_W=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}'); OK=0; REC=0
for i in $(seq 1 60); do
  sleep 2
  W=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  DW=$((W - PREV_W)); PREV_W=$W
  if [ "$DW" -ge "$NEED" ]; then OK=$((OK + 1)); else OK=0; fi
  if [ "$OK" -ge 3 ]; then REC=1; echo "RECOVERED mono=$(awk '{print $1}' /proc/uptime)" | tee -a "$O/cell.env"; break; fi
done
[ "$REC" = 0 ] && echo "NOT-RECOVERED-120s" | tee -a "$O/cell.env"
}

snap_m316() {
  # DR-005 step 2.8: M316 rep 1 only, 30 s after REDUCE; the device
  # handle and reporter name are confirmed first; failures are recorded
  if [ "$MODE" = M ] && [ "$KEEP" = "10 11" ] && [ "$REP" = 1 ]; then
    sleep 30
    devlink dev show > "$O/devlink-dev.txt" 2>&1
    devlink health > "$O/devlink-health.txt" 2>&1
    devlink -j health diagnose pci/0000:c3:00.0 reporter rx > "$O/rx-diag-reduced.json" 2>&1
    ethtool -S $IFACE | grep -E '^ +(rx7_|ch7_)|rx_out_of_buffer' > "$O/ethtool-reduced.txt" 2>&1
  fi
}

send_k5() { # o sport rate secs
  ssh -n -o ControlPath=/tmp/p1mux-%r@%h -o ControlPersist=600 -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$1 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $1 --sport $2 --dport 7777 --rate $3 --secs $4 --plen 64 --core 4 > /tmp/metastab-snd-$1.txt 2>&1 </dev/null &'"
  sleep 0.4
}

if [ "$MODE" = B ]; then
  # mode B: only the kept senders; no flood; no wedge detection
  for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
    o=${pair%%:*}; s=${pair##*:}
    case " $KEEP " in *" $o "*) send_k5 $o $s 158000 400 ;; esac
  done
  TFLOOD=$(awk '{print $1}' /proc/uptime)
  echo "B-START (kept only) mono=$TFLOOD keep=$KEEP" | tee -a "$O/cell.env"
  snap_m316 & SNAP_PID=$!    # no-op in mode B, kept for symmetry
  monitor
else
  # mode M: full flood RATE*5 until WEDGE, hold 10 s, then the monitor
  for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
    o=${pair%%:*}; s=${pair##*:}
    send_k5 $o $s "$RATE" 400
  done
  TFLOOD=$(awk '{print $1}' /proc/uptime)
  echo "FLOOD START mono=$TFLOOD" | tee -a "$O/cell.env"
  WEDGE=0
  PREV_W=0; PREV_D=0; FLAT=0
  for i in $(seq 1 60); do
    sleep 2
    CUR=$(ethtool -S $IFACE | grep -E 'rx7_packets:|rx_out_of_buffer:|rx_packets_phy:')
    W=$(echo "$CUR" | awk '/rx7_packets:/{print $2}')
    D=$(echo "$CUR" | awk '/rx_out_of_buffer:/{print $2}')
    DW=$((W - PREV_W)); DD=$((D - PREV_D))
    if [ "$PREV_W" != 0 ] && [ "$DW" -eq 0 ] && [ "$DD" -gt 50000 ]; then FLAT=$((FLAT + 1)); else FLAT=0; fi
    PREV_W=$W; PREV_D=$D
    if [ "$FLAT" -ge 3 ]; then WEDGE=1; TW=$(awk '{print $1}' /proc/uptime); echo "WEDGE mono=$TW rx7=$W oob=$D" | tee -a "$O/cell.env"; break; fi
  done
  if [ "$WEDGE" = 0 ]; then echo "NO-WEDGE in 120s" | tee -a "$O/cell.env"; fi
  sleep 10
  snap_m316 & SNAP_PID=$!
  monitor
fi

# --- step 2.7: stop all senders, wait QUIET, then 10k probe 30 s from .10 ---
# (A0's amendment: QUIET >= 60 gets a 1 Hz quiet-window sampler; the
# outcome rule needs rx7 advance over the whole quiet window)
for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
if [ "$QUIET" -ge 60 ]; then
  # amendment A quiet-window sampler: 1 Hz rx7_packets / rx_out_of_buffer
  ( for i in $(seq 1 "$QUIET"); do
      L=$(ethtool -S $IFACE 2>/dev/null | awk -F': ' '/rx7_packets:/{w=$2} /rx_out_of_buffer:/{o=$2} END{print strftime("%H:%M:%S")","w","o}')
      echo "$L"
      sleep 1
    done ) > "$O/quiet.csv" 2>&1 &
  QPID=$!
fi
sleep "$QUIET"
if [ -n "${QPID:-}" ]; then wait $QPID 2>/dev/null; echo "QUIET-WINDOW-LOGGED sec=$QUIET" >> "$O/cell.env"; fi
TP=$(awk '{print $1}' /proc/uptime)
P0=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
echo "PROBE START mono=$TP rx7=$P0" | tee -a "$O/cell.env"
send_k5 10 32704 10000 30
sleep 32
P1=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
ADV=$((P1 - P0))
if [ "$ADV" -ge 270000 ]; then echo "PROBE-OK adv=$ADV" | tee -a "$O/cell.env"; else echo "PROBE-DEAD adv=$ADV" | tee -a "$O/cell.env"; fi
wait $SNAP_PID 2>/dev/null || true   # NOT a bare wait: CW_PID never exits

# --- teardown (as wdiagtrace.sh) ---
if [ "$TRACE_PID" != none ]; then
  kill -INT $TRACE_PID 2>/dev/null || true
  for i in $(seq 1 30); do kill -0 $TRACE_PID 2>/dev/null || break; sleep 1; done
  if [ -s "$O/metastab-$MODE$NKEEP-$REP.dat" ]; then echo "TRACE-OK" >> "$O/cell.env"; else echo "TRACE-MISSING" >> "$O/cell.env"; fi
  for p in $(pgrep -x trace-cmd); do kill -9 $p 2>/dev/null; done
fi
kill $CW_PID 2>/dev/null || true
pkill -xc k2_rx 2>/dev/null || true
echo "T_END mono=$(awk '{print $1}' /proc/uptime)" >> "$O/cell.env"
echo "CELL DONE mode=$MODE keep=$KEEP rep=$REP $(date -u +%FT%TZ)"
