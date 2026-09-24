#!/bin/bash
# wcounters2.sh -- 1 Hz observer: queue-7 (napi/enp195s0np0-8263) state
# + ch7 counters. Exact-name lookup via /proc/*/comm (ps truncates comm
# to 15 chars; every napi/ thread shares the truncation).
set -u
MI=""
for p in /proc/[0-9]*; do
  c=$(cat "$p/comm" 2>/dev/null)
  if [ "$c" = "napi/enp195s0np0-8263" ]; then MI=${p#/proc/}; fi
done
echo "wcounters2 start $(date -u +%FT%TZ) napi8263_pid=${MI:-none}"
while true; do
  NOW=$(date +%s.%N)
  if [ -n "$MI" ] && [ -d "/proc/$MI" ]; then
    AFF=$(awk '/Cpus_allowed_list/{print $2}' /proc/$MI/status)
    STAT=$(awk '{print "ut="$14" st="$15" state="$3}' /proc/$MI/stat)
  else
    AFF=none
    STAT=state=gone
    for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); if [ "$c" = "napi/enp195s0np0-8263" ]; then MI=${p#/proc/}; fi; done
  fi
  TOT=$(grep -E "^ *312:" /proc/interrupts | awk '{print $2}')
  C=$(ethtool -S enp195s0np0 | grep -E 'ch7_(aff_change|arm|poll|eq_rearm)')
  echo "$NOW napi8263=$MI aff=$AFF $STAT irq312_tot=$TOT $C"
  sleep 1
done
