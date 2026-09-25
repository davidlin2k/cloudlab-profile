#!/bin/bash
# w3knee2.sh -- W3 knee-pass v2 extension: 160k-300k x {P0,P0X}, 1 rep,
# with sender-CPU sampling (the v2 overload-cell validity check).
set -u
IFACE=enp195s0np0
PERF=/usr/lib/linux-tools/6.8.0-142-generic/perf
O=/root/p1/w3knee2
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

cell() {
  AR=$1; CPU=$2; L=$3
  D=$O/$AR-$L
  mkdir -p $D
  echo "== $AR load $L =="
  Q=$(( (L / 5) * 8 ))
  snap > $D/rx-before.txt
  for o in $NODES; do ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "grep '^cpu ' /proc/stat" > $D/cpustat-before-$o.txt 2>/dev/null; done
  for o in $NODES; do
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "sudo bash -c 'nohup timeout 110 /root/k2/mutilate -s 10.10.1.1 --noload -T 2 -c 8 -d 32 -K 30 -V 32 -u 0.1 -r 100000 -i exponential:1 -q $Q -w 5 -t 65 -C 1 -Q 200 -D 4 --save /tmp/w3-samples.txt > /tmp/w3-load.txt 2>&1 </dev/null &'"
    sleep 0.3
  done
  sleep 6
  $PERF stat -A -a -C 8,9 -e ref-cycles -- sleep 64 > $D/perf.txt 2>&1
  sleep 6
  snap > $D/rx-after.txt
  for o in $NODES; do
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "grep '^cpu ' /proc/stat" > $D/cpustat-after-$o.txt 2>/dev/null
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "cat /tmp/w3-load.txt" > $D/load-$o.txt 2>/dev/null
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o "cat /tmp/w3-samples.txt" > $D/samples-$o.txt 2>/dev/null
    ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.$o 'sudo pkill -xc mutilate; true' 2>/dev/null || true
  done
}

for AR in P0 P0X; do
  if [ $AR = P0 ]; then CPU=8; else CPU=9; fi
  echo "== arm $AR memcached on CPU $CPU =="
  taskset -c $CPU memcached -t 1 -c 32768 -p 11211 -l 10.10.1.1 -u root -m 256 > $O/memcached-$AR.log 2>&1 &
  sleep 2
  MPID=$(pgrep -x memcached | head -1)
  taskset -pc $CPU $MPID > $O/arm-$AR.txt
  ssh -n -o StrictHostKeyChecking=no davidlin@10.10.1.10 "sudo timeout 120 /root/k2/mutilate -s 10.10.1.1 --loadonly -K 30 -V 32 -r 100000 -T 4" > $O/loadonly-$AR.txt 2>&1
  for L in 160000 190000 220000 260000 300000; do
    cell $AR $CPU $L
  done
  pkill -xc memcached 2>/dev/null
  sleep 1
done

for rid in $(ethtool -n $IFACE | sed -n 's/^Filter: \([0-9]*\).*/\1/p'); do ethtool -N $IFACE delete $rid; done
echo "W3KNEE2 DONE $(date -u +%FT%TZ)"
