#!/bin/bash
# calsmt.sh -- SMT slowdown factor from matched micro-runs (root on rx).
# For each NAPI placement (P0 inline-on-8, P2 thread-on-8, P4 thread-on-9)
# run a 100k pps W1 cell with the placement's SMT sibling idle and then
# burning; the cyc/pkt and ns/pkt ratio is the SMT factor s feeding the
# knee model (Fig 4). Sibling pairs are (N, N+32): core 8 <-> 40, 9 <-> 41.
set -u
OUT=/root/p1/results/calsmt
mkdir -p "$OUT"
cd /root/k2 && gcc -O2 -o burn burn.c || exit 1
exec > >(tee "$OUT/calsmt.log") 2>&1
echo "== calsmt $(date -u +%FT%TZ)"

run_one() { # label policy burn_cpu
  local label=$1 policy=$2 bcpu=$3
  local BURN=""
  echo "-- $label (policy=$policy burn_cpu=$bcpu)"
  if [ "$bcpu" != "-" ]; then
    taskset -c "$bcpu" /root/k2/burn &
    BURN=$!
    sleep 0.3
  fi
  bash /root/k2/p1cell.sh "$policy" W1 100000 64 1 "calsmt-$label" 5 10 >/dev/null 2>&1
  [ -n "$BURN" ] && kill $BURN 2>/dev/null
  sed -n 's/.*cyc\/pkt=\([0-9.]*\).*/'"$label"' cyc_per_pkt=\1/p' \
    "/root/p1/results/calsmt-$label/W1-${policy}-r100000-p64/rep1/consumer.txt"
  sed -n 's/.*app_ns\/pkt=\([0-9.]*\).*/'"$label"' app_ns_per_pkt=\1/p' \
    "/root/p1/results/calsmt-$label/W1-${policy}-r100000-p64/rep1/consumer.txt"
}

run_one p0-idle  P0 -
run_one p0-burn  P0 40
run_one p2-idle  P2 -
run_one p2-burn  P2 40
run_one p4-idle  P4 -
run_one p4-burn  P4 41
echo "== calsmt done"
