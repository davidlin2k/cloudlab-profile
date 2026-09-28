#!/bin/bash
# p1/t1b_preflight.sh -- T1B (DR-015): i40e/Intel X710 preflight.
# Idempotent Flow Director rule install (the preflight-v2 pattern:
# add a rule only if missing; AN-010: rule adds reprogram the device).
# Pins the flooded queue's IRQ to the IRQ core, sets threaded NAPI,
# then asserts queue-7 steering with a 10k pps x 8 s probe.
#
# Env: IFACE (the experiment NIC), SENDER (the pair's sender IP),
#      DUTIP (this node's 10.10.1.x), IRQCPU (the IRQ core), Q (queue).
set -u
IFACE=${IFACE:-enp24s0f1np1}
SENDER=${SENDER:-10.10.1.10}
DUTIP=${DUTIP:-10.10.1.1}
IRQCPU=${IRQCPU:-6}
Q=${Q:-7}
SPORT=${SPORT:-32704}
SSH="ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no davidlin@$SENDER"

echo "== t1b preflight $(date -u +%FT%TZ) iface=$IFACE irqcore=$IRQCPU"
threaded=$(cat /sys/class/net/$IFACE/threaded)
echo "threaded: $threaded"
echo 1 > /sys/class/net/$IFACE/threaded
ethtool -G $IFACE rx 512 2>/dev/null || true   # modest rings on 10G
# --- the IRQ core pin (the setup's boot spread races i40e probe) ---
IRQ=$(grep -E "i40e-.*TxRx-$Q\b" /proc/interrupts | awk -F: '{print $1}' | tr -d ' ' | head -1)
if [ -n "$IRQ" ]; then echo "$IRQCPU" > /proc/irq/$IRQ/smp_affinity_list; fi
echo "irq TxRx-$Q=$IRQ pinned to $IRQCPU"

# --- the FD rule, idempotent ---
HAVE=$(ethtool -n $IFACE 2>/dev/null)
ADDED=0
if ! echo "$HAVE" | grep -qE "Src port: $SPORT\b"; then
  ethtool -N $IFACE flow-type udp4 src-ip $SENDER dst-ip $DUTIP \
    src-port $SPORT dst-port 7777 action $Q >/dev/null 2>&1 && ADDED=1
fi
RULES=$(ethtool -n $IFACE 2>/dev/null | grep -cE "Action: (The packet is|)$Q\b|$Q\b")
echo "rules added: $ADDED"
sleep 2

# --- steering assert: 10k pps x 8 s must advance rx$Q ---
RXQ=/sys/class/net/$IFACE/queues/rx-$Q
P0=$(cat $RXQ/rx_packets 2>/dev/null || echo 0)
$SSH "sudo bash -c 'nohup /root/k2/k5blast --dip $DUTIP --sip ${SENDER##*.} --sport $SPORT --dport 7777 --rate 10000 --secs 8 --plen 64 --core 4 > /tmp/pf-status.txt 2>&1 </dev/null &'" >/dev/null 2>&1
sleep 14
P1=$(cat $RXQ/rx_packets)
ADV=$((P1 - P0))
echo "steering assert: rx$Q advance $ADV (need >= 14000)"
if [ "$ADV" -lt 14000 ]; then
  echo "T1B-PREFLIGHT-FAIL"
  exit 1
fi
echo "T1B-PREFLIGHT-OK"