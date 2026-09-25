#!/bin/bash
# tracewatch.sh OUTFILE -- DR-004 task 3 per-second counters (mono clock)
set -u
O="$1"
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
: > "$O"
while true; do
  T=$(awk '{print $1}' /proc/uptime)
  echo "@ $T" >> "$O"
  ethtool -S $IFACE | grep -E 'rx_out_of_buffer:|rx_buff_alloc_err:|rx_congst_umr:|ch7_poll:|ch7_arm:|ch7_events:|ch7_eq_rearm:|ch7_force_irq:|ch7_aff_change:|rx7_packets:|rx7_bytes:|rx7_csum_none:|rx7_csum_unnecessary:|rx7_xdp_drop:|rx7_xdp_redirect:|rx7_gro_' >> "$O"
  grep -E "^ *${IRQ}:" /proc/interrupts >> "$O"
  sleep 1
done
