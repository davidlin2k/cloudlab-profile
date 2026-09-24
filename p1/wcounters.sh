#!/bin/bash
# wcounters.sh -- 1 Hz mlx5 channel-7 + NAPI-kthread observer
# (DR-002/AN-003 test 1, PI-designed 2026-09-24). LOCAL reads only
# (ethtool -S, /proc), pinned to CPU 62: zero cross-node bytes and no
# instrumented core touched (cpu8/app/napi accounting excludes it).
IFACE=enp195s0np0
echo "wdiag counter watch start $(date -u +%FT%TZ)"
echo "counters: $(ethtool -S $IFACE | grep -oE 'ch[0-9]+_[a-z0-9_]+' | grep -iE 'aff|arm|rearm|poll' | sort -u | tr '\n' ' ')"
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
while :; do
  T=$(date +%s.%N)
  NAP=$(pgrep -f 'napi/enp195s0np0' | head -1)
  AFF="-"
  [ -n "$NAP" ] && AFF=$(grep Cpus_allowed_list /proc/$NAP/status | awk '{print $2}')
  IRTOT=$(grep -E "^ *${IRQ}:" /proc/interrupts | awk '{s=0; for(i=2;i<=65;i++) s+=$i; print s}')
  IRMASK=$(grep -E "^ *${IRQ}:" /proc/interrupts | sed 's/.*enp195s0np0.*/&/' | grep -o 'PCI-MSI.*' | head -c 40)
  V=$(ethtool -S $IFACE | grep -iE 'ch7.*(aff|arm|rearm)' | tr -s ' ' | tr '\n' ' ')
  echo "$T napi_pid=${NAP:--} napi_aff=$AFF irq${IRQ}_tot=${IRTOT:--} $V"
  sleep 1
done
