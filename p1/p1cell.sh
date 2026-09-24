#!/bin/bash
# p1cell.sh -- run ONE p1-LADDER cell (root on rx) and write its
# harness-owned run manifest. usage:
#   p1cell.sh POLICY WORKLOAD RATE PLEN REP TAG [WARM] [MEAS]
# POLICY: P0 P0X P2 P3 P4 (P1 = pre-6.5 kernel, separate batch)
# WORKLOAD: W1 (flood, k2_rx) | W2 (req/resp, k4send -> k2_rx --echo)
# RATE: aggregate offered (W1 pkts/s, W2 rpc/s; divisible by 5)
# PLEN: UDP payload bytes. REP: 1-based. TAG: run-set name.
set -u
POLICY=$1; WORK=$2; RATE=$3; PLEN=$4; REP=$5; TAG=$6
WARM=${7:-10}; MEAS=${8:-60}
TOT=$((WARM + MEAS + 1))
IFACE=enp195s0np0
TQ=7
TXOCTS="10 11 12 13 14"
W1_SPORTS="32704 32726 32706 32724 32725"
W2_LPORTS="33751 33717 33749 33719 33718"
RPS_PER=$((RATE / 5))
N=$((RPS_PER * TOT))
CELL="${WORK}-${POLICY}-r${RATE}-p${PLEN}"
OUT=/root/p1/results/$TAG/$CELL/rep$REP
mkdir -p "$OUT"
exec > >(tee "$OUT/run.log") 2>&1
START_ISO=$(date -u +%FT%TZ)
echo "== p1cell $CELL rep$REP $START_ISO warm=$WARM meas=$MEAS"

# exact-name strays only (pkill -f self-matches the invoking shell)
pkill -xc k2_rx >/dev/null 2>&1; pkill -xc k5blast >/dev/null 2>&1; pkill -xc k4send >/dev/null 2>&1
for o in $TXOCTS; do
  ssh -n -o ControlPath=/tmp/p1mux-%r@%h -o ControlPersist=600 -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
    "sudo pkill -xc k5blast >/dev/null 2>&1; sudo pkill -xc k4send >/dev/null 2>&1; true" 2>/dev/null
done
exec 9>/dev/cpu_dma_latency; echo 0 >&9

POL=$(bash /root/k2/p1pol.sh "$POLICY")
echo "policy: $POL"
NAPI_PID=$(echo "$POL" | sed -n 's/.*napi_pid=\([0-9]*\).*/\1/p')
NAPI_CPU=$(echo "$POL" | sed -n 's/.*napi_cpu=\([0-9]*\).*/\1/p')
APP_CPU=$(echo "$POL" | sed -n 's/.*app_cpu=\([0-9]*\).*/\1/p')

ethtool -S $IFACE | grep -E "rx[0-9]+_packets:|rx_discards:|rx_out_of_buffer:" > "$OUT/nic-pre.txt"
cat /proc/net/softnet_stat > "$OUT/softnet-pre.txt"
cp /proc/stat "$OUT/stat-pre.txt"

CONSUMER=/root/k2/k2_rx
# +2s over the senders: the consumer must outlive their tail so
# conservation closes (analysis uses the 1s window lines for goodput)
CARGS="--core $APP_CPU --secs $((TOT + 2)) --skip $WARM"
if [ "$WORK" = W1 ]; then
  $CONSUMER --port 7777 $CARGS > "$OUT/consumer.txt" 2> "$OUT/consumer.err" &
else
  $CONSUMER --echo --port 7778 $CARGS > "$OUT/consumer.txt" 2> "$OUT/consumer.err" &
fi
APP_PID=$!
bash /root/k2/p1samp.sh "$OUT/cpu.log" "$NAPI_PID" "$APP_PID" $((TOT + 2)) &
SAMP_PID=$!

sleep 1
SPORTS=($W1_SPORTS); LPORTS=($W2_LPORTS); OCTS=($TXOCTS)
for idx in 0 1 2 3 4; do
  o=${OCTS[$idx]}
  if [ "$WORK" = W1 ]; then
    ssh -n -o ControlPath=/tmp/p1mux-%r@%h -o ControlPersist=600 -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
      "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport ${SPORTS[$idx]} --dport 7777 --n $N --rate $RPS_PER --plen $PLEN --core 4 >/tmp/p1snd-$o.txt 2>&1 </dev/null &'" \
      || echo "FAIL launch sender $o"
  else
    ssh -n -o ControlPath=/tmp/p1mux-%r@%h -o ControlPersist=600 -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
      "sudo bash -c 'nohup /root/k2/k4send --dip 10.10.1.1 --sip $o --qmap 0:7778 --lport ${LPORTS[$idx]} --n $N --plen $PLEN --depth 32 --rate $RPS_PER --follow 0 --core 4 --dump /tmp/p1hist-$o.txt >/tmp/p1snd-$o.txt 2>&1 </dev/null &'" \
      || echo "FAIL launch sender $o"
  fi
done

wait $APP_PID
sleep 1
kill $SAMP_PID 2>/dev/null
END_ISO=$(date -u +%FT%TZ)

for o in $TXOCTS; do
  # fetch with retries: ssh bursts throttle and fail silently (skill
  # pitfall) - a missing sender log must never look like a quiet sender
  for try in 1 2 3 4; do
    [ -s "$OUT/sender-$o.txt" ] && grep -q "sent=" "$OUT/sender-$o.txt" && break
    sleep 1
    ssh -n -o ControlPath=/tmp/p1mux-%r@%h -o ControlPersist=600 -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
      "cat /tmp/p1snd-$o.txt" > "$OUT/sender-$o.txt" 2>/dev/null
  done
  if [ "$WORK" = W2 ]; then
    for try in 1 2 3 4; do
      [ -s "$OUT/hist-$o.txt" ] && break
      sleep 1
      ssh -n -o ControlPath=/tmp/p1mux-%r@%h -o ControlPersist=600 -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
        "cat /tmp/p1hist-$o.txt" > "$OUT/hist-$o.txt" 2>/dev/null
    done
  fi
done
ethtool -S $IFACE | grep -E "rx[0-9]+_packets:|rx_discards:|rx_out_of_buffer:" > "$OUT/nic-post.txt"
cat /proc/net/softnet_stat > "$OUT/softnet-post.txt"
cp /proc/stat "$OUT/stat-post.txt"

# ---- gate evaluation (harness-owned; never edited by hand) ----
# sender metrics: SUMMARY lines only ("dip=" for k5blast, "sip=" for
# k4send) - status lines repeat sent= and must not be summed
SENT=$(grep -hE "^\[k5blast\] dip=|^\[k4send\] sip=" "$OUT"/sender-*.txt | sed -n 's/.* sent=\([0-9]*\).*/\1/p' | awk '{s+=$1} END {print s+0}')
ENOB=$(grep -hE "^\[k5blast\] dip=|^\[k4send\] sip=" "$OUT"/sender-*.txt | sed -n 's/.*enobufs=\([0-9]*\).*/\1/p' | awk '{s+=$1} END {print s+0}')
CONS=$(sed -n 's/.* pkts=\([0-9]*\).*/\1/p' "$OUT/consumer.txt")
DROPS=$(sed -n 's/.*sockdrops=\([0-9]*\).*/\1/p' "$OUT/consumer.txt")
MPKTS=$(sed -n 's/.*mpkts=\([0-9]*\).*/\1/p' "$OUT/consumer.txt")
P50=$(sed -n 's/.*p50_us=\([0-9.]*\).*/\1/p' "$OUT/consumer.txt")
RESP=$(grep -hE "^\[k4send\] sip=" "$OUT"/sender-*.txt | sed -n 's/.* resp=\([0-9]*\).*/\1/p' | awk '{s+=$1} END {print s+0}')
CENS=$(grep -hE "^\[k4send\] sip=" "$OUT"/sender-*.txt | sed -n 's/.*censored=\([0-9]*\).*/\1/p' | awk '{s+=$1} END {print s+0}')
ECHOED=$(sed -n 's/.*echoed=\([0-9]*\).*/\1/p' "$OUT/consumer.txt")

# landing: purity of the target queue across per-queue packet counters
python3 - "$OUT/nic-pre.txt" "$OUT/nic-post.txt" "$TQ" > "$OUT/gates.txt" 2>&1 <<'EOF'
import sys, re
def load(p):
    d = {}
    for ln in open(p):
        m = re.match(r"rx(\d+)_packets: (\d+)", ln.strip())
        if m: d[int(m.group(1))] = int(m.group(2))
    return d
pre, post = load(sys.argv[1]), load(sys.argv[2])
tq = int(sys.argv[3])
deltas = {q: post.get(q,0)-pre.get(q,0) for q in post}
tot = sum(deltas.values())
purity = deltas.get(tq,0)/tot if tot else 0.0
print(f"landing_purity={purity:.4f} tq_delta={deltas.get(tq,0)} all_delta={tot}")
EOF
PURITY=$(sed -n 's/.*landing_purity=\([0-9.]*\).*/\1/p' "$OUT/gates.txt")

GATE_CONS=pass; GATE_LAND=pass; GATE_FLOOR=pass; GATE_GEN=pass
for o in $TXOCTS; do
  grep -q "sent=" "$OUT/sender-$o.txt" 2>/dev/null || { GATE_GEN=fail; echo "MISSING sender log $o" >> "$OUT/gates.txt"; }
done
if [ "$WORK" = W1 ]; then
  UNACC=$((SENT - CONS - DROPS))
  ALLOW=$((SENT / 50))          # in-flight at consumer exit: 2%
  if [ "$UNACC" -lt 0 ] || [ "$UNACC" -gt "$ALLOW" ]; then GATE_CONS=fail; fi
  echo "conservation: sent=$SENT consumed=$CONS sockdrops=$DROPS unaccounted=$UNACC allow=$ALLOW" >> "$OUT/gates.txt"
else
  UNACC=$((SENT - CONS - DROPS))
  ALLOW=$((SENT / 50))
  if [ "$UNACC" -lt 0 ] || [ "$UNACC" -gt "$ALLOW" ] || [ "$ECHOED" -ne "$CONS" ]; then GATE_CONS=fail; fi
  echo "conservation: sent=$SENT consumed=$CONS sockdrops=$DROPS echoed=$ECHOED resp=$RESP censored=$CENS unaccounted=$UNACC allow=$ALLOW" >> "$OUT/gates.txt"
fi
awk -v p="$PURITY" 'BEGIN { exit (p+0 >= 0.99) ? 0 : 1 }' || GATE_LAND=fail
if grep -qE "GATE( FAIL|WARN)" "$OUT/consumer.err" "$OUT"/sender-*.txt 2>/dev/null; then GATE_FLOOR=fail; fi
if [ "$ENOB" -ne 0 ]; then GATE_GEN=fail; fi
awk -v s="$SENT" -v r="$RPS_PER" -v t="$TOT" \
  'BEGIN { want = r*5*t; exit (s+0 >= 0.97*want && s+0 <= 1.03*want) ? 0 : 1 }' || GATE_GEN=fail

cat > "$OUT/manifest.json" <<EOF
{
  "run_id": "p1-LADDER/$(date -u +%F)/$CELL/rep$REP",
  "spec": "p1-LADDER", "spec_version": ${SPEC_VERSION:-2},
  "git": {"harness": "$(cat /root/p1/harness-sha 2>/dev/null || echo uncommitted)", "analysis": "n/a"},
  "time": {"start": "$START_ISO", "end": "$END_ISO", "warmup_s": $WARM, "measure_s": $MEAS},
  "nodes": {"receiver": "clnode366", "senders": ["clnode311", "clnode312", "clnode313", "clnode331", "tx0"]},
  "kernel": {"release": "$(uname -r)", "softirq_policy": "post-revert", "napi_threaded": $([ -n "$NAPI_PID" ] && echo 1 || echo 0)},
  "nic": {"driver": "mlx5_core", "channels": 32, "target_queue": $TQ, "irq_home_cpu": 8},
  "cpu": {"governor": "none-no-cpufreq-driver", "idle_states": "dma_latency_0", "smt": "on", "nps": 4},
  "placement": {"app_cpu": $APP_CPU, "napi_cpu": "${NAPI_CPU:-none}", "napi_pid": "${NAPI_PID:-0}"},
  "cell": {"workload": "$WORK", "policy": "$POLICY", "rate": $RATE, "plen": $PLEN, "rep": $REP},
  "metrics": {"sent": $SENT, "consumed": $CONS, "measure_pkts": ${MPKTS:-0}, "sockdrops": ${DROPS:-0},
              "resp": ${RESP:-0}, "censored": ${CENS:-0}, "echoed": ${ECHOED:-0}, "enobufs": $ENOB,
              "lat_p50_us": ${P50:--1}},
  "gates": {"conservation": "$GATE_CONS", "landing": "$GATE_LAND", "floor": "$GATE_FLOOR", "generator": "$GATE_GEN"},
  "outputs": ["consumer.txt", "consumer.err", "cpu.log", "gates.txt", "nic-pre.txt", "nic-post.txt", "stat-pre.txt", "stat-post.txt"]
}
EOF
echo "gates: conservation=$GATE_CONS landing=$GATE_LAND floor=$GATE_FLOOR generator=$GATE_GEN"
echo "== p1cell done $CELL rep$REP $(date -u +%FT%TZ)"
