#!/bin/bash
# preflight.sh -- DR-007 standing rule: run after EVERY ring/flag/channel
# change; asserts queue-7 steering before any cell counts. Exits 1 on
# failure (the batch must abort).
set -u
IFACE=${IFACE:-enp195s0np0}
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
echo "== preflight $(date -u +%FT%TZ)"
echo "ring: $(ethtool -g $IFACE | awk '/^RX:/{print $2}' | tail -1) striding: $(ethtool --show-priv-flags $IFACE | awk '/rx_striding_rq/{print $3}') threaded: $(cat /sys/class/net/$IFACE/threaded)"
# restore the task-1 defaults unless the caller exported overrides
RING=${RING:-1024}
STRIDING=${STRIDING:-on}
THREADED=${THREADED:-1}
ethtool -G $IFACE rx "$RING"
ethtool --set-priv-flags $IFACE rx_striding_rq "$STRIDING"
echo "$THREADED" > /sys/class/net/$IFACE/threaded
ethtool -C $IFACE adaptive-rx on >/dev/null 2>&1
ethtool -K $IFACE gro on >/dev/null 2>&1
for f in napi_defer_hard_irqs gro_flush_timeout; do
  p=/sys/class/net/$IFACE/queues/rx-7/$f; [ -e "$p" ] && echo 0 > "$p"
done
[ -e /proc/sys/net/core/busy_read ] && echo 0 > /proc/sys/net/core/busy_read
[ -n "$IRQ" ] && echo 8 > /proc/irq/$IRQ/smp_affinity_list
for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); case "$c" in napi/enp195s0np0-*) taskset -pc 0-63 "${p#/proc/}" >/dev/null 2>&1 ;; esac; done
# steering is by explicit ntuple rules (the RSS-key route was never
# reliable: p1prep's hkey set always failed on format; a reboot
# re-randomizes the key and the W1 sports hash elsewhere). Install the
# five W1 rules idempotently, then assert.
for pair in "10.10.1.10 32704" "10.10.1.11 32726" "10.10.1.12 32706" "10.10.1.13 32724" "10.10.1.14 32725"; do
  set -- $pair
  sudo ethtool -N $IFACE flow-type udp4 src-ip $1 dst-ip 10.10.1.1 src-port $2 dst-port 7777 action 7 >/dev/null 2>&1 || true
done
sleep 2
# assert queue-7 steering: a 10k probe at sport 32704 must advance rx7
P0=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 8 --plen 64 --core 4 > /tmp/preflight-probe.txt 2>&1 </dev/null &'"
sleep 10
P1=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
ADV=$((P1 - P0))
echo "steering assert: rx7 advance $ADV (need >= 14000)"
if [ "$ADV" -lt 14000 ]; then echo "PREFLIGHT FAIL -- queue-7 steering not asserted"; exit 1; fi
echo "PREFLIGHT OK"
