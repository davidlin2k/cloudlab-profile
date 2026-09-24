#!/bin/bash
# perfsched.sh -- DR-003 decision 8: the mechanism for the 108.5 us
# co-location latency. 4 cells: P0 and P0X at 0.25x knee (130k, W1),
# with adaptive-rx on and off. Each cell: perf sched record (system-wide
# sched events) concurrent with p1cell; then sched latency + timehist
# for the k2_rx wake latency (the scheduler-wait instrument).
#
# Run AFTER WDIAG-DONE (one driver at a time). usage: perfsched.sh
set -u
mkdir -p /root/p1/perf
echo "PERFSCHED START $(date -u +%FT%TZ)"
for ADAPT in on off; do
  if [ "$ADAPT" = off ]; then
    ethtool -C enp195s0np0 adaptive-rx off
  else
    ethtool -C enp195s0np0 adaptive-rx on
  fi
  ethtool -c enp195s0np0 > /root/p1/perf/coalesce-$ADAPT.txt 2>&1
  for POL in P0 P0X; do
    TAG="perfsched-$POL-$ADAPT"
    echo "== $TAG $(date -u +%FT%TZ)"
    perf sched record -o /root/p1/perf/sched-$TAG.data -- sleep 80 > /root/p1/perf/sched-$TAG.rec 2>&1 &
    PERF=$!
    bash /root/k2/p1cell.sh "$POL" W1 130000 64 1 "$TAG" > /root/p1/perf/$TAG.celllog 2>&1
    wait $PERF
    perf sched latency -i /root/p1/perf/sched-$TAG.data > /root/p1/perf/sched-$TAG.latency.txt 2>&1
    perf sched timehist -i /root/p1/perf/sched-$TAG.data 2>/dev/null | grep -E 'k2_rx|k5blast' > /root/p1/perf/sched-$TAG.timehist.txt
    echo "-- wake latency top (k2_rx line):"
    grep -E 'k2_rx|Average' /root/p1/perf/sched-$TAG.latency.txt | head -3
    echo "-- p50_us from the cell:"
    grep -oE 'p50_us=[0-9.]+' /root/p1/perf/$TAG.celllog | tail -1
  done
done
ethtool -C enp195s0np0 adaptive-rx on
echo "PERFSCHED DONE $(date -u +%FT%TZ)"
touch /root/p1/PERFSCHED-DONE
