#!/bin/bash
# k5cap.sh -- capacity: saturated drain rate per core (K5CAP).
# Usage (root on rx): k5cap.sh <ports_per_core> <cpu_list> <secs> <rep> [plen]
# cpu list entries must be the softirq homes of RSS queues 0..n-1:
# after pin_irqs.sh (comp_j -> cpu j+1) cpu list "1" = queue 0,
# "1,2" = queues 0,1, etc. Demand side: k5blast spin-paced sendmmsg
# blasters, up to 3 per port (extra (sip,sport) pairs that hash the
# same dport onto queue 0, from blasters.txt), so the receiver core is
# saturated and its consumed rate IS the capacity. Per the method
# rules: sender capacity must exceed offered load; a blaster that
# finishes early fails the cell.
set -u
NPC=${1:?ports per core}; CPUS=${2:?cpu list like 1 or 1,2}; SECS=${3:-10}
REP=${4:-1}; PLEN=${5:-300}
NBLAST=3
IFACE=enp195s0np0
OUT=/root/k5/cap-${NPC}p-${CPUS//,/-}-r${REP}-$(date +%H%M%S)
mkdir -p "$OUT"
comb=$(ethtool -l $IFACE | awk '/Combined/{c=$2} END{print c}')
[ "$comb" = "32" ] || { echo "GATE FAIL: Combined=$comb"; exit 2; }

# --- pick ports: group g uses queue g; one authored (sip,sport) per port
declare -A used=()
DPORTS=()
nc=$(echo "$CPUS" | awk -F, '{print NF}')
for g in $(seq 0 $((nc - 1))); do
	taken=0
	while read -r sip sport dp q; do
		[ $taken -ge $NPC ] && break
		[ "$q" -ne "$g" ] && continue
		key="$sip:$sport"
		[ -n "${used[$key]:-}" ] && continue
		used[$key]=1
		DPORTS+=("$dp")
		taken=$((taken + 1))
	done < <(awk '$4 == '"$g"'' /root/k2/porttable.txt)
	[ $taken -lt $NPC ] && { echo "GATE FAIL: not enough authored ports for queue $g"; exit 2; }
done
echo "ports: ${DPORTS[*]}"

# --- blasters per port: primary + secondaries from blasters.txt
B_DP=(); B_SIP=(); B_SPORT=()
for dp in "${DPORTS[@]}"; do
	nb=0
	while read -r d sip sport; do
		[ "$d" -ne "$dp" ] && continue
		[ $nb -ge $NBLAST ] && break
		key="$sip:$sport"
		[ -n "${used[$key]:-}" ] && continue
		used[$key]=1
		B_DP+=("$dp"); B_SIP+=("$sip"); B_SPORT+=("$sport")
		nb=$((nb + 1))
	done < <(awk -v d="$dp" '$1 == d' /root/k2/blasters.txt)
	[ $nb -eq 0 ] && { echo "GATE FAIL: no blaster for dport $dp"; exit 2; }
done
echo "blasters: ${#B_DP[@]}"

# --- preflight
pkill -x k5blast 2>/dev/null; pkill -x k4reins 2>/dev/null; sleep 0.5
for tx in 10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13 10.10.1.14; do
	ssh -o ConnectTimeout=10 davidlin@$tx 'sudo pkill -x k5blast' 2>/dev/null
done

# --- receiver
PJ=$(IFS=,; echo "${DPORTS[*]}")
nohup /root/k2/k4reins --secs $((SECS + 10)) --knee 3000000 \
	--cores "$CPUS" --ports "$PJ" > "$OUT/k4reins.log" 2>&1 &
sleep 1
pgrep -x k4reins >/dev/null || { echo "GATE FAIL: k4reins not running"; exit 2; }

# --- blasters, detached, done-flag handshake
NB=${#B_DP[@]}
for i in $(seq 0 $((NB - 1))); do
	tx="10.10.1.${B_SIP[$i]}"; s=${B_SPORT[$i]}; dp=${B_DP[$i]}
	ssh -o ConnectTimeout=10 davidlin@$tx \
	  "sudo rm -f /tmp/k5b-$s.done /tmp/k5b-$s.log; \
	   sudo nohup bash -c 'sleep 1; /root/k2/k5blast --dip 10.10.1.1 \
	     --sip ${B_SIP[$i]} --sport $s --dport $dp \
	     --n $((SECS * 2000000)) --plen $PLEN --batch 64 \
	     > /tmp/k5b-$s.log 2>&1; touch /tmp/k5b-$s.done' >/dev/null 2>&1 &"
done
# --- wait for every done flag; a missing flag fails the cell
for i in $(seq 0 $((NB - 1))); do
	tx="10.10.1.${B_SIP[$i]}"; f="/tmp/k5b-${B_SPORT[$i]}.done"
	seen=0
	for t in $(seq 1 $((SECS * 6))); do
		if ssh -o ConnectTimeout=10 davidlin@$tx "[ -f $f ]" 2>/dev/null; then
			seen=1; break
		fi
		sleep 2
	done
	[ $seen -eq 1 ] || echo "GATE FAIL: blaster $i (sport ${B_SPORT[$i]}) did not finish"
done
sleep 1
while pgrep -x k4reins >/dev/null; do sleep 1; done

# --- collect: blaster walls + sent; receiver counters
maxwall=0; fails=0
: > "$OUT/blasters.txt"
for i in $(seq 0 $((NB - 1))); do
	tx="10.10.1.${B_SIP[$i]}"; s=${B_SPORT[$i]}
	line=$(ssh -o ConnectTimeout=10 davidlin@$tx "sudo cat /tmp/k5b-$s.log" 2>/dev/null)
	echo "$line" >> "$OUT/blasters.txt"
	wall=$(sed -n 's/.*wall=\([0-9.]*\)s.*/\1/p' <<< "$line")
	case ${wall:-0} in ''|*[!0-9.]*) wall=0;; esac
	[ -z "$line" ] && { echo "GATE FAIL: empty blaster log sport=$s"; fails=$((fails+1)); continue; }
	awk -v w="$wall" -v s="$SECS" 'BEGIN{exit !(w < s * 0.9)}' && {
		echo "GATE FAIL: blaster sport=$s wall=${wall}s < $SECS (budget too small or blaster slow)"
		fails=$((fails + 1))
	}
	awk -v w="$wall" -v m="$maxwall" 'BEGIN{exit !(w > m)}' && maxwall=$wall
done
echo "max blaster wall: $maxwall s"
cons=$(awk '/\[gate\] port=/ {split($3,a,"="); s+=a[2]} END{print s+0}' "$OUT/k4reins.log")
grep -qE "GATEFAIL|FAIL" "$OUT/k4reins.log" && { echo "GATE FAIL: receiver gate line"; fails=$((fails+1)); }
if [ "$maxwall" = 0 ] || [ "$fails" -gt 0 ]; then
	echo "K5CAP CELL: FAIL -> $OUT"; exit 2
fi
awk -v c="$cons" -v w="$maxwall" 'BEGIN{printf "CAPACITY (%s ports/core, cpus %s): consumed=%d rate=%.0f pps over %.2fs\n", "'"$NPC"'", "'"$CPUS"'", c, c/w, w}'
echo "K5CAP CELL: PASS -> $OUT"
echo "---- receiver:"; grep -E "\[gate\]|\[k4reins\] (port|grp)" "$OUT/k4reins.log"
echo "---- blasters:"; cat "$OUT/blasters.txt"