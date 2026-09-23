#!/bin/bash
# k5cap.sh -- capacity: saturated drain rate per core (K5CAP).
# Usage (root on rx): k5cap.sh <ports_per_core> <cpu_list> <secs> <rep> [plen]
# cpu list entries must be the softirq homes of RSS queues 0..n-1:
# after pin_irqs.sh (comp_j -> cpu j+1) cpu list "1" = queue 0,
# "1,2" = queues 0,1, etc. One sportgen blaster per port, pinned to the
# (sip, sport) its dport was authored for. Done-flag handshake per
# blaster; blaster logs verified non-empty (stale-log trap).
set -u
NPC=${1:?ports per core}; CPUS=${2:?cpu list like 1 or 1,2}; SECS=${3:-10}
REP=${4:-1}; PLEN=${5:-300}
IFACE=enp195s0np0
OUT=/root/k5/cap-${NPC}p-${CPUS//,/-}-r${REP}-$(date +%H%M%S)
mkdir -p "$OUT"
comb=$(ethtool -l $IFACE | awk '/Combined/{c=$2} END{print c}')
[ "$comb" = "32" ] || { echo "GATE FAIL: Combined=$comb"; exit 2; }

# --- pick ports: group g uses queue g; one (sip,sport) per port,
#     distinct across the whole rung
declare -A used=()
DPORTS=(); SENDERS=(); SPORTS=()
nc=$(echo "$CPUS" | awk -F, '{print NF}')
for g in $(seq 0 $((nc - 1))); do
	taken=0
	while read -r sip sport dp q; do
		[ $taken -ge $NPC ] && break
		[ "$q" -ne "$g" ] && continue
		key="$sip:$sport"
		[ -n "${used[$key]:-}" ] && continue
		used[$key]=1
		DPORTS+=("$dp"); SENDERS+=("$sip"); SPORTS+=("$sport")
		taken=$((taken + 1))
	done < <(awk '$4 == '"$g"'' /root/k5/porttable.txt)
	[ $taken -lt $NPC ] && { echo "GATE FAIL: not enough authored ports for queue $g"; exit 2; }
done
echo "ports: ${DPORTS[*]}"

# --- preflight
pkill -x sportgen 2>/dev/null; pkill -x k4reins 2>/dev/null; sleep 0.5
ssh davidlin@10.10.1.10 'sudo pkill -x sportgen' 2>/dev/null
# (senders get cleaned by their own launch wrapper below)

# --- receiver: one thread per core group, ports authored to its queue
PJ=$(IFS=,; echo "${DPORTS[*]}")
nohup /root/k2/k4reins --secs $((SECS + 8)) --knee 3000000 \
	--cores "$CPUS" --ports "$PJ" > "$OUT/k4reins.log" 2>&1 &
sleep 1
pgrep -x k4reins >/dev/null || { echo "GATE FAIL: k4reins not running"; exit 2; }

# --- blasters: detached per sender, done-flag handshake
for i in "${!DPORTS[@]}"; do
	tx="10.10.1.${SENDERS[$i]}"
	ssh -o ConnectTimeout=10 davidlin@$tx \
	  "sudo rm -f /tmp/sg-${SPORTS[$i]}.done /tmp/sg-${SPORTS[$i]}.log; \
	   sudo nohup bash -c 'sleep 1; /root/e0/sportgen --dip 10.10.1.1 \
	     --dport ${DPORTS[$i]} --sport ${SPORTS[$i]} \
	     --n $((SECS * 3000000)) --proto udp --plen $PLEN --batch 64 \
	     --pause 0 > /tmp/sg-${SPORTS[$i]}.log 2>&1; \
	     touch /tmp/sg-${SPORTS[$i]}.done' >/dev/null 2>&1 &"
done
# --- wait (poll every 2s, generous bound)
for i in "${!DPORTS[@]}"; do
	tx="10.10.1.${SENDERS[$i]}"; f="/tmp/sg-${SPORTS[$i]}.done"
	for t in $(seq 1 $((SECS * 4))); do
		ssh -o ConnectTimeout=10 davidlin@$tx "[ -f $f ]" 2>/dev/null && break
		sleep 2
	done
done
sleep 2
while pgrep -x k4reins >/dev/null; do sleep 1; done
# --- stale-log trap: every blaster log must be non-empty and fresh
for i in "${!DPORTS[@]}"; do
	tx="10.10.1.${SENDERS[$i]}"; s=${SPORTS[$i]}
	n=$(ssh -o ConnectTimeout=10 davidlin@$tx "sudo wc -c < /tmp/sg-$s.log" 2>/dev/null)
	case ${n:-0} in ''|*[!0-9]*) n=0;; esac
	[ "$n" -lt 20 ] && echo "GATE FAIL: empty blaster log sip=${SENDERS[$i]} sport=$s"
done
echo "==== $OUT"
grep -E "\[gate\]|\[k4reins\] (port|grp)" "$OUT/k4reins.log"
echo "capacity: consumed total / $SECS s (per port lines above)"