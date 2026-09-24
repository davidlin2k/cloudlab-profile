#!/bin/bash
# Step-clock sweep master. Runs on the workstation; orchestrates
# emitters (n3-n5), HAProxy (n1), sink (n6), instrument (n1).
# Per cell: relaunch sink, wait live>=98%, 3 reps x (15s discard +
# 60s measure). Records sink metrics + emitter overrun gate.
#
# Usage: sweep_master.sh <phase-mode> <csv-out>
set -u
PHASE=$1
CSV=$PWD/results/$PHASE.csv
ENGINES="clnode323 clnode386 clnode322"
N1="clnode366"
N6="clnode331"
CSV=/mnt/davidlin-personal/cloudlab-profile/clock/results/$PHASE.csv
mkdir -p "$(dirname "$CSV")"
echo "streams,rep,live,errs,stalls,stall_s,tokens,p50_itl_ms,p99_itl_ms,rate_tok_s,drops,slow_writes,slot_overruns,em_cpu_s,phase" > "$CSV"

for S in 25000 50000 75000 100000; do  # PI spec D: knee region
  echo "== $PHASE N=$S $(date -u +%H:%M:%S)" >&2
  # relaunch emitters with the right phase (4 processes per node)
  for n in $ENGINES; do
    ssh -o ConnectTimeout=10 davidlin@$n.clemson.cloudlab.us "bash /tmp/clock/relaunch_emitters.sh $PHASE" &
  done
  wait
  sleep 2
  ssh -o ConnectTimeout=10 davidlin@$N6.clemson.cloudlab.us "sudo pkill -xc clocksink; sleep 2; sudo rm -f /tmp/clock/sw-${PHASE}-${S}.log"
  # launch sink
  ssh -o ConnectTimeout=10 davidlin@$N6.clemson.cloudlab.us \
    "sudo bash -c 'nohup /tmp/clock/clocksink -proxy http://10.10.1.1:9000 -streams $S -dial-rate 10000 -window 1 > /tmp/clock/sw-${PHASE}-${S}.log 2>&1 < /dev/null &'"
  # wait for live >= 98% of S
  ok=0
  for i in $(seq 1 90); do
    live=$(ssh -o ConnectTimeout=10 davidlin@$N6.clemson.cloudlab.us \
      "curl -s -m 3 http://127.0.0.1:9200/stats" 2>/dev/null | grep -oE "live=[0-9]+" | cut -d= -f2)
    [ -n "$live" ] && [ "$live" -ge $((S * 98 / 100)) ] && ok=1 && break
    sleep 5
  done
  [ "$ok" = "1" ] || { echo "$S,connect_timeout,0,0,0,0,0,0,0,0,0,0,0,0,$PHASE" >> "$CSV"; continue; }
  # 3 reps: 15s discard + 60s measure each
  for rep in 1 2 3; do
    sleep 15  # discard
    sleep 60  # measure
    last=$(ssh -o ConnectTimeout=10 davidlin@$N6.clemson.cloudlab.us \
      "grep -E 'rate=' /tmp/clock/sw-${PHASE}-${S}.log | tail -1" 2>/dev/null)
    live=$(echo "$last" | grep -oE "live=[0-9]+" | cut -d= -f2)
    errs=$(echo "$last" | grep -oE "errs=[0-9]+" | cut -d= -f2)
    stalls=$(echo "$last" | grep -oE "stalls=[0-9]+" | cut -d= -f2)
    stall_s=$(echo "$last" | grep -oE "stall_s=[0-9]+" | cut -d= -f2)
    tok=$(echo "$last" | grep -oE "tokens=[0-9]+" | cut -d= -f2)
    p50=$(echo "$last" | grep -oE "p50_itl_ms=[0-9]+" | cut -d= -f2)
    p99=$(echo "$last" | grep -oE "p99_itl_ms=[0-9]+" | cut -d= -f2)
    rate=$(echo "$last" | grep -oE "rate=[0-9]+" | cut -d= -f2)
    estats=$(ssh -o ConnectTimeout=10 davidlin@clnode323.clemson.cloudlab.us \
      "for h in 10.10.1.11 10.10.1.12 10.10.1.13; do for q in 8000 8001 8002 8003; do curl -s -m 3 http://\$h:\$q/stats; done; done" 2>/dev/null)
    over=$(echo "$estats" | grep -oE "slot_overruns=[0-9]+" | cut -d= -f2 | paste -sd+ - | bc)
    drops=$(echo "$estats" | grep -oE "dropped=[0-9]+" | cut -d= -f2 | paste -sd+ - | bc)
    slow=$(echo "$estats" | grep -oE "slow_writes=[0-9]+" | cut -d= -f2 | paste -sd+ - | bc)
    ecpu=$(echo "$estats" | grep -oE "cpu_s=[0-9.]+" | cut -d= -f2 | paste -sd+ - | bc)
    echo "$S,$rep,${live:-0},${errs:-0},${stalls:-0},${stall_s:-0},${tok:-0},${p50:-0},${p99:-0},${rate:-0},${drops:-0},${slow:-0},${over:-0},${ecpu:-0},$PHASE" >> "$CSV"
    echo "  rep $rep: live=$live rate=$rate tok=$tok stall_s=$stall_s drops=$drops slow=$slow slip=$over" >&2
  done
done
ssh -o ConnectTimeout=10 davidlin@$N6.clemson.cloudlab.us "sudo pkill -xc clocksink" 2>/dev/null
echo master_complete >> "$CSV"
