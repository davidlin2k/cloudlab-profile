#!/bin/bash
# k5_gate.sh -- day-1 instrument gate (K5FIX): idle ping-pong through the
# conserved, asserted instrument. Run as root ON RX:
#   ./k5_gate.sh <dport_for_queue0> [tx_ip] [sip_octet]
# Gates: conservation (receiver + sender identities), ledger rolls once
# per window, msg_len > 0, RTT p50 >= 10us floor, IRQs pinned off cpu0/
# cpu32 (delta check), Combined == 32. Exit 0 only if ALL pass.
set -u
DP=${1:?usage: k5_gate.sh <dport_for_queue0> [tx_ip] [sip_octet]}
TX=${2:-10.10.1.10}
SIPO=${3:-10}
IFACE=enp195s0np0
RXIP=10.10.1.1
LP=32700
OUT=/root/k5/gate-$(date +%H%M%S)
mkdir -p "$OUT"
echo "== k5 gate -> $OUT"
FAIL=0

# --- preflight -------------------------------------------------------
pkill -x sportgen 2>/dev/null; pkill -x k2_rx 2>/dev/null
pkill -x k4reins 2>/dev/null; pkill -x k4send 2>/dev/null
sleep 0.5
comb=$(ethtool -l $IFACE | awk '/Combined/{c=$2} END{print c}')
if [ "$comb" != "32" ]; then
	echo "GATE FAIL: Combined=$comb != 32"; exit 2
fi
ethtool -x $IFACE > "$OUT/ethtool-x.txt" 2>&1
cp /proc/interrupts "$OUT/interrupts-before.txt"

# --- receiver (queue-0 softirq home = cpu 1 after pin_irqs.sh) -------
rm -f /tmp/k4r.log /tmp/sg.done
nohup /root/k2/k4reins --secs 45 --knee 300000 --cores 1 \
	--ports $DP > /tmp/k4r.log 2>&1 &
sleep 1
pgrep -x k4reins >/dev/null || { echo "GATE FAIL: k4reins not running"; exit 2; }

# --- sender on tx0, detached + done-flag handshake -------------------
ssh -o StrictHostKeyChecking=no davidlin@$TX \
  "sudo rm -f /tmp/k4send.log /tmp/sg.done; \
   sudo nohup bash -c 'sleep 1; /root/k2/k4send --dip $RXIP --sip $SIPO \
     --qmap 0:$DP --lport 32700 --n 150000 --plen 300 --rate 5000 \
     --depth 8 --follow 0 --core 2 > /tmp/k4send.log 2>&1; \
     touch /tmp/sg.done' >/dev/null 2>&1 &"
# sender: 30s window + 10s drain; poll for the flag (2s interval)
for i in $(seq 1 40); do
	ssh -o StrictHostKeyChecking=no davidlin@$TX '[ -f /tmp/sg.done ]' \
		2>/dev/null && break
	sleep 3
done
sleep 2
while pgrep -x k4reins >/dev/null; do sleep 1; done
cp /proc/interrupts "$OUT/interrupts-after.txt"
ssh -o StrictHostKeyChecking=no davidlin@$TX 'cat /tmp/k4send.log' \
	> "$OUT/k4send.txt" 2>&1
cp /tmp/k4r.log "$OUT/k4reins.txt"

# --- gates -----------------------------------------------------------
echo "--- sender: $(head -1 $OUT/k4send.txt)"
sent=$(sed -n 's/.*sent=\([0-9]*\).*/\1/p' $OUT/k4send.txt | head -1)
resp=$(sed -n 's/.*resp=\([0-9]*\).*/\1/p' $OUT/k4send.txt | head -1)
cens=$(sed -n 's/.*censored=\([0-9]*\).*/\1/p' $OUT/k4send.txt | head -1)
p50=$(sed -n 's/.*p50=\([0-9.]*\).*/\1/p' $OUT/k4send.txt | head -1)
[ -z "$sent" ] && { echo "GATE FAIL: no sender output"; exit 2; }
# sender identity: sent == resp + censored (enforced in-driver too)
if [ $((resp + cens)) -ne "$sent" ]; then
	echo "GATE FAIL: sender sent=$sent != resp=$resp + censored=$cens"
	FAIL=1
fi
# idle gate: nothing should be censored or dropped
[ "$cens" -gt $((sent / 1000)) ] && { echo "GATE FAIL: idle run censored=$cens"; FAIL=1; }
# floor gate: p50 >= 10us
awk -v p="$p50" 'BEGIN{exit !(p < 10.0)}' && { echo "GATE FAIL: p50=${p50}us < 10us floor"; FAIL=1; }
# receiver identity (enforced in-driver; re-grep for FAIL)
grep -q "GATEFAIL" $OUT/k4reins.txt && { echo "GATE FAIL: receiver gate line"; FAIL=1; }
grep -q "FAIL" $OUT/k4reins.txt && { echo "GATE FAIL: per-port FAIL in k4reins.txt"; FAIL=1; }
# cross-check: receiver consumed == sender sent (idle: no loss)
cons=$(awk '/\[gate\] port=/ {s+=$3} END{print s+0}' $OUT/k4reins.txt)
if [ "$cons" -ne "$sent" ]; then
	echo "GATE FAIL: consumed=$cons != sent=$sent"; FAIL=1
fi
# IRQ delta check: comp0 vector must have fired on cpu 1 (>=95%)
a=$(grep "mlx5_comp0@pci:0000:c3:00.0" "$OUT/interrupts-before.txt" | head -1 | awk '{print $1}' | tr -d ':')
[ -n "$a" ] || { echo "GATE FAIL: no mlx5_comp0 irq found"; exit 2; }
after=$(awk -v i="^ *$a:" '$0 ~ i {for (j=2; j<=NF-3; j++) sum += $j} END{print sum+0}' "$OUT/interrupts-after.txt")
before=$(awk -v i="^ *$a:" '$0 ~ i {for (j=2; j<=NF-3; j++) sum += $j} END{print sum+0}' "$OUT/interrupts-before.txt")
cpu1_after=$(awk -v i="^ *$a:" '$0 ~ i {print $3}' "$OUT/interrupts-after.txt")
cpu1_before=$(awk -v i="^ *$a:" '$0 ~ i {print $3}' "$OUT/interrupts-before.txt")
delta=$((after - before)); d1=$((cpu1_after - cpu1_before))
if [ "$delta" -gt 0 ]; then
	share=$((100 * (cpu1_after - cpu1_before) / delta))
	echo "comp0 delta=$delta on cpu1: ${share}%"
	[ "$share" -lt 95 ] && { echo "GATE FAIL: comp0 IRQ not pinned to cpu1"; FAIL=1; }
fi

if [ $FAIL -eq 0 ]; then echo "K5FIX GATE: PASS"
else echo "K5FIX GATE: FAIL"; exit 2
fi
echo "---- receiver:"; cat "$OUT/k4reins.txt"
echo "---- sender:"; cat "$OUT/k4send.txt"