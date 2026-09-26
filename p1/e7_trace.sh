#!/bin/bash
# p1/e7_trace.sh -- DR-008 E7 as revised by DR-009 Change 1: classify the
# threaded=0 latches (069/038/089 families) -- same contract bug via a
# different trigger, or a distinct second mechanism.
# Cell: 069's hit config (threaded=0 softirq NAPI, adaptive-rx on,
# ring 8192, gro on, striding on per night-1), flood 790k, and at
# flood+20s an irqbalance-style IRQ affinity move (312: cpu 8 -> cpu 12,
# AWAY from the busy app core) with the stranded-backlog logger running
# throughout. Question: does the softirq poll take the done-- detour,
# return budget-1, and strand the backlog?
set -u
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
exec >> /root/p1/e7.log 2>&1
echo "E7 START $(date -u +%FT%TZ) irq=$IRQ"

ethtool -G $IFACE rx 8192 || { echo "ring set FAIL"; exit 1; }
sleep 2
bash /root/p1/preflight.sh || exit 1
ethtool -C $IFACE adaptive-rx on 2>/dev/null || true
ethtool -K $IFACE gro on 2>/dev/null || true
bash /root/p1/preflight.sh || exit 1
echo "wiring: ring=$(ethtool -g $IFACE | awk '/RX:/{getline; print $2}') threaded=$(cat /sys/class/net/$IFACE/threaded) irq_aff=$(cat /proc/irq/$IRQ/smp_affinity_list)"

# channel 7 discovery (post-recreation addresses)
CH=$(sudo python3 /tmp/b2_dump.py 7 0 2 2>/dev/null | grep -m1 -oE "ch7 \(WEDGED\) @ 0x[0-9a-f]+" | grep -oE "0x[0-9a-f]+")
[ -n "$CH" ] || { echo "E7: discovery failed"; exit 1; }
echo "E7 ch7=$CH"

D=/root/p1/metastab/M1-e7-069
rm -rf "$D"; mkdir -p "$D"

# --- flood (5 x 158k), the app on core 8, threaded=0 already set ---
/root/k2/k2_rx --port 7777 --core 8 --secs 300 --skip 0 > "$D/consumer.txt" 2>&1 &
APP=$!
sleep 1
for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
  o=${pair%%:*}; s=${pair##*:}
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
    "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport $s --dport 7777 --rate 158000 --secs 240 --plen 64 --core 4 > /tmp/e7-snd-$o.txt 2>&1 </dev/null &'"
  sleep 0.4
done
echo "FLOOD START $(date -u +%FT%TZ)"

# --- the stranded-backlog logger for the whole cell ---
bash /tmp/stranded_logger.sh "$CH" "$D/stranded.log" 320 &
LOG=$!

sleep 20
echo "IRQ-MOVE $IRQ: 8 -> 12 (irqbalance-style, flood+20s) $(date -u +%FT%TZ)" | tee "$D/irqmove.txt"
echo 12 > /proc/irq/$IRQ/smp_affinity_list
sleep 20
# the 2017-case probe of whether the mask tracked: dump the driver's view
echo "post-move: irq_eff=$(cat /proc/irq/$IRQ/effective_affinity_list 2>/dev/null)"

# --- let the flood run; then the standard probe protocol ---
sleep 200
for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null; done
sleep 20
P0=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
echo "PROBE START rx7=$P0"
send_probe() {
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
    "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 30 --plen 64 --core 4 > /tmp/e7-probe.txt 2>&1 </dev/null &'"
}
send_probe
sleep 32
P1=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
ADV=$((P1 - P0))
if [ "$ADV" -ge 270000 ]; then echo "E7 PROBE-OK adv=$ADV"; else echo "E7 PROBE-DEAD adv=$ADV"; fi
kill $LOG 2>/dev/null; kill $APP 2>/dev/null

# --- dead-state dump for the record ---
sudo python3 /tmp/b2_dump.py 7 0 5 > /tmp/e7_dead_dump.txt 2>&1

# --- restore ---
bash /root/p1/rxrecover.sh /root/p1/rxrecover-e7.log || true
ethtool -G $IFACE rx 1024
bash /root/p1/preflight.sh
echo "E7 DONE $(date -u +%FT%TZ)"