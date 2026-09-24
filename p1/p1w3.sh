#!/bin/bash
# p1w3.sh POLICY QPS SECS rep TAG -- one W3 cell (memcached+mutilate).
# Receive steering: ALL tcp/11211 to queue 7 via an ntuple rule, so the
# instrumented queue carries W3 exactly as it carries W1/W2 under every
# policy. memcached: -t 1 pinned to the policy's app_cpu (the c_app
# source). mutilate: agents on tx0-3 (-T 16 -A), master on tx4, OPEN
# LOOP on the master (--measure_depth 16 --measure_qps sampling), 90%
# GETs (-u 0.1111 = 1:9 set:get), 32-byte values (-V 32), keyspace
# -r 100000. Open-loop intent: the master samples latency at a constant
# slow rate while agents carry the load (mutilate README).
set -eu
POLICY=${1:?policy}; QPS=${2:?qps}; SECS=${3:?secs}; REP=${4:?rep}; TAG=${5:?tag}
RXIP=10.10.1.1; TXIP="10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13"; MASTER=10.10.1.14
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OUT=/root/p1/results/$TAG/w3-$POLICY-q$QPS-rep$REP
mkdir -p "$OUT"

# 0) kill-verify strays (self-match-safe: names never superstring ours)
for ip in $RXIP $TXIP $MASTER; do
  sudo ssh root@$ip 'pkill -xc memcached; pkill -xc mutilate; true' >/dev/null 2>&1 || true
done
sleep 1

# 1) policy wiring (P0/P0X/P2/P3/P4 + P5/P6 knobs live in p1pol.sh)
bash /root/k2/p1pol.sh "$POLICY" > "$OUT/policy.txt" 2>&1

# 2) steering: tcp dport 11211 -> queue 7 (W3's instrument invariant)
IFACE=enp195s0np0
ethtool -N $IFACE delete all >/dev/null 2>&1 || true
ethtool -N $IFACE flow-type tcp4 dst-port 11211 action 7 >/dev/null
ethtool -n $IFACE > "$OUT/ntuple.txt"

# 3) memcached on the app core (1 thread = c_app source for W3)
APP_CPU=$(grep -oP 'app_cpu=\K[0-9]+' "$OUT/policy.txt" | head -1)
taskset -c "$APP_CPU" memcached -t 1 -c 32768 -m 64 -u root -l 10.10.1.1 -p 11211 \
  > "$OUT/memcached.log" 2>&1 &
MCPID=$!
sleep 2

# 4) mutilate: agents on tx0-3, master on tx4 (open-loop latency)
AGENTS=""; for ip in $TXIP; do AGENTS="$AGENTS -a $ip"; done
for ip in $TXIP; do
  sudo ssh root@$ip "nohup /root/k2/mutilate/mutilate -A -T 16 \
    > /root/k2/w3-agent.log 2>&1 < /dev/null &"
done
sleep 2
sudo ssh root@$master "nohup /root/k2/mutilate/mutilate -s 10.10.1.1 -p 11211 \
  $(for ip in $TXIP; do echo -n "\\-a $ip "; done) \
  -T 8 -C 16 -q $QPS -t $SECS -u 0.1111 -V 32 -K 32 -r 100000 \
  --measure_depth 16 --measure_qps 2000 \
  > /root/k2/w3-master.log 2>&1 < /dev/null &"
MASTERCMD_OK=1

# 5) sample rx state during the window (1 Hz, zero cross-node bytes)
bash /root/k2/p1samp.sh "$SECS" "$OUT/samples.txt" >/dev/null 2>&1 || true

# 6) fetch + gate + manifest (kill-verify at the end of every cell)
sleep 2
for i in 1 2 3 4; do
  sudo ssh root@$MASTER 'cat /root/k2/w3-master.log' > "$OUT/master.txt" 2>/dev/null && [ -s "$OUT/master.txt" ] && break
  sleep 3
done
for ip in $TXIP; do
  sudo ssh root@$ip 'cat /root/k2/w3-agent.log' >> "$OUT/agents.txt" 2>/dev/null || true
done
kill $MCPID >/dev/null 2>&1 || true
for ip in $RXIP $TXIP $MASTER; do
  sudo ssh root@$ip 'pkill -xc memcached; pkill -xc mutilate; true' >/dev/null 2>&1 || true
done
ethtool -N $IFACE delete all >/dev/null 2>&1 || true

QPS_MEAS=$(awk '/Total QPS/{print $4; exit}' "$OUT/master.txt" || echo 0)
P99=$(awk '/^read/{print $9; exit}' "$OUT/master.txt" || echo 0)
GATE_GEN=pass; awk -v m="$QPS" -v a="${QPS_MEAS:-0}" 'BEGIN{exit !(a >= 0.9*m && a <= 1.05*m)}' || GATE_GEN=generator-fail
cat > "$OUT/manifest.json" <<EOF
{"exp":"p1-LADDER","tag":"$TAG","policy":"$POLICY","workload":"w3",
 "qps_target":$QPS,"qps_meas":${QPS_MEAS:-0},"p99_us":${P99:-0},
 "secs":$SECS,"rep":$REP,"started":"$NOW","ended":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "gates":{"generator":"$GATE_GEN","steering":"pass"},"spec_version":"v3"}
EOF
echo "== p1w3 done $POLICY q$QPS rep$REP $TAG qps=$QPS_MEAS p99=$P99"
