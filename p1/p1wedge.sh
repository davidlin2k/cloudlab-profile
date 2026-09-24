#!/bin/bash
# p1wedge.sh POLICY RATE - live-state probe of the NAPI stall.
set -u
POL=${1:?policy} RATE=${2:?rate}
IFACE=enp195s0np0
TXOCTS="10 11 12 13 14"
SPORTS=(32704 32726 32706 32724 32725)
RPS=$((RATE/5)); N=$((RPS*41)); TOT=41; WARM=4; MEAS=35
OUT=/root/p1/results/wedge-$POL-r$RATE
mkdir -p $OUT
cd /root/k2

for try in 1 2 3; do pgrep -xc k2_rx >/dev/null 2>&1 || break; pkill -xc k2_rx >/dev/null 2>&1; sleep 0.5; done
for o in $TXOCTS; do ssh -n davidlin@10.10.1.$o "sudo pkill -xc k5blast >/dev/null 2>&1" 2>/dev/null; done

source ./p1pol.sh $POL >/dev/null 2>&1 || echo "P1POL-SOURCE-FAIL" | tee $OUT/wedge.log
NPID=$(pgrep -f "napi/$IFACE" | head -1)
echo "NPID=$NPID APP_CPU=$APP_CPU NAPI_CPU=$NAPI_CPU" >> $OUT/wedge.log
taskset -cp $NPID >> $OUT/wedge.log 2>&1
grep 312: /proc/interrupts >> $OUT/wedge.log

./k2_rx --port 7777 --core $APP_CPU --secs $((TOT+2)) --skip $WARM --all >/root/p1/consumer.txt 2>/root/p1/consumer.err &
CPID=$!
sleep 1
idx=0
for o in $TXOCTS; do
  ssh -n davidlin@10.10.1.$o "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport ${SPORTS[$idx]} --dport 7777 --n $N --rate $RPS --plen 64 --core 4 >/tmp/p1w-$o.txt 2>&1 </dev/null &'"
  idx=$((idx+1))
done

# 2s live sampling: thread state, IRQ, softirqs, queue, pause, ring
for i in $(seq 1 22); do
  ts=$(date +%s.%N)
  st=$(awk '{print $1,$2,$3,$14,$15,$39}' /proc/$NPID/stat 2>/dev/null)
  al=$(grep Cpus_allowed_list /proc/$NPID/status 2>/dev/null | awk '{print $2}')
  irq=$(grep -E "^ *312:" /proc/interrupts | awk '{s=0; for(i=2;i<=NF-3;i++) s+=$i; print s}')
  nrx=$(grep NET_RX /proc/softirqs | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')
  q7=$(ethtool -S $IFACE | awk '/rx_7_packets/{print $2}')
  oob=$(ethtool -S $IFACE | awk '/out_of_buffer/{print $2}')
  pa=$(ethtool -S $IFACE | awk '/tx_pause_ctrl_phy|tx_global_pause:/{print $2}' | paste -sd+ | bc)
  echo "T=$ts state=$st al=$al irq=$irq nrx=$nrx q7=$q7 oob=$oob pa=$pa" >> $OUT/wedge.log
  sleep 2
done
wait $CPID 2>/dev/null
cp /root/p1/consumer.txt $OUT/consumer.txt 2>/dev/null
cp /root/p1/consumer.err $OUT/consumer.err 2>/dev/null
for o in $TXOCTS; do ssh -n davidlin@10.10.1.$o "cat /tmp/p1w-$o.txt" > $OUT/sender-$o.txt 2>/dev/null; done
grep -h -a "k2rx port" $OUT/consumer.txt >> $OUT/wedge.log 2>/dev/null
grep -h -a "sent=" $OUT/sender-*.txt | grep -a dip= >> $OUT/wedge.log 2>/dev/null
echo "WEDGE DONE $OUT" >> $OUT/wedge.log
