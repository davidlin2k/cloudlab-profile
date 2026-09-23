#!/bin/bash
# k2_ddio.sh -- the K2 DDIO-causality measurement (the program's decisive
# figure). Run as root ON THE RECEIVER.
#
#   usage: ./k2_ddio.sh <sender_control_host> <sender_exp_ip> [iface]
#
# <sender_control_host>: CloudLab control-net hostname — orchestration ssh
#   ONLY (never carries experiment traffic).
# <sender_exp_ip>: 10.10.1.x experiment address — sportgen --dip ONLY.
#
# Design: sportgen streams 1400B UDP at ~1 Mpps (one core can consume
# ~1.5 Mpps of this, so the consumer never queues) with a source port chosen
# so RSS lands it on a chosen queue; k2_rx consumes pinned to a chosen core
# and reports cycles/pkt + cache-misses/pkt. Five cells:
#
#   queue/core    consumer    what it isolates
#   Q(c0)         c0          full local (baseline)
#   Q(near)       c0          queue same CCD, other core  -> slice-locality
#   Q(far)        c0          queue other CCD             -> DDIO landing cost
#   Q(c0)         far         consumer crosses            -> post-DMA cost
#   Q(far)        far         full local on far CCD       -> symmetry control
#
# The (Q(far),c0 - Q(c0),c0) delta is what pre-DMA steering can move that
# post-DMA steering structurally cannot. Verdict thresholds are stated in
# the output; the JSON has the raw numbers.
set -euo pipefail

SENDER_HOST=${1:?usage: k2_ddio.sh <sender_control_host> <sender_exp_ip> [iface]
  <sender_host> = control-net hostname (orchestration ssh ONLY);
  <sender_ip>  = experiment-net IP (10.10.1.x, sportgen --dip ONLY).
  Per CloudLab policy the control network never carries experiment traffic,
  and orchestration never rides the experiment LAN.}
SENDER=${2:?missing sender experiment IP}
IFACE=${3:-$(ip -o addr show to 10.10.1.0/24 | awk '{print $2}')}
KIT=/local/repository/e0
HERE=$(cd "$(dirname "$0")" && pwd)
REMOTE_KIT=/root/e0
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
SSH_USER=davidlin   # CloudLab nodes share the user's keys; root has none
DPORT=7777
PPS=1000000            # ~1 Mpps of 1400B = ~17 Gbps: one core absorbs it
NPKTS=$((PPS * 15))    # 15 s per cell
BATCH=64
PAUSE=$((1000000 * BATCH / PPS))   # us between batches -> PPS
REPS=3

[ -x "$HERE/k2_rx" ] || (cd "$HERE" && gcc -Wall -O2 -o k2_rx k2_rx.c)

log() { echo "[k2] $*"; }
die() { echo "[k2] FATAL: $*" >&2; exit 1; }

# --- sender side: sportgen present? (deploy.sh usually put it there) ---
ssh $SSH_OPTS $SSH_USER@"$SENDER_HOST" "sudo test -x $REMOTE_KIT/sportgen" 2>/dev/null || {
	log "building sportgen on sender"
	ssh $SSH_OPTS $SSH_USER@"$SENDER_HOST" "sudo bash -c 'cd $REMOTE_KIT && gcc -Wall -O2 -o sportgen sportgen.c'" \
		|| die "no sportgen on sender: run deploy.sh first"
}

# --- topology: cpu -> l3id (setup.sh wrote it) ---
[ -f /root/topology.txt ] || die "/root/topology.txt missing: run setup.sh"
read -r _ _ L3_C0 < <(awk 'NR==2{print; exit}' /root/topology.txt)
C0=$(awk -v l3="$L3_C0" 'NR>1 && $3==l3 {print $1; exit}' /root/topology.txt)
CORE_C0=$(awk -v c="$C0" 'NR>1 && $1==c {print $2}' /root/topology.txt)
# near: same L3 domain, DIFFERENT physical core (an SMT sibling would be the
# same core and would not test slice-locality at all)
NEAR=$(awk -v l3="$L3_C0" -v core="$CORE_C0" \
	'NR>1 && $3==l3 && $2!=core {print $1; exit}' /root/topology.txt)
FAR=$(awk -v l3="$L3_C0" 'NR>1 && $3!=l3 {print $1; exit}' /root/topology.txt)
L3_FAR=$(awk -v c="$FAR" 'NR>1 && $1==c {print $3}' /root/topology.txt)
log "consumer c0=$C0 (l3 $L3_C0, core $CORE_C0)  near=$NEAR  far=$FAR (l3 $L3_FAR)"
[ -n "$NEAR" ] && [ -n "$FAR" ] || die "need 2 distinct L3 domains"

NQ=$(ethtool -l "$IFACE" 2>/dev/null | awk '/^Combined:/ {print $2}' | tail -1)
[ -n "$NQ" ] || die "ethtool -l failed on $IFACE"
log "iface=$IFACE combined queues=$NQ"

# --- per-queue counters (same parsing as e0_gate.sh's proven snap_queues) ---
snap_queues() {
	sudo ethtool -S "$IFACE" 2>/dev/null | awk -F: '
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
qget() { snap_queues | awk -v q="$1" '$1==q {print $2; exit}'; }

# --- empirical port discovery: find a sport whose stream lands >=97% on queue q ---
find_port() { # find_port <target_queue> -> prints sport
	local q=$1 sp tries=0
	for sp in $(seq 20000 7 20412); do
		local before after d hit
		before=$(qget "$q")
		ssh $SSH_OPTS $SSH_USER@"$SENDER_HOST" \
			"sudo $REMOTE_KIT/sportgen --dip 10.10.1.1 --dport $DPORT --sport $sp \
			 --n 50000 --proto udp --plen 1400 --batch $BATCH --pause $PAUSE" >/dev/null
		after=$(qget "$q")
		d=$((after - before))
		hit=$((d * 100 / 50000))
		if [ "$hit" -ge 97 ]; then echo "$sp"; return; fi
		echo "[k2]   probe $sp -> q$q hit=$hit%" >&2
		tries=$((tries + 1)); [ $tries -ge 60 ] && { echo ""; return; }
	done
	echo ""
}

PORT_OWN=$(find_port "$C0")
PORT_NEAR=$(find_port "$NEAR")
PORT_FAR=$(find_port "$FAR")
[ -n "$PORT_OWN" ] && [ -n "$PORT_NEAR" ] && [ -n "$PORT_FAR" ] \
	|| die "port discovery failed (is 4-tuple RSS on? run e0_gate.sh first)"
log "ports: own=$PORT_OWN near=$PORT_NEAR far=$PORT_FAR"

# --- the 5-cell matrix ---
run_cell() { # run_cell <name> <port> <consumer_core>
	local name=$1 port=$2 core=$3 rep out
	for rep in 1 2 3; do
		out=$("$HERE/k2_rx" --port $DPORT --core "$core" --secs 15 &
		      sleep 0.3
		      ssh $SSH_OPTS $SSH_USER@"$SENDER_HOST" \
			"sudo $REMOTE_KIT/sportgen --dip 10.10.1.1 --dport $DPORT --sport $port \
			 --n $NPKTS --proto udp --plen 1400 --batch $BATCH --pause $PAUSE" >/dev/null
		      wait)
		echo "$out" | sed "s/^k2rx /k2rx cell=$name /"
	done
}

{
	echo "=== K2 DDIO causality $(date -u +%FT%TZ) ==="
	run_cell own  "$PORT_OWN"  "$C0"
	run_cell near "$PORT_NEAR" "$C0"
	run_cell far  "$PORT_FAR"  "$C0"
	run_cell xcon "$PORT_OWN"  "$FAR"
	run_cell ctrl "$PORT_FAR"  "$FAR"
} 2>&1 | tee /root/k2_results.txt

# --- verdict: queue-side delta (pre-DMA steering's exclusive leverage) ---
python3 - <<'EOF'
import re, statistics, json
cells = {}
for line in open('/root/k2_results.txt'):
    m = re.search(r'cell=(\S+).*pkts=(\d+).*cyc/pkt=([\d.-]+) miss/pkt=([\d.-]+)', line)
    if m and int(m.group(2)) > 100000:
        cells.setdefault(m.group(1), []).append((float(m.group(3)), float(m.group(4))))
med = {k: (statistics.median(x[0] for x in v), statistics.median(x[1] for x in v))
       for k, v in cells.items()}
if 'own' in med and 'far' in med:
    dq = med['far'][0] - med['own'][0]      # queue-side: DDIO landing distance
    dqm = med['far'][1] - med['own'][1]
    dc = med['xcon'][0] - med['own'][0] if 'xcon' in med else None  # consumer-side
    verdict = "PRE-DMA WIN" if dq > 0.15 * med['own'][0] else "DDIO-FLOOR HOLDS"
    print(f"\n[k2] own={med['own'][0]:.1f}cyc/{med['own'][1]:.1f}m far={med['far'][0]:.1f}cyc/{med['far'][1]:.1f}m")
    if dc is not None:
        print(f"[k2] consumer-cross delta={dc:+.1f}cyc  queue-side delta={dq:+.1f}cyc ({dq/(med['own'][0])*100:+.0f}%)")
    print(f"[k2] VERDICT: {verdict} (queue-side pre-DMA delta {dq:+.1f} cyc/pkt, {dqm:+.1f} miss/pkt)")
    json.dump({k: {'cycc_per_pkt': v[0], 'miss_per_pkt': v[1]} for k, v in med.items()},
              open('/root/k2_result.json', 'w'), indent=1)
else:
    print("[k2] insufficient cells parsed; see /root/k2_results.txt")
EOF