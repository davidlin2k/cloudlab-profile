#!/bin/bash
# w3cal3.sh -- calibration v3: five independent mutilate masters
# (no zmq agent mode: agents go stale after a killed master), bracket
# aligned to the measure window, fetch after full exit, conclusive
# landing gate. Feeds the W3 spec's pre-registered knee.
set -u
IFACE=enp195s0np0
PERF=/usr/lib/linux-tools/6.8.0-142-generic/perf
O=/root/p1/w3cal3b
rm -rf $O; mkdir -p $O
NODES="10 11 12 13 14"

ethtool -K $IFACE ntuple on
for rid in $(ethtool -n $IFACE | sed -n 's/^Filter: \([0-9]*\).*/\1/p'); do ethtool -N $IFACE delete $rid; done
ethtool -N $IFACE flow-type tcp4 dst-port 11211 action 7 2>&1 | tee $O/ntuple.log

# queue-7 threaded-NAPI kthread (PID pinned by the wedgetrace work,
# AN-006A provenance) -> CPU 8 in both arms: the receive side is CPU 8
# per W1/W2 placement semantics; the ARM difference is the worker CPU.
KTHREAD=1594438
grep 'napi' /proc/$KTHREAD/comm > $O/kthread-pin.txt 2>&1
taskset -pc 8 $KTHREAD >> $O/kthread-pin.txt
grep Cpus_allowed_list /proc/$KTHREAD/status >> $O/kthread-pin.txt

pkill -xc memcached 2>/dev/null
for o in $NODES; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc mutilate; true' 2>/dev/null || true; done
sleep 1

gate_landing() {
  AR=$1
  C0=$(ethtool -S $IFACE | grep -E 'rx0_packets:|rx1_packets:|rx7_packets:')
  ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.10 "sudo timeout 30 /root/k2/mutilate -s 10.10.1.1 --noload -T 1 -c 2 -d 2 -K 30 -V 32 -u 0.1 -r 100000 -q 20000 -w 1 -t 4 -C 1 -Q 200 --save /tmp/w3-gate.txt" > /dev/null 2>&1
  C1=$(ethtool -S $IFACE | grep -E 'rx0_packets:|rx1_packets:|rx7_packets:')
  {
    echo "gate before:"
    echo "$C0"
    echo "gate after:"
    echo "$C1"
  } >> $O/arm-$AR.txt
}

run_arm() {
  AR=$1; CPU=$2
  echo "== arm $AR: memcached -t 1 pinned to CPU $CPU =="
  taskset -c $CPU memcached -t 1 -c 32768 -p 11211 -l 10.10.1.1 -u root -m 256 > $O/memcached-$AR.log 2>&1 &
  sleep 2
  MPID=$(pgrep -x memcached | head -1)
  echo "memcached pid=$MPID" > $O/arm-$AR.txt
  taskset -pc $CPU $MPID >> $O/arm-$AR.txt
  ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.10 "sudo timeout 120 /root/k2/mutilate -s 10.10.1.1 --loadonly -K 30 -V 32 -r 100000 -T 4" > $O/loadonly-$AR.txt 2>&1
  gate_landing $AR
  echo "== cost window: 5 masters x 4000 QPS, measure [6,70] =="
  for o in $NODES; do
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "sudo bash -c 'nohup timeout 110 /root/k2/mutilate -s 10.10.1.1 --noload -T 2 -c 4 -d 8 -K 30 -V 32 -u 0.1 -r 100000 -i exponential:1 -q 16000 -w 5 -t 65 -C 1 -Q 100 -D 4 --save /tmp/w3-samples.txt > /tmp/w3-load.txt 2>&1 </dev/null &'"
    sleep 0.3
  done
  sleep 6
  $PERF stat -A -a -C 8,9 -e ref-cycles -- sleep 64 > $O/perf-$AR.txt 2>&1
  sleep 6
  for o in $NODES; do
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "cat /tmp/w3-load.txt" > $O/load-$AR-$o.txt 2>/dev/null
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "cat /tmp/w3-samples.txt" > $O/samples-$AR-$o.txt 2>/dev/null
  done
  echo "== idle p99 (200 QPS trickle from tx10, 30 s measure) =="
  ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.10 "sudo timeout 90 /root/k2/mutilate -s 10.10.1.1 --noload -T 1 -c 2 -d 2 -K 30 -V 32 -u 0.1 -r 100000 -i exponential:1 -q 200 -w 5 -t 30 -C 1 -Q 200 --save /tmp/w3-idle.txt" > $O/idle-$AR.txt 2>&1
  ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.10 "cat /tmp/w3-idle.txt" > $O/idle-samples-$AR.txt 2>/dev/null
  pkill -xc memcached
  for o in $NODES; do ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o 'sudo pkill -xc mutilate; true' 2>/dev/null || true; done
  sleep 1
}

run_arm P0 8
run_arm P0X 9

for rid in $(ethtool -n $IFACE | sed -n 's/^Filter: \([0-9]*\).*/\1/p'); do ethtool -N $IFACE delete $rid; done
echo "CAL3B DONE $(date -u +%FT%TZ)"
