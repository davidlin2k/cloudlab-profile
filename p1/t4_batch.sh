#!/bin/bash
# t4_batch.sh [ARM [START [END]]] -- DR-005 task 4: the two mechanism A/Bs
# Arms: ring-default (RX 1024), ring-8192, striding-off (RX 1024 +
# rx_striding_rq off). 8 cells each (the memo). Each cell = the task 1
# unpin M158 cell (p1/metastab.sh M "10" t4-<arm>-<i>).
# After EVERY ring or flag change (the memo): the full pre-flight
# (RSS key capture, port-map probe, IRQ 312 -> CPU 8 re-pin) and the
# queue-7 NAPI-thread rediscovery (5 s flood at 158k; the
# napi/enp195s0np0-* thread whose utime+stime grows most). Step-4
# recovery before every cell. Skips cells that already have a probe
# verdict. Restores defaults at the end.
set -u
IFACE=enp195s0np0
exec >> /root/p1/t4-batch.log 2>&1
echo "T4 BATCH START $(date -u +%FT%TZ) args=$*"

preflight() { # $1 = arm label
  echo "== preflight $1 $(date -u +%FT%TZ)"
  ethtool -g $IFACE | sed -n '1,12p'
  ethtool -x $IFACE > /root/p1/t4-rss-$1.txt
  IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
  echo 8 > /proc/irq/$IRQ/smp_affinity_list
  echo 1 > /sys/class/net/$IFACE/threaded
  for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); case "$c" in napi/enp195s0np0-*) taskset -pc 0-63 "${p#/proc/}" >/dev/null 2>&1 ;; esac; done
  sleep 2
  # port-map probe: sport 32704 must land on queue 7
  P0=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 8 --plen 64 --core 4 > /tmp/t4-portmap.txt 2>&1 </dev/null &'"
  sleep 10
  P1=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
  echo "portmap probe adv=$((P1 - P0))"
  [ $((P1 - P0)) -ge 14000 ] || { echo "PORTMAP FAIL -- aborting the batch"; exit 1; }
  # NAPI rediscovery: 5 s flood at 158k, the thread whose time grows most
  declare -A T0
  for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); case "$c" in napi/enp195s0np0-*) T0[${p#/proc/}]=$(awk '{print $14+$15}' "$p/stat" 2>/dev/null) ;; esac; done
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 158000 --secs 5 --plen 64 --core 4 > /tmp/t4-rediscover.txt 2>&1 </dev/null &'"
  sleep 7
  BEST=none; BESTD=-1
  for pid in "${!T0[@]}"; do
    [ -d /proc/$pid ] || continue
    D=$(( $(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null || echo 0) - ${T0[$pid]:-0} ))
    echo "napi pid=$pid dticks=$D"
    [ "$D" -gt "$BESTD" ] && { BESTD=$D; BEST=$pid; }
  done
  echo "queue7 NAPI thread rediscovered: pid=$BEST (dticks=$BESTD)"
}

recover() { bash /tmp/t2recover.sh; }

run_arm() {
  local ARM="$1" START="${2:-1}" END="${3:-8}"
  case "$ARM" in
    ring-default) ethtool -G $IFACE rx 1024; ethtool --set-priv-flags $IFACE rx_striding_rq on ;;
    ring-8192)    ethtool -G $IFACE rx 8192; ethtool --set-priv-flags $IFACE rx_striding_rq on ;;
    striding-off) ethtool -G $IFACE rx 1024; ethtool --set-priv-flags $IFACE rx_striding_rq off ;;
    *) echo "unknown arm $ARM"; exit 2 ;;
  esac
  sleep 2
  preflight "$ARM"
  for i in $(seq "$START" "$END"); do
    local D=/root/p1/metastab/M1-t4-$ARM-$i
    if grep -q 'PROBE-' "$D/cell.env" 2>/dev/null; then echo "== $ARM cell $i SKIP"; continue; fi
    echo "== $ARM cell $i $(date -u +%FT%TZ)"
    recover
    bash /root/p1/metastab.sh M "10" "t4-$ARM-$i"
    if grep -q 'PROBE-DEAD\|NOT-RECOVERED' "$D/cell.env" 2>/dev/null; then recover; fi
  done
}

if [ "$#" -ge 1 ]; then
  run_arm "$1" "${2:-1}" "${3:-8}"
else
  run_arm ring-default 1 8
  run_arm ring-8192 1 8
  run_arm striding-off 1 8
  # restore the platform defaults
  ethtool -G $IFACE rx 1024
  ethtool --set-priv-flags $IFACE rx_striding_rq on
  preflight restore
fi
echo "T4 BATCH DONE $(date -u +%FT%TZ)"
touch /root/p1/T4-DONE
