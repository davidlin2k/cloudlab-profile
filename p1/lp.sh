#!/bin/bash
# lp.sh -- landing probe: verify the Toeplitz port authoring against real
# per-queue counters (root on rx). Predictions assume DPDK_KEY + identity
# indirection (queue = hash & 31), wire-order 4-tuple.
set -u
IFACE=enp195s0np0
probe() { # sport label
  mapfile -t before < <(ethtool -S $IFACE | awk '/^ *rx[0-9]+_packets:/ {gsub(/[: ]*/,"",$1); print $1, $2}')
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
    "sudo /root/e0/sportgen --dip 10.10.1.1 --dport 7777 --sport $1 --n 100000 --proto udp --plen 64 --batch 64 --pause 500" >/dev/null
  echo "-- $2 (sport $1):"
  while read -r q v; do
    nv=$(ethtool -S $IFACE | awk -v q="$q" '/^ *rx[0-9]+_packets:/ && $1==q":" {print $2}')
    d=$((nv - v))
    [ "$d" -gt 100 ] && echo "  ${q} delta=$d"
  done < <(printf '%s\n' "${before[@]}")
}
probe 32704 "pred q7"
probe 32718 "pred q1"
probe 32700 "pred q29"
