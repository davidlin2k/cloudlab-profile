#!/bin/bash
# relaunch_emitters.sh <phase> — (re)start the 12-emitter fleet share
# on THIS node: ports 8000-8003, 25k streams each, 25ms period, 100B.
set -u
PHASE=${1:?aligned|random|per-engine}
sudo pkill -xc clockemit 2>/dev/null || true
sleep 1
for p in 8000 8001 8002 8003; do
  sudo rm -f "/tmp/clock/e-$p.log"
  sudo bash -c "nohup /tmp/clock/clockemit -listen :$p -streams 25000 -period 25 -phase $PHASE -chunk 100 > /tmp/clock/e-$p.log 2>&1 < /dev/null &"
done
sleep 2
up=0
for p in 8000 8001 8002 8003; do
  curl -s -m 3 "http://127.0.0.1:$p/healthz" | grep -q streams && up=$((up+1))
done
echo "emitters_up=$up phase=$PHASE"
