#!/bin/bash
# w3main.sh -- W3 main matrix (spec v3): 5 loads x 3 reps x {P0,P0X,BP}
# (45 cells) + perf sched at 0.25x on the {P0,P0X} pair (2 captures).
set -u
IFACE=enp195s0np0
PERF=/usr/lib/linux-tools/6.8.0-142-generic/perf
O=/root/p1/w3main
NODES="10 11 12 13 14"
rm -rf $O; mkdir -p $O

ethtool -K $IFACE ntuple on
for rid in $(ethtool -n $IFACE | sed -n 's/^Filter: \([0-9]*\).*/\1/p'); do ethtool -N $IFACE delete $rid; done
ethtool -N $IFACE flow-type tcp4 dst-port 11211 action 7 > $O/ntuple.log 2>&1
taskset -pc 8 1594438 > $O/kthread-pin.txt 2>&1

pkill -xc memcached 2>/dev/null
for o in $NODES; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc mutilate; true' 2>/dev/null || true; done
sleep 1

snap() { ethtool -S $IFACE | grep -E 'rx0_packets:|rx1_packets:|rx7_packets:'; }

start_memcached() {
  AR=$1; CPU=$2
  taskset -c $CPU memcached -t 1 -c 32768 -p 11211 -l 10.10.1.1 -u root -m 256 > $O/memcached-$AR.log 2>&1 &
  sleep 2
  MPID=$(pgrep -x memcached | head -1)
  taskset -pc $CPU $MPID > $O/arm-$AR.txt
  ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.10 "sudo timeout 120 /root/k2/mutilate -s 10.10.1.1 --loadonly -K 30 -V 32 -r 100000 -T 4" > $O/loadonly-$AR.txt 2>&1
}

launch_masters() {
  Q=$1
  for o in $NODES; do
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "sudo bash -c 'nohup timeout 110 /root/k2/mutilate -s 10.10.1.1 --noload -T 2 -c 8 -d 32 -K 30 -V 32 -u 0.1 -r 100000 -i exponential:1 -q $Q -w 5 -t 65 -C 1 -Q 200 -D 4 --save /tmp/w3-samples.txt > /tmp/w3-load.txt 2>&1 </dev/null &'"
    sleep 0.3
  done
}

fetch_masters() {
  D=$1
  snap > $D/rx-after.txt
  for o in $NODES; do
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "grep '^cpu ' /proc/stat" > $D/cpustat-after-$o.txt 2>/dev/null
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "cat /tmp/w3-load.txt" > $D/load-$o.txt 2>/dev/null
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "cat /tmp/w3-samples.txt" > $D/samples-$o.txt 2>/dev/null
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o 'sudo pkill -xc mutilate; true' 2>/dev/null || true
  done
}

cell() {
  AR=$1; CPU=$2; L=$3; R=$4
  D=$O/$AR-$L-$R
  mkdir -p $D
  echo "== $AR load $L rep $R =="
  Q=$(( (L / 5) * 8 ))
  snap > $D/rx-before.txt
  for o in $NODES; do ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "grep '^cpu ' /proc/stat" > $D/cpustat-before-$o.txt 2>/dev/null; done
  launch_masters $Q
  sleep 6
  $PERF stat -A -a -C 8,9 -e ref-cycles -- sleep 64 > $D/perf.txt 2>&1
  sleep 6
  fetch_masters $D
}

sched_cell() {
  AR=$1; CPU=$2; L=$3
  D=$O/sched-$AR-$L
  mkdir -p $D
  echo "== perf sched $AR load $L =="
  Q=$(( (L / 5) * 8 ))
  launch_masters $Q
  sleep 6
  $PERF sched record -o $D/sched.data -- sleep 64 > $D/sched.log 2>&1
  sleep 6
  fetch_masters $D
}

for AR in P0 P0X BP; do
  if [ $AR = P0X ]; then CPU=9; else CPU=8; fi
  if [ $AR = BP ]; then
    sysctl -w net.core.busy_poll=50 > $O/bp-sysctl.txt 2>&1
    sysctl -w net.core.busy_read=50 >> $O/bp-sysctl.txt
  else
    sysctl -w net.core.busy_poll=0 > /dev/null 2>&1
    sysctl -w net.core.busy_read=0 > /dev/null 2>&1
  fi
  echo "== arm $AR memcached on CPU $CPU =="
  start_memcached $AR $CPU
  for L in 47500 95000 190000 285000 380000; do
    for R in 1 2 3; do
      cell $AR $CPU $L $R
    done
  done
  pkill -xc memcached 2>/dev/null
  sleep 1
done

sysctl -w net.core.busy_poll=0 > /dev/null 2>&1
sysctl -w net.core.busy_read=0 > /dev/null 2>&1

start_memcached P0 8
sched_cell P0 8 47500
pkill -xc memcached 2>/dev/null; sleep 1
start_memcached P0X 9
sched_cell P0X 9 47500
pkill -xc memcached 2>/dev/null

for rid in $(ethtool -n $IFACE | sed -n 's/^Filter: \([0-9]*\).*/\1/p'); do ethtool -N $IFACE delete $rid; done
echo "W3MAIN DONE $(date -u +%FT%TZ)"
