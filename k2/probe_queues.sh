#!/bin/bash
# probe_queues.sh -- discover which RX queue receives a fixed-sport stream.
# Run as root ON THE RECEIVER: ./probe_queues.sh <sender_ip> <sport>
set -uo pipefail
IFACE=${3:-enp195s0np0}
SENDER=${1:?sender ip}; SPORT=${2:?sport}
qget() { ethtool -S "$IFACE" 2>/dev/null | awk -v c="rx$1_packets" '$1==c":" {print $2}'; }

mapfile -t before < <(ethtool -S "$IFACE" | awk '/^ *rx[0-9]+_packets:/ {gsub(/[: ]*/,"",$1); print $1, $2}')
ssh -o StrictHostKeyChecking=no davidlin@"$SENDER" \
  "sudo /root/e0/sportgen --dip 10.10.1.1 --dport 7777 --sport $SPORT --n 50000 --proto udp --plen 1400 --batch 64 --pause 976" >/dev/null
while read -r q v; do
  nv=$(ethtool -S "$IFACE" | awk -v q="$q" '/^ *rx[0-9]+_packets:/ && $1==q":" {print $2}')
  d=$((nv - v))
  [ "$d" -gt 100 ] && echo "queue=${q#rx} delta=$d"
done < <(printf '%s\n' "${before[@]}")