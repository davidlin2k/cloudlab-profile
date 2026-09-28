#!/bin/bash
# preflight.sh -- DR-007 standing rule: run after EVERY ring/flag/channel
# change; asserts queue-7 steering before any cell counts. Exits 1 on
# failure (the batch must abort).
#
# v2 (AN-010 fix): the W1 rules are now TRULY idempotent -- the old
# version re-ADDED all five rules every run; each add triggers a
# device flow-table reprogram whose duration grows with the rule
# count (the DB reached 70+ duplicates and the reprogram window grew
# past the assert's 14 s -- the steering asserts read zero while the
# device rebuilt). Now: the five rules are added only if missing.
set -u
IFACE=${IFACE:-enp195s0np0}
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
echo "== preflight $(date -u +%FT%TZ)"
echo "ring: $(ethtool -g $IFACE | awk '/^RX:/{print $2}' | tail -1) striding: $(ethtool --show-priv-flags $IFACE | awk '/rx_striding_rq/{print $3}') threaded: $(cat /sys/class/net/$IFACE/threaded)"
# restore the task-1 defaults unless the caller exported overrides
RING=${RING:-1024}
STRIDING=${STRIDING:-on}
THREADED=${THREADED:-1}
ethtool -G $IFACE rx "$RING"
ethtool --set-priv-flags $IFACE rx_striding_rq "$STRIDING"
echo "$THREADED" > /sys/class/net/$IFACE/threaded
ethtool -C $IFACE adaptive-rx on >/dev/null 2>&1
ethtool -K $IFACE gro on >/dev/null 2>&1
for f in napi_defer_hard_irqs gro_flush_timeout; do
  p=/sys/class/net/$IFACE/queues/rx-7/$f; [ -e "$p" ] && echo 0 > "$p"
done
[ -e /proc/sys/net/core/busy_read ] && echo 0 > /proc/sys/net/core/busy_read
[ -n "$IRQ" ] && echo 8 > /proc/irq/$IRQ/smp_affinity_list
for p in /proc/[0-9]*; do c=$(cat "$p/comm" 2>/dev/null); case "$c" in napi/enp195s0np0-*) taskset -pc 0-63 "${p#/proc/}" >/dev/null 2>&1 ;; esac; done

# --- the W1 rules, idempotent: add a sport's rule only if missing ---
HAVE=$(ethtool -n $IFACE 2>/dev/null)
ADDED=0
for pair in "10.10.1.10 32704" "10.10.1.11 32726" "10.10.1.12 32706" "10.10.1.13 32724" "10.10.1.14 32725"; do
  set -- $pair
  if ! echo "$HAVE" | grep -q "Src port: $2 "; then
    ethtool -N $IFACE flow-type udp4 src-ip $1 dst-ip 10.10.1.1 src-port $2 dst-port 7777 action 7 >/dev/null 2>&1 || true
    ADDED=$((ADDED + 1))
  fi
done
echo "rules added: $ADDED total-q7: $(ethtool -n $IFACE 2>/dev/null | grep -c 'Direct to queue 7')"
sleep 2
# assert queue-7 steering: a 10k probe at sport 32704 must advance rx7.
# The sender's ssh-setup latency varies (a cold sender sshd adds 2-3 s
# before the 8 s burst starts); read P1 at +14 s so the whole burst
# lands inside the window.
P0=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
declare -A Q0
for q in $(seq 0 15); do
  Q0[$q]=$(ethtool -S $IFACE | awk -v Q=$q '$1 ~ "^rx"Q"_packets:" {print $2}')
done
ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 8 --plen 64 --core 4 > /tmp/preflight-probe.txt 2>&1 </dev/null &'"
sleep 14
P1=$(ethtool -S $IFACE | awk '/rx7_packets:/{print $2}')
ADV=$((P1 - P0))
echo "steering assert: rx7 advance $ADV (need >= 14000)"
if [ "$ADV" -lt 14000 ]; then
  echo "PREFLIGHT FAIL -- queue-7 steering not asserted"
  # facts for the failure: the sender's status, the per-queue deltas,
  # the rule count (the 10k x 8 s probe = ~80k on the steered queue)
  scp -q davidlin@10.10.1.10:/tmp/preflight-probe.txt /tmp/pf-status.txt 2>/dev/null \
    && tail -2 /tmp/pf-status.txt
  for q in $(seq 0 15); do
    B=$(ethtool -S $IFACE | awk -v Q=$q '$1 ~ "^rx"Q"_packets:" {print $2}')
    echo "  rx$q delta: $((B - ${Q0[$q]:-0}))" 2>/dev/null
  done
  echo "  rules: $(ethtool -n $IFACE 2>/dev/null | grep -c 'Direct to queue 7')"
  exit 1
fi
echo "PREFLIGHT OK"