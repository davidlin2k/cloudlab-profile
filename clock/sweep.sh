#!/bin/bash
# Step-clock sweep driver (runs on n6). Drives the sink through the
# stream staircase; per point: open streams, wait for steady state,
# soak 60 s, record rate + counters. The instrument on n1 records
# kernel layers continuously; correlate by wall-clock.
set -u
PROXY="http://10.10.1.1:9000"
OUT="$1"   # csv path
TAG="$2"   # phase tag (aligned|random)
shift 2
mkdir -p "$(dirname "$OUT")"
echo "streams,live,errs,rate_tok_s,phase" > "$OUT"
for S in "$@"; do
  pkill -xc clocksink 2>/dev/null || true
  sleep 3
  nohup /tmp/clock/clocksink -proxy "$PROXY" -streams "$S" -dial-rate 10000 \
      > "/tmp/clock/sw-${TAG}-${S}.log" 2>&1 < /dev/null &
  # wait for live to reach 98% of S (max 6 min)
  ok=0
  for i in $(seq 1 72); do
    live=$(curl -s -m 3 http://127.0.0.1:9200/stats | grep -oE "live=[0-9]+" | cut -d= -f2)
    [ -n "$live" ] && [ "$live" -ge $((S * 98 / 100)) ] && ok=1 && break
    sleep 5
  done
  [ "$ok" = "1" ] || { echo "$S,connect_timeout,0,0,$TAG" >> "$OUT"; continue; }
  sleep 60   # soak: instrument sees the steady state
  rate=$(grep -oE "rate=[0-9]+" "/tmp/clock/sw-${TAG}-${S}.log" | tail -1 | cut -d= -f2)
  live=$(curl -s -m 3 http://127.0.0.1:9200/stats | grep -oE "live=[0-9]+" | cut -d= -f2)
  errs=$(curl -s -m 3 http://127.0.0.1:9200/stats | grep -oE "errs=[0-9]+" | cut -d= -f2)
  echo "$S,${live:-0},${errs:-0},${rate:-0},$TAG" >> "$OUT"
  echo "point $S done: live=$live rate=$rate" >&2
done
pkill -xc clocksink 2>/dev/null || true
echo sweep_complete >> "$OUT"
