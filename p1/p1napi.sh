#!/bin/bash
# p1napi.sh -- decisive NAPI identity probe (root on rx): RAW schedstat
# values per napi thread before/after a single-queue blast in threaded
# mode, per-queue landing check in threaded mode, rmem state, and the
# uapi header for the netlink queue->napi_id mapping (fallback).
set -u
IFACE=enp195s0np0
echo "== rmem"; sysctl net.core.rmem_max net.core.rmem_default
echo "== threaded NAPI raw probe"
echo 1 > /sys/class/net/$IFACE/threaded
sleep 0.5
snap() {
  for p in $(ls /proc | grep -E '^[0-9]+$'); do
    c=$(cat /proc/$p/comm 2>/dev/null)
    case "$c" in
      napi/*) echo "$p $(tr '\n' ' ' < /proc/$p/schedstat 2>/dev/null)" ;;
    esac
  done | sort -n
}
snap > /tmp/raw-pre
mapfile -t before < <(ethtool -S $IFACE | awk '/^ *rx[0-9]+_packets:/ {gsub(/[: ]*/,"",$1); print $1, $2}')
ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
  "sudo /root/e0/sportgen --dip 10.10.1.1 --dport 7777 --sport 32704 --n 200000 --proto udp --plen 64 --batch 64 --pause 500" >/dev/null
echo "-- landing in threaded mode:"
while read -r q v; do
  nv=$(ethtool -S $IFACE | awk -v q="$q" '/^ *rx[0-9]+_packets:/ && $1==q":" {print $2}')
  d=$((nv - v))
  [ "$d" -gt 100 ] && echo "   ${q} delta=$d"
done < <(printf '%s\n' "${before[@]}")
snap > /tmp/raw-post
echo "-- raw schedstat pre/post (pid runtime wait slices):"
join /tmp/raw-pre /tmp/raw-post | head -40
echo 0 > /sys/class/net/$IFACE/threaded
echo "== netlink uapi"
ls /usr/include/linux/ | grep -i netdev
grep -n "NETDEV_CMD_QUEUE_GET_DUMP\|NETDEV_A_QUEUE_NAPI\|NETDEV_A_QUEUE_ID" /usr/include/linux/netdev.h 2>/dev/null | head -8
echo "== done"
