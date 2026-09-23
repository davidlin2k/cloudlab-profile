#!/bin/bash
# k5cap.sh -- capacity: saturated drain rate per core (K5CAP), via a
# load staircase. Blasting far past the knee lands in the overload
# collapse (measured: 1 port, 1M pps offered -> 2.1k pps consumed), so
# capacity is the PLATEAU top of consumed-vs-offered, not the rate at
# max demand. Points: offered rates below; per point a fresh receiver
# and paced k5blast blasters (NB per port, each rate/NB). The receiver
# is the limiter at saturation: blasters are killed after it exits and
# their offered rate is read from the last status line. Capacity =
# max(consumed / (rolls x 0.1s)) over points; the knee is the offered
# rate at the plateau top. Usage (root on rx):
#   k5cap.sh <ports_per_core> <cpu_list> <secs_per_point> <rep> [plen]
# cpu list entries must be the softirq homes of RSS queues 0..n-1
# (after pin_irqs.sh comp_j -> cpu j+1: "1" = queue 0, "1,2" = 0,1).
set -u
NPC=${1:?ports per core}; CPUS=${2:?cpu list like 1 or 1,2}
SECS=${3:-8}; REP=${4:-1}; PLEN=${5:-300}
NBLAST=3
RATES="150000 300000 450000 600000 900000 1200000"
IFACE=enp195s0np0
OUT=/root/k5/cap-${NPC}p-${CPUS//,/-}-r${REP}-$(date +%H%M%S)
mkdir -p "$OUT"
comb=$(ethtool -l $IFACE | awk '/Combined/{c=$2} END{print c}')
[ "$comb" = "32" ] || { echo "GATE FAIL: Combined=$comb"; exit 2; }

# --- ports: group g uses queue g; one authored (sip,sport) per port
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
NB=${#B_DP[@]}
echo "blasters: $NB"

TXS="10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13 10.10.1.14"
: > "$OUT/summary.txt"
best=0; best_rate=0
for RATE in $RATES; do
	PT="$OUT/pt-$RATE"; mkdir -p "$PT"
	pkill -x k5blast 2>/dev/null; pkill -x k4reins 2>/dev/null; sleep 0.5
	for tx in $TXS; do ssh -o ConnectTimeout=10 davidlin@$tx \
		'sudo pkill -x k5blast' 2>/dev/null; done

	PJ=$(IFS=,; echo "${DPORTS[*]}")
	nohup /root/k2/k4reins --secs $((SECS + 6)) --knee 3000000 \
		--cores "$CPUS" --ports "$PJ" > "$PT/k4reins.log" 2>&1 &
	sleep 1
	pgrep -x k4reins >/dev/null || { echo "GATE FAIL: k4reins not running"; exit 2; }

	each=$((RATE / NB))
	for i in $(seq 0 $((NB - 1))); do
		tx="10.10.1.${B_SIP[$i]}"; s=${B_SPORT[$i]}; dp=${B_DP[$i]}
		ssh -o ConnectTimeout=10 davidlin@$tx \
		  "sudo rm -f /tmp/k5b-$s.log; \
		   sudo nohup bash -c 'sleep 1; /root/k2/k5blast --dip 10.10.1.1 \
		     --sip ${B_SIP[$i]} --sport $s --dport $dp \
		     --n $((each * (SECS + 4))) --rate $each --plen $PLEN \
		     --batch 64 > /tmp/k5b-$s.log 2>&1; touch /tmp/k5b-$s.done' \
		     >/dev/null 2>&1 &"
	done
	# receiver is the clock: wait for it to exit, then reap blasters
	gone=0
	for t in $(seq 1 $((SECS + 12))); do
		pgrep -x k4reins >/dev/null || { gone=1; break; }
		sleep 1
	done
	[ $gone -eq 1 ] || { echo "GATE FAIL: receiver did not exit"; exit 2; }
	sleep 2
	for tx in $TXS; do ssh -o ConnectTimeout=10 davidlin@$tx \
		'sudo pkill -x k5blast' 2>/dev/null; done

	# collect
	: > "$PT/blasters.txt"
	offered=0
	for i in $(seq 0 $((NB - 1))); do
		tx="10.10.1.${B_SIP[$i]}"; s=${B_SPORT[$i]}
		line=$(ssh -o ConnectTimeout=10 davidlin@$tx \
			"sudo tail -1 /tmp/k5b-$s.log" 2>/dev/null)
		echo "$line" >> "$PT/blasters.txt"
		sv=$(sed -n 's/.*sent=\([0-9]*\).*/\1/p' <<< "$line")
		case ${sv:-0} in ''|*[!0-9]*) sv=0;; esac
		offered=$((offered + sv))
	done
	cons=$(awk '/\[gate\] port=/ {split($3,a,"="); s+=a[2]} END{print s+0}' \
		"$PT/k4reins.log")
	rolls=$(awk '/\[gate\] rolls=/ {split($3,a,"="); print a[2]+0}' \
		"$PT/k4reins.log")
	if grep -qE "GATEFAIL" "$PT/k4reins.log" || [ "$rolls" -lt 5 ]; then
		echo "POINT rate=$RATE INVALID (receiver gate failure)" \
			| tee -a "$OUT/summary.txt"
		continue
	fi
	win=$(awk -v r="$rolls" 'BEGIN{print r * 0.1}')
	cr=$(awk -v c="$cons" -v w="$win" 'BEGIN{printf "%.0f", c / w}')
	od=$(awk -v o="$offered" -v w="$win" 'BEGIN{printf "%.0f", o / w}')
	ok="OK"
	awk -v o="$od" -v r="$RATE" 'BEGIN{exit !(o < r * 0.8)}' && ok="UNDER-DEMAND"
	echo "POINT rate=$RATE window=${win}s consumed=$cons consumed_rate=$cr offered_rate=$od $ok" \
		| tee -a "$OUT/summary.txt"
	if [ "$ok" = "OK" ] || [ "$ok" = "UNDER-DEMAND" ]; then
		better=$(awk -v a="$cr" -v b="$best" 'BEGIN{print (a > b) ? 1 : 0}')
		if [ "$better" = 1 ]; then best=$cr; best_rate=$RATE; fi
	fi
done
pkill -x k4reins 2>/dev/null
if [ "$best" -gt 0 ]; then
	echo "CAPACITY ($NPC ports/core, cpus $CPUS, rep $REP): $best pps; knee at offered $best_rate pps" \
		| tee -a "$OUT/summary.txt"
	echo "K5CAP CELL: PASS -> $OUT"
else
	echo "K5CAP CELL: FAIL (no valid point) -> $OUT"
fi
cat "$OUT/summary.txt"