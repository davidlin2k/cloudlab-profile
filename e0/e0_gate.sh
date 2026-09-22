#!/bin/bash
#
# e0_gate.sh - E0 actuation gate for Reins (mechanism K1).
#
# Question this answers: on a ConnectX-6 (mlx5) pair, does a chosen source
# port deterministically select a chosen RX queue?  If yes, the receiver can
# steer each message to a core by assigning the sender's ephemeral port -
# the actuation primitive all of Reins builds on.
#
# How: on the RECEIVER, dump the live Toeplitz key + RSS indirection table
# (`ethtool -x`), predict each (sip, dip, sport, dport) queue with
# toeplitz.py, make the SENDER emit N packets with that tuple (sportgen over
# ssh), and compare per-queue ethtool counter deltas.  Sweeps ~64 source
# ports x 2 destination ports under three hash-class probes:
#   udp   4-tuple hashing (expected: PASS)
#   tcp   TCP-shaped frames for HomaModule hijack mode (expected: PASS)
#   146   IP protocol 146 = Homa native (expected: FAIL - L3-only hashing)
# Pass: >= 97% of a trial's packets land on the predicted queue.
#
# Output: $OUT/e0_result.json {proto: {pass, mean_hit_frac, n_trials, ...}}
# plus a human verdict table and raw artifacts (ethtool dumps, trials CSV,
# per-trial counter snapshots).  Exit 0 only if tcp AND udp pass; the
# proto-146 result is informational.
#
# Usage (receiver node; sender = sender's experiment IP):
#   sudo ./e0_gate.sh --sender 10.10.1.11
#   sudo ./e0_gate.sh --sender 10.10.1.11 --iface eno1 --n-sports 64 --pkts 20000
#   sudo ./e0_gate.sh --veth                 # single-node plumbing smoke test
# The kit must exist at the same path on the sender (scp -r e0/ tx:), or pass
# --remote-kit.  Root is needed only for `ethtool -x` (CAP_NET_ADMIN) and raw
# sockets on the sender; without root the script falls back to `sudo -n`.
# Run time at defaults: ~384 trials, roughly 5-10 minutes.

set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")" && pwd)
TOEPLITZ="$KIT_DIR/toeplitz.py"

usage() {
	sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

# Queue predicted for a tuple under a named calibration mode.  The mode
# selects one of the Q_* arrays filled from predictions.txt.
queue_of() { # mode sport dport
	local -n ref="Q_$(echo "$1" | tr 'a-z' 'A-Z')"
	echo "${ref[$2:$3]}"
}

die() { echo "e0_gate: $*" >&2; exit 1; }
log() { echo "e0_gate: $*"; }

SENDER="" SSH_USER="root" REMOTE_KIT="" IFACE="" OUT=""
NSPORTS=64 NPKTS=20000 THRESH=0.97
DPORTS="4240 4421"
VETH=0 PLAN_ONLY=0 STEER_CORE="" NTUPLE=""
BATCH=200 PAUSE=400

while [ $# -gt 0 ]; do
	case "$1" in
	--sender) SENDER=$2; shift 2;;
	--iface) IFACE=$2; shift 2;;
	--ssh-user) SSH_USER=$2; shift 2;;
	--remote-kit) REMOTE_KIT=$2; shift 2;;
	--out) OUT=$2; shift 2;;
	--n-sports) NSPORTS=$2; shift 2;;
	--pkts) NPKTS=$2; shift 2;;
	--thresh) THRESH=$2; shift 2;;
	--dports) DPORTS=$(echo "$2" | tr ',' ' '); shift 2;;
	--veth) VETH=1; shift;;
	--plan-only) PLAN_ONLY=1; shift;;
	--steer-core) STEER_CORE=$2; shift 2;;
	--set-ntuple) NTUPLE=$2; shift 2;;
	-h|--help) usage;;
	*) usage;;
	esac
done

SUDO=""
if [ "$(id -u)" != 0 ]; then
	SUDO="sudo -n"
	$SUDO true 2>/dev/null || SUDO="sudo"
fi

MODES="fwd fwd_xor fwd_swap rev rev_xor rev_swap"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OUT=${OUT:-$KIT_DIR/e0_last_run}
rm -rf "$OUT"
mkdir -p "$OUT"
TRIALS="$OUT/trials.csv"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPath=/tmp/e0-ssh-$$ -o ControlPersist=300"
echo "proto,dport,sport,pred,total,frac_pred,frac_max,maxq,low,pass" > "$TRIALS"

# ---------------------------------------------------------------------------
# --veth: single-node smoke test.  veth does no RSS, so this validates only
# the plumbing: sportgen packet shapes, counter movement, toeplitz selftest.
# ---------------------------------------------------------------------------
if [ "$VETH" = 1 ]; then
	[ "$(id -u)" = 0 ] || die "--veth needs root (netns + raw sockets)"
	cleanup_veth() { ip netns del e0tx 2>/dev/null || true; ip netns del e0rx 2>/dev/null || true; }
	trap cleanup_veth EXIT
	cleanup_veth
	ip netns add e0tx
	ip netns add e0rx
	ip link add e0v0 type veth peer name e0v1
	ip link set e0v0 netns e0tx
	ip link set e0v1 netns e0rx
	ip -n e0tx addr add 10.203.0.1/24 dev e0v0
	ip -n e0rx addr add 10.203.0.2/24 dev e0v1
	ip -n e0tx link set e0v0 up
	ip -n e0rx link set e0v1 up
	ip -n e0tx link set lo up
	ip -n e0rx link set lo up
	log "veth smoke test: sending 200 packets per proto from e0tx to e0rx"
	smoke_ok=1
	for proto in udp tcp 146; do
		before=$(ip netns exec e0rx cat /sys/class/net/e0v1/statistics/rx_packets)
		ip netns exec e0tx "$KIT_DIR/sportgen" --dip 10.203.0.2 --dport 4240 \
			--sport 40001 --n 200 --proto "$proto" --batch 64 --pause 200 >/dev/null
		sleep 0.3
		after=$(ip netns exec e0rx cat /sys/class/net/e0v1/statistics/rx_packets)
		delta=$((after - before))
		if [ "$delta" -ge 190 ]; then
			log "  proto $proto: $delta/200 arrived: OK"
		else
			log "  proto $proto: only $delta/200 arrived: FAIL"
			smoke_ok=0
		fi
	done
	if python3 "$TOEPLITZ" --selftest > "$OUT/selftest.txt" 2>&1; then
		log "  toeplitz selftest: OK"
	else
		log "  toeplitz selftest: FAIL (see $OUT/selftest.txt)"
		smoke_ok=0
	fi
	printf '{\n  "mode": "veth_smoke",\n  "plumbing_pass": %s,\n  "date": "%s"\n}\n' \
		"$([ "$smoke_ok" = 1 ] && echo true || echo false)" "$TS" \
		> "$OUT/e0_result.json"
	log "veth smoke test: $([ "$smoke_ok" = 1 ] && echo PASS || echo FAIL) (note: veth does no RSS; this validates plumbing only)"
	if [ "$smoke_ok" = 1 ]; then
		exit 0
	fi
	exit 1
fi

# ---------------------------------------------------------------------------
# Real NIC mode: two nodes.
# ---------------------------------------------------------------------------
[ -n "$SENDER" ] || die "need --sender IP (or --veth for the smoke test)"
[ -f "$TOEPLITZ" ] || die "toeplitz.py not found next to e0_gate.sh"
[ -f "$KIT_DIR/sportgen.c" ] || die "sportgen.c not found next to e0_gate.sh"
command -v ethtool >/dev/null || die "ethtool not installed"
command -v python3 >/dev/null || die "python3 not installed"
REMOTE_KIT=${REMOTE_KIT:-$KIT_DIR}

# (a) record the NIC: interface, channels, key+indir, cpu count.
if [ -z "$IFACE" ]; then
	IFACE=$(ip -o route get "$SENDER" 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
fi
[ -n "$IFACE" ] || die "cannot find the interface routing to $SENDER; pass --iface"
RX_IP=$(ip -4 -o addr show dev "$IFACE" | awk '{split($4, a, "/"); print a[1]; exit}')
[ -n "$RX_IP" ] || die "no IPv4 address on $IFACE"

log "iface $IFACE rx_ip $RX_IP sender $SENDER"
hostname > "$OUT/hostname"
uname -r > "$OUT/kernel"
nproc > "$OUT/nproc"
$SUDO ethtool -i "$IFACE" > "$OUT/ethtool_i.txt" 2>&1 || true
$SUDO ethtool -l "$IFACE" > "$OUT/ethtool_l.txt" 2>&1 || true
$SUDO ethtool -k "$IFACE" > "$OUT/ethtool_k.txt" 2>&1 || true
CHANNELS=$(awk '/^[[:space:]]*(Combined|RX|TX):/ {print $2}' "$OUT/ethtool_l.txt" 2>/dev/null | tail -1)
CHANNELS=${CHANNELS:-?}
NTUPLE_STATE=$(grep -w ntuple "$OUT/ethtool_k.txt" 2>/dev/null | head -1 | awk '{print $2}')
NTUPLE_STATE=${NTUPLE_STATE:-unknown}
log "channels $CHANNELS nproc $(cat "$OUT/nproc") ntuple $NTUPLE_STATE"
if [ -n "$NTUPLE" ]; then
	log "setting ntuple $NTUPLE (requested)"
	$SUDO ethtool -K "$IFACE" ntuple "$NTUPLE" || die "ethtool -K ntuple $NTUPLE failed"
	NTUPLE_STATE=$(ethtool -k "$IFACE" | grep -w ntuple | head -1 | awk '{print $2}')
fi

$SUDO ethtool -x "$IFACE" > "$OUT/ethtool_x.txt" 2>&1 \
	|| die "ethtool -x $IFACE failed (needs root/CAP_NET_ADMIN); try: sudo $0 $*"
grep -qiE "hash key|key \*" "$OUT/ethtool_x.txt" \
	|| die "no RSS hash key in ethtool -x dump (see $OUT/ethtool_x.txt)"
if grep -qi "toeplitz: off" "$OUT/ethtool_x.txt"; then
	die "ethtool -x reports toeplitz: off; predictions impossible"
fi

# Newer mlx5e defaults to symmetric hashing (kernels > ~6.12); try to turn it
# off so the plain 4-tuple prediction applies.  Tolerated failure: the
# calibration below resolves the transform empirically instead.
if $SUDO ethtool -X "$IFACE" symmetric off > "$OUT/symmetric_off.txt" 2>&1; then
	log "symmetric hash disabled (ethtool -X symmetric off)"
	$SUDO ethtool -x "$IFACE" > "$OUT/ethtool_x.txt" 2>&1 || true
else
	log "note: could not toggle symmetric hash via ethtool -X (may be unsupported); calibrating empirically"
fi

# (b) sport sweep + predictions from the dumped key+indir (one python call).
[ "$NSPORTS" -ge 3 ] || die "--n-sports must be >= 3 (calibration needs 3 trials)"
mapfile -t SPORTS < <(awk -v n="$NSPORTS" 'BEGIN { for (i = 0; i < n; i++) printf "%d\n", 30001 + (i * 541) % 29000 }')
: > "$OUT/tuples.txt"
for dport in $DPORTS; do
	for sport in "${SPORTS[@]}"; do
		echo "$SENDER $sport $dport" >> "$OUT/tuples.txt"
	done
done
python3 "$TOEPLITZ" --ethtool "$OUT/ethtool_x.txt" --all-modes \
	--dip "$RX_IP" --tuple-file "$OUT/tuples.txt" > "$OUT/predictions.txt" \
	|| die "toeplitz.py prediction failed (bad key/indir dump?)"
INDIR_SIZE=$(sed -n 's/^# indir_size \([0-9]*\) .*/\1/p' "$OUT/predictions.txt" | head -1)
INDIR_SIZE=${INDIR_SIZE:-?}
log "indir_size $INDIR_SIZE sports ${#SPORTS[@]} dports $(echo $DPORTS | wc -w)"

declare -A Q_FWD Q_FWD_XOR Q_FWD_SWAP Q_REV Q_REV_XOR Q_REV_SWAP
while read -r sport dport qf qfx qfs qr qrx qrs; do
	case "$sport" in ''|\#*) continue;; esac
	Q_FWD[$sport:$dport]=$qf
	Q_FWD_XOR[$sport:$dport]=$qfx
	Q_FWD_SWAP[$sport:$dport]=$qfs
	Q_REV[$sport:$dport]=$qr
	Q_REV_XOR[$sport:$dport]=$qrx
	Q_REV_SWAP[$sport:$dport]=$qrs
done < "$OUT/predictions.txt"

# ssh plumbing: probe, make sure sportgen exists remotely (build if needed).
ssh $SSH_OPTS "$SSH_USER@$SENDER" true 2>/dev/null \
	|| die "ssh $SSH_USER@$SENDER failed.  CloudLab nodes share keys; check 'ssh $SENDER true'.  Kit must also be at $REMOTE_KIT on the sender (scp -r e0/)."
if ! ssh $SSH_OPTS "$SSH_USER@$SENDER" "test -x $REMOTE_KIT/sportgen" 2>/dev/null; then
	log "sportgen not found at $REMOTE_KIT on sender; building it there"
	ssh $SSH_OPTS "$SSH_USER@$SENDER" "cd $REMOTE_KIT && gcc -Wall -O2 -o sportgen sportgen.c" \
		|| die "cannot build sportgen on sender; scp the kit: scp -r $KIT_DIR $SSH_USER@$SENDER:$REMOTE_KIT"
fi

# Sender plan, for the record (reproducible manual fallback).
{
	echo "#!/bin/bash"
	echo "# Run on $SENDER if you must drive the sends by hand (gate normally"
	echo "# does this over ssh):"
	for dport in $DPORTS; do
		for sport in "${SPORTS[@]}"; do
			for proto in udp tcp 146; do
				echo "$REMOTE_KIT/sportgen --dip $RX_IP --dport $dport --sport $sport --n $NPKTS --proto $proto --batch $BATCH --pause $PAUSE"
			done
		done
	done
} > "$OUT/sender_plan.sh"
chmod +x "$OUT/sender_plan.sh"

if [ "$PLAN_ONLY" = 1 ]; then
	log "plan written to $OUT (sender_plan.sh, predictions.txt); nothing sent"
	exit 0
fi

# ---------------------------------------------------------------------------
# Counter snapshots and per-trial measurement.
# ---------------------------------------------------------------------------
snap_queues() {
	$SUDO ethtool -S "$IFACE" 2>/dev/null | awk -F: '
	{
		k = $1
		gsub(/[[:space:]]/, "", k)
		if (k ~ /^rx_?[0-9]+_packets$/) {
			sub(/^rx_?/, "", k)
			sub(/_packets$/, "", k)
			v = $2
			gsub(/[[:space:]]/, "", v)
			printf "%s %s\n", k, v + 0
		}
	}'
}

# Per-trial deltas: prints "total frac_pred frac_max maxq" (before after pred).
trial_stats() {
	awk -v pred="$3" '
		NR == FNR { b[$1] = $2; next }
		{ a[$1] = $2 }
		END {
			total = 0; pd = 0; mv = 0; mq = ""
			for (q in a) {
				d = a[q] - ((q in b) ? b[q] : 0)
				if (d > 0) {
					total += d
					if (q == pred) pd = d
					if (mq == "" || d > mv) { mq = q; mv = d }
				}
			}
			printf "%d %.6f %.6f %s\n", total, \
				(total > 0 ? pd / total : 0), \
				(total > 0 ? mv / total : 0), mq
		}' "$1" "$2"
}

remote_send() { # proto dport sport
	ssh $SSH_OPTS "$SSH_USER@$SENDER" \
		"$REMOTE_KIT/sportgen --dip $RX_IP --dport $2 --sport $3 --n $NPKTS --proto $1 --batch $BATCH --pause $PAUSE" >/dev/null
}

record_trial() { # proto dport sport pred before_file after_file
	local stats total fp fm mq low pass
	stats=$(trial_stats "$5" "$6" "$4")
	read -r total fp fm mq <<<"$stats"
	low=0
	if [ "$total" -lt $((NPKTS * 6 / 10)) ]; then
		low=1
	fi
	pass=0
	if [ "$low" = 0 ] && [ "$4" != "-1" ] \
		&& awk -v f="$fp" -v t="$THRESH" 'BEGIN { exit !(f >= t) }'; then
		pass=1
	fi
	printf '%s,%s,%s,%s,%d,%.4f,%.4f,%s,%d,%d\n' \
		"$1" "$2" "$3" "$4" "$total" "$fp" "$fm" "$mq" "$low" "$pass" >> "$TRIALS"
	[ "$low" = 0 ] || log "  warn: trial $1/$3/$2 moved only $total counters (<60% of $NPKTS); excluded"
}

# Calibration: 3 udp trials decide the prediction mode (key byte order and
# canonicalization).  A wrong mode scatters ~1/channels; the right one hits
# >=97% on every trial, so the choice is unambiguous.
log "calibrating prediction mode (3 udp trials)..."
CAL_DONE=""
CAL_MODE=""
for sport in "${SPORTS[0]}" "${SPORTS[1]}" "${SPORTS[2]}"; do
	dport=${DPORTS%% *}
	snap_queues > "$OUT/cal_before.$$"
	remote_send udp "$dport" "$sport"
	sleep 0.4
	snap_queues > "$OUT/cal_after.$$"
	awk -v pred="-1" 'NR==FNR { b[$1]=$2; next } { a[$1]=$2 } END { for (q in a) { d = a[q] - ((q in b) ? b[q] : 0); if (d > 0) print q, d } }' \
		"$OUT/cal_before.$$" "$OUT/cal_after.$$" > "$OUT/cal_$sport.delta"
	CAL_DONE="$CAL_DONE $sport"
	rm -f "$OUT/cal_before.$$" "$OUT/cal_after.$$"
done
best_mean=0
for mode in $MODES; do
	sum=0
	n=0
	for sport in $CAL_DONE; do
		pred=$(queue_of "$mode" "$sport" "$dport")
		frac=$(awk -v pred="$pred" '{ t += $2; if ($1 == pred) p += $2 } END { print (t > 0 ? p / t : 0) }' "$OUT/cal_$sport.delta")
		sum=$(awk -v a="$sum" -v b="$frac" 'BEGIN { print a + b }')
		n=$((n + 1))
	done
	mean=$(awk -v s="$sum" -v n="$n" 'BEGIN { print (n ? s / n : 0) }')
	log "  mode $mode: mean hit frac $mean"
	if awk -v m="$mean" -v b="$best_mean" 'BEGIN { exit !(m > b) }'; then
		best_mean=$mean
		CAL_MODE=$mode
	fi
done
if awk -v m="$best_mean" -v t="$THRESH" 'BEGIN { exit !(m >= t) }'; then
	log "prediction mode: $CAL_MODE (mean $best_mean over calibration trials)"
else
	log "WARNING: no prediction mode reached $THRESH (best $CAL_MODE = $best_mean)"
	log "  the NIC is not following the dumped key+indir: check ntuple rules, aRFS,"
	log "  or a driver that transforms the key.  Sweeping anyway for the record."
	CAL_MODE="none"
fi

# (c) the sweep: 3 protos x 2 dports x NSPORTS trials.
n_trials=0
for proto in udp tcp 146; do
	for dport in $DPORTS; do
		for sport in "${SPORTS[@]}"; do
			if [ "$CAL_MODE" = "none" ]; then
				pred=-1
			else
				pred=$(queue_of "$CAL_MODE" "$sport" "$dport")
			fi
			snap_queues > "$OUT/before.$$"
			remote_send "$proto" "$dport" "$sport"
			sleep 0.4
			snap_queues > "$OUT/after.$$"
			record_trial "$proto" "$dport" "$sport" "$pred" "$OUT/before.$$" "$OUT/after.$$"
			rm -f "$OUT/before.$$" "$OUT/after.$$"
			n_trials=$((n_trials + 1))
		done
	done
	log "  $proto done ($n_trials trials so far)"
done

# (d) optional, informational: pin the NIC queues' IRQs to one core.
# mlx5 interrupt labels carry the PCI address, not the interface name.
PCI_ADDR=$(basename "$(readlink -f "/sys/class/net/$IFACE/device" 2>/dev/null)" 2>/dev/null || true)
IRQS=$(grep -iE "mlx5.*${PCI_ADDR:-nomatch}" /proc/interrupts 2>/dev/null | awk '{print $1}' | tr -d ':' || true)
if [ -n "$STEER_CORE" ]; then
	log "steering ${IRQS##* } queue IRQs to core $STEER_CORE (informational)"
	for irq in $IRQS; do
		before=$(cat "/proc/irq/$irq/effective_affinity_list" 2>/dev/null || echo "?")
		$SUDO sh -c "echo $STEER_CORE > /proc/irq/$irq/smp_affinity_list" 2>/dev/null || true
		after=$(cat "/proc/irq/$irq/effective_affinity_list" 2>/dev/null || echo "?")
		log "  irq $irq: affinity $before -> $after"
	done
else
	echo "$IRQS" > "$OUT/nic_irqs.txt"
fi

# ---------------------------------------------------------------------------
# Verdicts, JSON, human summary.
# ---------------------------------------------------------------------------
proto_stats() { # proto -> "n mean npass npinned nlow"
	awk -F, -v p="$1" -v th="$THRESH" '
		$1 == p && $9 == 0 {
			n++; sum += $6; if ($6 >= th) np++; if ($7 >= th) npin++
		}
		END {
			if (n) printf "%d %.4f %d %d\n", n, sum / n, np + 0, npin + 0
			else printf "0 0 0 0\n"
		}' "$TRIALS"
}

verdict_json() { # proto -> JSON object text
	local stats n mean npass npin pass
	stats=$(proto_stats "$1")
	read -r n mean npass npin <<<"$stats"
	pass=false
	if [ "$n" -gt 0 ] && [ "$npass" -ge $((n * 9 / 10)) ] \
		&& awk -v m="$mean" -v t="$THRESH" 'BEGIN { exit !(m >= t) }'; then
		pass=true
	fi
	printf '{"pass": %s, "mean_hit_frac": %s, "n_trials": %d, "n_pass": %d}' \
		"$pass" "$mean" "$n" "$npass"
}

UDP_JSON=$(verdict_json udp)
TCP_JSON=$(verdict_json tcp)
P146_JSON=$(verdict_json 146)
udp_pass=$(echo "$UDP_JSON" | grep -q '"pass": true' && echo 1 || echo 0)
tcp_pass=$(echo "$TCP_JSON" | grep -q '"pass": true' && echo 1 || echo 0)
p146_pass=$(echo "$P146_JSON" | grep -q '"pass": true' && echo 1 || echo 0)

if [ "$tcp_pass" = 1 ] && [ "$udp_pass" = 1 ] && [ "$p146_pass" = 0 ]; then
	VERDICT="hijack_gated"
elif [ "$tcp_pass" = 1 ] && [ "$udp_pass" = 1 ]; then
	VERDICT="unexpected_native_pass"
elif [ "$tcp_pass" = 1 ]; then
	VERDICT="udp_anomaly"
else
	VERDICT="k1_fires"
fi

cat > "$OUT/e0_result.json" <<EOF
{
  "kit": "e0_gate",
  "date": "$TS",
  "iface": "$IFACE",
  "rx_ip": "$RX_IP",
  "sender": "$SENDER",
  "kernel": "$(cat "$OUT/kernel")",
  "channels": "$CHANNELS",
  "nproc": $(cat "$OUT/nproc"),
  "indir_size": "$INDIR_SIZE",
  "hfunc": "toeplitz",
  "ntuple": "$NTUPLE_STATE",
  "predict_mode": "$CAL_MODE",
  "threshold": $THRESH,
  "protos": {
    "udp": $UDP_JSON,
    "tcp": $TCP_JSON,
    "146": $P146_JSON
  },
  "verdict": "$VERDICT"
}
EOF
cp "$OUT/e0_result.json" "$KIT_DIR/e0_result.json"

echo
echo "==================== E0 GATE VERDICT ===================="
printf '%-6s %-8s %-14s %-10s %s\n' proto trials mean_hit_frac pass note
for proto in udp tcp 146; do
	stats=$(proto_stats "$proto")
	read -r n mean npass npin <<<"$stats"
	note=""
	if [ "$proto" = 146 ] && [ "$n" -gt 0 ]; then
		if awk -v m="$npin" -v n2="$n" -v t="$THRESH" 'BEGIN { exit !((n2 > 0) && (m / n2 >= t)) }'; then
			note="traffic pinned to a fixed queue (L3-only hashing)"
		fi
	fi
	pass_str=no
	if [ "$n" -gt 0 ] && [ "$npass" -ge $((n * 9 / 10)) ] \
		&& awk -v m="$mean" -v t="$THRESH" 'BEGIN { exit !(m >= t) }'; then
		pass_str=yes
	fi
	printf '%-6s %-8s %-14s %-10s %s\n' "$proto" "$n" "$mean" "$pass_str" "$note"
done
echo "---------------------------------------------------------"
case "$VERDICT" in
hijack_gated)
	echo "PASS: sport -> queue is deterministic (4-tuple), proto 146 is not."
	echo "Reins is gated on hijack mode: ship Homa frames as TCP (homa_hijack.c)"
	echo "or change Homa's wire protocol; native proto-146 packets hash on L3."
	;;
unexpected_native_pass)
	echo "UNEXPECTED: proto-146 traffic followed the 4-tuple prediction."
	echo "Re-check the receiver's driver/firmware before trusting this."
	;;
udp_anomaly)
	echo "PARTIAL: TCP-shaped 4-tuple hashing works but UDP does not."
	echo "Check ethtool -k rx-gro/rx-udp offloads and fragmentation settings."
	;;
k1_fires)
	echo "FAIL: no 4-tuple port -> queue determinism (K1 fires)."
	echo "Inspect $OUT: key_order/prediction mode calibration, ntuple rules,"
	echo "and per-trial scatter in trials.csv before concluding."
	;;
esac
echo "artifacts: $OUT (e0_result.json also copied to $KIT_DIR/e0_result.json)"
echo "========================================================="

[ "$tcp_pass" = 1 ] && [ "$udp_pass" = 1 ]
