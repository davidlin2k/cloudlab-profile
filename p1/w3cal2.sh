#!/bin/bash
# w3cal2.sh -- calibration: memcached per-request costs at low load +
# idle p99 (feeds the W3 spec's pre-registered knee). NOT an experiment
# cell: no claims come from this file's outputs alone.
set -u
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
PERF=/usr/lib/linux-tools/6.8.0-142-generic/perf
O=/root/p1/w3cal2
rm -rf $O; mkdir -p $O
AG="10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13 10.10.1.14"
MA=10.10.1.10

echo "== setup: ntuple steer dport 11211 -> queue 7 =="
ethtool -K $IFACE ntuple on
for rid in $(ethtool -n $IFACE | sed -n 's/^Filter: \([0-9]*\).*/\1/p'); do ethtool -N $IFACE delete $rid; done
ethtool -N $IFACE flow-type tcp4 dst-port 11211 action 7 2>&1 | tee $O/ntuple.log
ethtool -n $IFACE > $O/ntuple-dump.txt 2>&1
echo "irq=$IRQ"

echo "== kill strays =="
pkill -xc memcached 2>/dev/null
for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc mutilate; true' 2>/dev/null || true; done
sleep 1

echo "== agents on n2-n6 =="
for a in $AG; do
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@$a "sudo bash -c 'nohup /root/k2/mutilate -A -T 4 -p 5556 > /tmp/w3-agent.log 2>&1 </dev/null &'"
  sleep 0.4
done
sleep 2

run_arm() {
  AR=$1; CPU=$2
  echo "== arm $AR: memcached -t 1 on CPU $CPU =="
  taskset -c $CPU memcached -t 1 -c 32768 -p 11211 -l 10.10.1.1 -u root -m 256 > $O/memcached-$AR.log 2>&1 &
  sleep 2
  MPID=$(pgrep -x memcached | head -1)
  echo "memcached pid=$MPID taskset -pc $CPU $MPID" > $O/arm-$AR.txt
  taskset -pc $CPU $MPID >> $O/arm-$AR.txt
  echo "== loadonly =="
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@$MA "sudo timeout 120 /root/k2/mutilate -s 10.10.1.1 --loadonly -K 30 -V 32 -r 100000 -T 4" > $O/loadonly-$AR.txt 2>&1
  echo "== 20k QPS cost window (60 s measure) =="
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@$MA "sudo bash -c 'nohup timeout 110 /root/k2/mutilate -s 10.10.1.1 --noload -T 4 -c 16 -d 64 -K 30 -V 32 -u 0.1 -r 100000 -i exponential -q 20000 -w 5 -t 65 -C 2 -Q 500 -D 4 -a 10.10.1.10 -a 10.10.1.11 -a 10.10.1.12 -a 10.10.1.13 -a 10.10.1.14 --save /tmp/w3-samples-$AR.txt > /tmp/w3-load-$AR.txt 2>&1 </dev/null &'"
  sleep 6
  echo "== perf bracket [6.5, 64.5] =="
  $PERF stat -A -a -C 8,9 -e ref-cycles -- sleep 58 > $O/perf-$AR.txt 2>&1
  sleep 2
  scp -o StrictHostKeyChecking=no davidlin@$MA:/tmp/w3-load-$AR.txt $O/load-$AR.txt > /dev/null 2>&1 || ssh -n davidlin@$MA "cat /tmp/w3-load-$AR.txt" > $O/load-$AR.txt
  ssh -n -o StrictHostKeyChecking=no davidlin@$MA "cat /tmp/w3-samples-$AR.txt" > $O/samples-$AR.txt 2>/dev/null
  echo "== idle p99 (200 QPS trickle, 30 s) =="
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@$MA "sudo timeout 120 /root/k2/mutilate -s 10.10.1.1 --noload -T 2 -c 4 -d 4 -K 30 -V 32 -u 0.1 -r 100000 -i exponential -q 200 -w 5 -t 35 -C 2 -Q 200 -D 4 -a 10.10.1.10" > $O/idle-$AR.txt 2>&1
  echo "== landing gate: queue deltas under a 5 s trickle =="
  C0=$(ethtool -S $IFACE | grep -E 'rx7_packets:|rx0_packets:|rx1_packets:')
  ssh -n -o StrictHostKeyChecking=no davidlin@$MA "sudo timeout 60 /root/k2/mutilate -s 10.10.1.1 --noload -T 1 -c 2 -d 2 -K 30 -V 32 -u 0.1 -r 100000 -q 5000 -w 1 -t 6 -C 2 -Q 500 -a 10.10.1.10" > /dev/null 2>&1
  C1=$(ethtool -S $IFACE | grep -E 'rx7_packets:|rx0_packets:|rx1_packets:')
  echo "before: $C0" >> $O/arm-$AR.txt
  echo "after:  $C1" >> $O/arm-$AR.txt
  pkill -xc memcached
  sleep 1
}

run_arm P0 8
run_arm P0X 9

for a in $AG; do ssh -n -o StrictHostKeyChecking=no davidlin@$a 'sudo pkill -xc mutilate; true' 2>/dev/null || true; done
ethtool -N $IFACE delete 1 2>/dev/null || true
echo "CAL2 DONE $(date -u +%FT%TZ)"
