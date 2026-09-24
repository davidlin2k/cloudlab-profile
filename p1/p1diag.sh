#!/bin/bash
# p1diag.sh POLICY RATE [GRO on|off] [PAUSE keep|off] - one diagnostic
# cell with pause/GRO/tx-drop instrumentation at BOTH ends.
set -u
export ControlPath=/tmp/p1mux-%r@%h ControlPersist=600
POL=${1:?policy} RATE=${2:?rate} GRO=${3:-on} PAUSE=${4:-keep}
IFACE=enp195s0np0
TXOCTS="10 11 12 13 14"
SPORTS=(32704 32726 32706 32724 32725)
RPS=$((RATE/5)); N=$((RPS*71)); TOT=71; WARM=10; MEAS=60
OUT=/root/p1/results/diag-$POL-r$RATE-g$GRO-p$PAUSE
mkdir -p $OUT

snap() {
  ssh -n davidlin@10.10.1.$1 "ethtool -S enp195s0np0 2>/dev/null | grep -iE 'pause|xoff|xon|out_of_buffer|rx_7_packets|discard|tx_queue_.*dropped'" > $OUT/$2.txt 2>&1
}
snapr() {
  ssh davidlin@clnode366.clemson.cloudlab.us "ethtool -S $IFACE 2>/dev/null | grep -iE 'pause|xoff|xon|out_of_buffer|rx_7_packets|discard'" > $OUT/$1-rx.txt 2>&1
}

ssh davidlin@clnode366.clemson.cloudlab.us "ethtool -k $IFACE | grep -E 'generic-receive-offload|rx-gro-hw|lro'; ethtool -a $IFACE" > $OUT/feat-before.txt 2>&1
if [ "$GRO" = off ]; then
  ssh davidlin@clnode366.clemson.cloudlab.us "sudo ethtool -K $IFACE gro off lro off rx-gro-hw off 2>&1; ethtool -k $IFACE | grep -E 'generic-receive-offload|rx-gro-hw'" > $OUT/feat-gro.txt 2>&1
fi
if [ "$PAUSE" = off ]; then
  ssh davidlin@clnode366.clemson.cloudlab.us "sudo ethtool -A $IFACE rx off tx off 2>&1" >> $OUT/feat-before.txt 2>&1
  for o in $TXOCTS; do ssh -n davidlin@10.10.1.$o "sudo ethtool -A enp195s0np0 rx off tx off 2>&1" >> $OUT/feat-before.txt 2>&1; done
fi

for try in 1 2 3; do pgrep -xc k2_rx >/dev/null 2>&1 || break; pkill -xc k2_rx >/dev/null 2>&1; sleep 0.5; done
for o in $TXOCTS; do ssh -n davidlin@10.10.1.$o "sudo pkill -xc k5blast >/dev/null 2>&1" 2>/dev/null; done
for o in $TXOCTS; do ssh -n davidlin@10.10.1.$o "pgrep -xc k5blast || true" 2>/dev/null; done

snapr pre
for o in $TXOCTS; do snap $o pre-$o & done; wait

cd /root/k2
( source ./p1pol.sh $POL >/dev/null 2>&1
  exec ./k2_rx --port 7777 --core $APP_CPU --secs $((TOT+2)) --skip $WARM --all --dump $OUT/hist.txt >/root/p1/consumer.txt 2>/root/p1/consumer.err ) &
sleep 1.5
idx=0
for o in $TXOCTS; do
  ssh -n davidlin@10.10.1.$o "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport ${SPORTS[$idx]} --dport 7777 --n $N --rate $RPS --plen 64 --core 4 >/tmp/p1diag-$o.txt 2>&1 </dev/null &'"
  idx=$((idx+1))
done
sleep 74
snapr post
for o in $TXOCTS; do snap $o post-$o & done; wait
for o in $TXOCTS; do
  for try in 1 2 3 4; do
    [ -s $OUT/sender-$o.txt ] && grep -q "sent=" $OUT/sender-$o.txt && break
    ssh -n davidlin@10.10.1.$o "cat /tmp/p1diag-$o.txt" > $OUT/sender-$o.txt 2>/dev/null
    sleep 1
  done
done
cp /root/p1/consumer.txt $OUT/consumer.txt 2>/dev/null
cp /root/p1/consumer.err $OUT/consumer.err 2>/dev/null
pkill -xc k2_rx >/dev/null 2>&1
ssh davidlin@clnode366.clemson.cloudlab.us "sudo ethtool -K $IFACE gro on lro off rx-gro-hw on >/dev/null 2>&1; sudo ethtool -A $IFACE rx on tx on >/dev/null 2>&1"
for o in $TXOCTS; do ssh -n davidlin@10.10.1.$o "sudo ethtool -A enp195s0np0 rx on tx on >/dev/null 2>&1" 2>/dev/null; done
echo "DIAG DONE $OUT"
