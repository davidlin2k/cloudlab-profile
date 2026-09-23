#!/bin/bash
# ab_runs.sh: PI spec A (per-hop accounting at 50k/150k aligned) and
# spec B (bypass: sink straight to emitters). Finds where the rate
# drops: emitter -> HAProxy -> sink, with conservation at each hop.
# Also captures the proxy NIC for achieved-burst-width analysis.
set -u
ENGINES="clnode323 clnode386 clnode322"
N1="clnode366"
N6="clnode331"
R=results
mkdir -p $R

sample_hop() {  # $1 = label, $2 = N, $3 = seconds
  local out="$R/hop-$1-$2.txt"
  : > "$out"
  for i in $(seq 1 "$3"); do
    {
      echo "== sample $i t=$(date -u +%H:%M:%S.%N)"
      # emitter stats (12 endpoints, 3 nodes)
      ssh -o ConnectTimeout=5 davidlin@clnode323.clemson.cloudlab.us \
        'for h in 10.10.1.11 10.10.1.12 10.10.1.13; do for q in 8000 8001 8002 8003; do curl -s -m 2 http://$h:$q/stats; done; done' 2>/dev/null
      # HAProxy stats socket: bin/bout/scur per section + run queue
      ssh -o ConnectTimeout=5 davidlin@$N1.clemson.cloudlab.us \
        'python3 - << "PYEOF"
import socket
s = socket.socket(socket.AF_UNIX); s.connect("/run/haproxy/admin.sock")
s.sendall(b"show stat\n"); d = b""
while True:
    c = s.recv(65536)
    if not c: break
    d += c
for line in d.decode().strip().splitlines():
    f = line.split(",")
    if len(f) > 9 and f[1] in ("FRONTEND", "BACKEND"):
        print("hap", f[0], f[1], "scur="+f[4], "bin="+f[8], "bout="+f[9])
s.close()
s = socket.socket(socket.AF_UNIX); s.connect("/run/haproxy/admin.sock")
s.sendall(b"show info\n"); d = b""
while True:
    c = s.recv(65536)
    if not c: break
    d += c
for line in d.decode().splitlines():
    if line.startswith(("Run_queue", "Threads", "CurrConns", "CumConns")):
        print("hap", line.replace("\t", " "))
s.close()
PYEOF' 2>/dev/null
      # HAProxy per-thread CPU
      ssh -o ConnectTimeout=5 davidlin@$N1.clemson.cloudlab.us \
        'pidstat -t -p $(pidof haproxy | cut -d" " -f1) 1 1 2>/dev/null | grep -E "^Average|Thread"' 2>/dev/null
      # sink rate + CPU
      ssh -o ConnectTimeout=5 davidlin@$N6.clemson.cloudlab.us \
        'curl -s -m 2 http://127.0.0.1:9200/stats; pidstat -p $(pidof clocksink) 1 1 2>/dev/null | grep Average' 2>/dev/null
    } >> "$out" 2>&1
    sleep 1
  done
}

run_cell() {  # $1 = N, $2 = "proxy"|"bypass", $3 = mode
  local N=$1 KIND=$2 MODE=$3
  echo "== $KIND N=$N mode=$MODE $(date -u +%H:%M:%S)"
  for n in $ENGINES; do
    ssh -o ConnectTimeout=10 davidlin@$n.clemson.cloudlab.us "bash /tmp/clock/relaunch_emitters.sh $MODE" &
  done
  wait
  sleep 2
  ssh -o ConnectTimeout=10 davidlin@$N6.clemson.cloudlab.us "sudo pkill -xc clocksink; sleep 2; sudo rm -f /tmp/clock/ab-$KIND-$N.log"
  local EP
  if [ "$KIND" = "proxy" ]; then
    EP="http://10.10.1.1"
  else
    EP="10.10.1.11:8000,10.10.1.11:8001,10.10.1.11:8002,10.10.1.11:8003,10.10.1.12:8000,10.10.1.12:8001,10.10.1.12:8002,10.10.1.12:8003,10.10.1.13:8000,10.10.1.13:8001,10.10.1.13:8002,10.10.1.13:8003"
  fi
  ssh -o ConnectTimeout=10 davidlin@$N6.clemson.cloudlab.us \
    "sudo bash -c 'nohup /tmp/clock/clocksink -listen :9200 -proxy $EP -streams $N -dial-rate 10000 -window 1 > /tmp/clock/ab-$KIND-$N.log 2>&1 < /dev/null &'"
  # wait for live >= 98%
  local ok=0
  for i in $(seq 1 90); do
    live=$(ssh -o ConnectTimeout=5 davidlin@$N6.clemson.cloudlab.us 'curl -s -m 2 http://127.0.0.1:9200/stats' | grep -oE 'live=[0-9]+' | cut -d= -f2)
    live=${live:-0}
    if [ "$live" -ge $((N * 98 / 100)) ]; then ok=1; break; fi
    sleep 5
  done
  [ "$ok" = "1" ] || { echo "  connect_timeout (live=$live)"; return; }
  sleep 15  # discard
  # 10s burst capture at the proxy NIC (proxy runs only)
  if [ "$KIND" = "proxy" ]; then
    ssh -o ConnectTimeout=5 davidlin@$N1.clemson.cloudlab.us \
      "sudo rm -f /tmp/clock/burst-$N.pcap; sudo timeout 12 tcpdump -i enp195s0np0 -w /tmp/clock/burst-$N.pcap --time-stamp-precision=nano 'tcp src portrange 8000-8003' 2>/dev/null; sudo chmod 644 /tmp/clock/burst-$N.pcap" &
  fi
  sample_hop "$KIND-$N" "$N" 60
  wait
  ssh -o ConnectTimeout=5 davidlin@$N6.clemson.cloudlab.us 'tail -1 /tmp/clock/ab-'$KIND'-'$N'.log' | tee "$R/ab-$KIND-$N-final.txt"
}

for N in 50000 150000; do
  run_cell "$N" proxy aligned
  run_cell "$N" bypass aligned
done
echo ab_runs_complete
