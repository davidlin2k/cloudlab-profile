#!/bin/bash
# rxrecover.sh -- DR-007 standing rule: run after EVERY dead cell; logs
# the reviving step to $1 (default /root/p1/rxrecover.log). Halts with
# exit 1 if the queue cannot be revived (the caller must alert the PI).
set -u
IFACE=${IFACE:-enp195s0np0}
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
LOG=${1:-/root/p1/rxrecover.log}
log(){ echo "$(date -u +%FT%TZ) $*" | tee -a "$LOG"; }
probe(){ # 8 s at 10k, print advance
  P0=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 8 --plen 64 --core 4 > /dev/null 2>&1 </dev/null &'"
  sleep 10
  P1=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  echo $((P1 - P0))
}
# re-pin before probing so a revived queue is measurable under the
# task 1 wiring
[ -n "$IRQ" ] && echo 8 > /proc/irq/$IRQ/smp_affinity_list
for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); case "$c" in napi/enp195s0np0-*) taskset -pc 0-63 "${p#/proc/}" >/dev/null 2>&1 ;; esac; done

A=$(probe); log "baseline probe adv=$A"
[ "$A" -ge 14000 ] && { log "ALIVE-NO-RECOVERY-NEEDED"; exit 0; }

echo 0 > /sys/class/net/$IFACE/threaded; sleep 5
echo 1 > /sys/class/net/$IFACE/threaded; sleep 3
A=$(probe); log "step1 threaded-toggle adv=$A"
if [ "$A" -ge 14000 ]; then log "RECOVERED-BY-THREADED-TOGGLE"; exit 0; fi

ethtool -L $IFACE combined 32; sleep 3
A=$(probe); log "step2 channels-32 adv=$A"
if [ "$A" -ge 14000 ]; then log "RECOVERED-BY-CHANNELS"; exit 0; fi

ethtool -L $IFACE combined 16; sleep 2
ethtool -L $IFACE combined 32; sleep 3
[ -n "$IRQ" ] && echo 8 > /proc/irq/$IRQ/smp_affinity_list
A=$(probe); log "step3 recreate-16-32 adv=$A"
if [ "$A" -ge 14000 ]; then log "RECOVERED-BY-RECREATION"; exit 0; fi

log "UNRECOVERED -- HALT AND ALERT THE PI"
exit 1
