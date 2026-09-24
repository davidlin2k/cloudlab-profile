#!/bin/bash
# p1w5.sh -- one W5 time-series cell for Fig 5 (root on rx).
# usage: p1w5.sh POLICY PATTERN REP TAG   (POLICY: P0 P2 P4 P7)
# PATTERN: ramp burst step (p1/lists/w5-*.txt profiles, aggregate pps,
# each of 5 senders scales 0.2). 190 s pattern + 5 s consumer tail.
set -u
POLICY=$1; PATTERN=$2; REP=$3; TAG=$4
IFACE=enp195s0np0
DUR=${DUR:-190}
CELL="W5-${POLICY}-${PATTERN}"
OUT=/root/p1/results/$TAG/$CELL/rep$REP
mkdir -p "$OUT"
exec > >(tee "$OUT/run.log") 2>&1
echo "== p1w5 $CELL rep$REP $(date -u +%FT%TZ)"

pkill -xc k2_rx >/dev/null 2>&1; pkill -xc k5blast >/dev/null 2>&1
for o in 10 11 12 13 14; do
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
    "sudo pkill -xc k5blast >/dev/null 2>&1; true" 2>/dev/null
done
exec 9>/dev/cpu_dma_latency; echo 0 >&9

# Static policies wear their own wiring via p1pol; P7's base state is P0
# wiring and the controller owns the rung from here.
APP_CPU=8
WIRE=$POLICY
[ "$POLICY" = P7 ] && WIRE=P0
bash /root/k2/p1pol.sh "$WIRE" > "$OUT/policy.txt" 2>&1

ethtool -S $IFACE | grep -E "rx[0-9]+_packets" > "$OUT/nic-pre.txt"
nohup /root/k2/k2_rx --port 7777 --core "$APP_CPU" --secs $((DUR + 5)) --skip 5 \
  > "$OUT/consumer.txt" 2> "$OUT/consumer.err" &
APP_PID=$!
CTLPID=""
if [ "$POLICY" = P7 ]; then
  . /root/p1/costs.env
  nohup python3 /root/k2/p1ctl.py --c-app "$C_APP" --c-net "$C_NET" --smt "$SMT" \
    --duration "$DUR" --log "$OUT/ctl.log" > "$OUT/ctl.err" 2>&1 &
  CTLPID=$!
  echo "$CTLPID" > "$OUT/ctl.pid"
fi
sleep 1
for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
  o=${pair%%:*}; s=${pair##*:}
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
    "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport $s --dport 7777 --profile /root/k2/lists/w5-$PATTERN.txt --scale 0.2 --secs $DUR --plen 64 --core 4 > /tmp/p1snd-$o.txt 2>&1 </dev/null &'" \
    || echo "FAIL launch $o"
done
wait $APP_PID
[ -n "$CTLPID" ] && { sleep 3; kill "$CTLPID" 2>/dev/null; }
sleep 1

for o in 10 11 12 13 14; do
  for try in 1 2 3 4; do
    [ -s "$OUT/sender-$o.txt" ] && grep -q "sent=" "$OUT/sender-$o.txt" && break
    sleep 1
    ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
      "cat /tmp/p1snd-$o.txt" > "$OUT/sender-$o.txt" 2>/dev/null
  done
done
ethtool -S $IFACE | grep -E "rx[0-9]+_packets" > "$OUT/nic-post.txt"

CONS=$(grep "sum=" "$OUT/consumer.err" | sed -n 's/.* pkts=\([0-9]*\).*/\1/p' | tail -1)
DROPS=$(grep "sum=" "$OUT/consumer.err" | sed -n 's/.*sockdrops=\([0-9]*\).*/\1/p' | tail -1)
SENT=$(grep -hE "^\[k5blast\] dip=" "$OUT"/sender-*.txt | sed -n 's/.* sent=\([0-9]*\).*/\1/p' | awk '{s+=$1} END {print s+0}')
UNACC=$((SENT - CONS - ${DROPS:-0}))
GATE_CONS=pass
ALLOW=$((SENT / 20))    # 180 s run: last ~1 s in flight at consumer exit
[ "$UNACC" -lt 0 ] || [ "$UNACC" -gt "$ALLOW" ] && GATE_CONS=fail
echo "conservation: sent=$SENT consumed=$CONS sockdrops=${DROPS:-0} unaccounted=$UNACC allow=$ALLOW" > "$OUT/gates.txt"

cat > "$OUT/manifest.json" <<EOF
{
  "run_id": "p1-LADDER/$(date -u +%F)/$CELL/rep$REP",
  "spec": "specs/p1-LADDER.md", "spec_version": 2,
  "kernel": "$(uname -r)",
  "cell": {"workload": "W5", "policy": "$POLICY", "pattern": "$PATTERN", "rep": $REP, "plen": 64},
  "tool_versions": {"k2_rx": "wp99-window", "k5blast": "profile", "p1ctl": "v1"},
  "placement": {"app_cpu": $APP_CPU, "controller": "$([ -n "$CTLPID" ] && echo p1ctl || echo static)"},
  "gates": {"conservation": "$GATE_CONS"},
  "metrics": {"sent": $SENT, "consumed": $CONS, "sockdrops": ${DROPS:-0}},
  "time": {"pattern_s": $DUR, "warmup_s": 5, "measure_s": $DUR},
  "outputs": ["consumer.txt", "consumer.err", "ctl.log", "sender-*.txt", "nic-pre.txt", "nic-post.txt"]
}
EOF
echo "== p1w5 done $CELL rep$REP $(date -u +%FT%TZ) gates: conservation=$GATE_CONS"
