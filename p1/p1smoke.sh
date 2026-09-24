#!/bin/bash
# p1smoke.sh -- p1-LADDER instrument smoke (root on rx): rebuild k2_rx,
# clean NAPI-thread map for queue 7, then W1 (flood) and W2 (echo) smoke
# cells through the ENTIRE collection path.
set -u
IFACE=enp195s0np0
mkdir -p /root/p1
exec > >(tee /root/p1/smoke.log) 2>&1
echo "== p1smoke $(date -u +%FT%TZ)"

echo "== build k2_rx"
cd /root/k2 && gcc -Wall -O2 -o k2_rx k2_rx.c && echo "built ok" || { echo "BUILD FAIL"; exit 1; }

echo "== NAPI thread map for queue 7 (clean background)"
echo 1 > /sys/class/net/$IFACE/threaded
sleep 0.5
snap() {
  for p in $(ls /proc | grep -E '^[0-9]+$'); do
    c=$(cat /proc/$p/comm 2>/dev/null)
    case "$c" in
      napi/*) echo "$p $(awk '{print $1}' /proc/$p/schedstat 2>/dev/null)" ;;
    esac
  done | sort -n
}
snap > /tmp/np-pre
ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
  "sudo /root/e0/sportgen --dip 10.10.1.1 --dport 7777 --sport 32704 --n 300000 --proto udp --plen 64 --batch 64 --pause 500" >/dev/null
snap > /tmp/np-post
join /tmp/np-pre /tmp/np-post | awk '{d=$3-$2; if (d>5000000) print "queue7 -> napi pid", $1, "+", d, "ns"}'
echo 0 > /sys/class/net/$IFACE/threaded

echo "== smoke W1: k2_rx + 2x k5blast (50k pps each, plen 64)"
q7b=$(ethtool -S $IFACE | awk '/^ *rx7_packets:/ {print $2}')
/root/k2/k2_rx --port 7777 --core 8 --secs 13 > /root/p1/smoke-w1-rx.txt 2>/root/p1/smoke-w1-rx.err &
RXPID=$!
sleep 1
for pair in 10:32704 11:32726; do
  o=${pair%%:*}; s=${pair##*:}
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
    "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport $s --dport 7777 --n 550000 --rate 50000 --plen 64 --core 4 >/tmp/k5-$o.txt 2>&1 </dev/null &'" \
    || echo "FAIL launch $o"
done
wait $RXPID
sleep 2
q7a=$(ethtool -S $IFACE | awk '/^ *rx7_packets:/ {print $2}')
echo "-- consumer:"; cat /root/p1/smoke-w1-rx.txt
echo "-- consumer wins (head):"; head -3 /root/p1/smoke-w1-rx.err
for o in 10 11; do
  echo "-- sender $o:"; ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o "cat /tmp/k5-$o.txt" 2>/dev/null
done
echo "-- q7 counter delta: $((q7a - q7b))"

echo "== smoke W2: k2_rx --echo + k4send (5k rps, plen 64)"
/root/k2/k2_rx --echo --port 7778 --core 8 --secs 9 > /root/p1/smoke-w2-srv.txt 2>/root/p1/smoke-w2-srv.err &
SRVPID=$!
sleep 1
ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
  "sudo bash -c 'nohup /root/k2/k4send --dip 10.10.1.1 --sip 10 --qmap 0:7778 --lport 33751 --n 30000 --plen 64 --depth 4 --rate 5000 --follow 0 --core 4 >/tmp/k4.txt 2>&1 </dev/null &'"
wait $SRVPID
sleep 1
echo "-- server:"; cat /root/p1/smoke-w2-srv.txt
echo "-- client:"; ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "cat /tmp/k4.txt" 2>/dev/null
echo "== p1smoke done"
