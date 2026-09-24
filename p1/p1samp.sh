#!/bin/bash
# p1samp.sh -- 1 Hz per-core / per-thread CPU + landing/drop counters for
# one p1-LADDER cell. usage: p1samp.sh OUTFILE NAPI_PID APP_PID SECS
set -u
OUT=${1:?out}; NAPI_PID=${2:-}; APP_PID=${3:-}; SECS=${4:-75}
TQ=7
IRQN=$(grep -E "mlx5_comp${TQ}@pci:0000:c3" /proc/interrupts | awk '{print $1}' | tr -d ':')
KSI8=$(pgrep -x "ksoftirqd/8" | head -1)
KSI9=$(pgrep -x "ksoftirqd/9" | head -1)
{
for i in $(seq 1 "$SECS"); do
  echo "@$(date +%s.%N)"
  grep -E "^cpu(8|9|36|40) " /proc/stat
  awk -v n=9 'NR==n {print "softnet8", $0}' /proc/net/softnet_stat
  echo "irqcount $(grep -E "mlx5_comp${TQ}@pci:0000:c3" /proc/interrupts | awk '{s=0; for(i=2;i<=NF-3;i++) s+=$i; print s}')"
  [ -n "$NAPI_PID" ] && [ -d /proc/$NAPI_PID ] && \
    echo "task napi $(tr '\n' ' ' < /proc/$NAPI_PID/schedstat)"
  [ -n "$KSI8" ] && echo "task ksi8 $(tr '\n' ' ' < /proc/$KSI8/schedstat)"
  [ -n "$KSI9" ] && echo "task ksi9 $(tr '\n' ' ' < /proc/$KSI9/schedstat)"
  [ -n "$APP_PID" ] && [ -d /proc/$APP_PID ] && \
    echo "task app $(tr '\n' ' ' < /proc/$APP_PID/schedstat)"
  ethtool -S enp195s0np0 2>/dev/null | grep -E "rx${TQ}_packets:|rx_discards:|rx_out_of_buffer:" | tr -s ' ' | sed 's/^ *//;s/: / /;s/^/nic /'
  sleep 1
done
} > "$OUT" 2>&1
