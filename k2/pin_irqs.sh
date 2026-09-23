#!/bin/bash
# pin_irqs.sh -- day-1 instrument fix (K5FIX): move the mlx5 MSI-X
# vectors off cpu0/cpu32 (physical core 0 = housekeeping: RCU, timers,
# kworkers). Verified on this block: cpu0/thread_siblings_list = "0,32"
# (pairs are (N, N+32)), and the heavy mlx5_comp0 vector landed on cpu0.
#
# New queue==cpu table after re-pin (queue = RSS queue index):
#   comp_i -> cpu (i+1)   for i = 0..30    (queue0 -> cpu1 ... queue30 -> cpu31)
#   comp_31 -> cpu 33 (SMT sibling of core 1; core 0 stays clean)
#   mlx5_async/misc -> cpu 41
# Every physical core keeps at most one queue's softirq home; core 0 is
# fully reserved for kernel housekeeping. Re-dump `ethtool -x` and
# re-probe the port map after this (RSS key is NOT touched by affinity,
# but the queue==cpu tables above supersede all earlier ones).
#
# irqbalance is stopped/disabled: it re-spreads vectors and would decay
# the pinning silently.
# Usage (root, on rx): ./pin_irqs.sh [iface] [outdir]
set -u
IFACE=${1:-enp195s0np0}
OUT=${2:-/root/k5/irqpin-$(date +%H%M%S)}
mkdir -p "$OUT"

cp /proc/interrupts "$OUT/interrupts-before.txt"
systemctl stop irqbalance 2>/dev/null; systemctl disable irqbalance 2>/dev/null
pkill -x irqbalance 2>/dev/null
sleep 0.5

pin() { # irq cpu
	local mask; mask=$(printf "%x" $((1 << $2)))
	if ! echo "$mask" > "/proc/irq/$1/smp_affinity" 2>/dev/null; then
		echo "WARN: could not pin irq $1 -> cpu $2"
		return 1
	fi
	return 0
}

moved=0
while read -r ln; do
	irq=$(echo "$ln" | awk '{print $1}' | tr -d ':')
	name=$(echo "$ln" | awk '{print $NF}')
	cpu=""
	case "$name" in
	  mlx5_comp[0-9]*@*)
		n=${name#mlx5_comp}; n=${n%%@*}
		[ "$n" -eq 31 ] && cpu=33 || cpu=$((n + 1))
		;;
	  mlx5_async*@*|mlx5_ptp*@*) cpu=41 ;;
	  *) continue ;;
	esac
	if pin "$irq" "$cpu"; then
		echo "irq $irq ($name) -> cpu $cpu"
	else
		echo "FAIL irq $irq ($name) -> cpu $cpu"
	fi
done < <(grep -E "mlx5_(comp|async|ptp)" /proc/interrupts)

# per-CPU kernel-side spreaders (not per-vector): keep them off cpu0 too
cp /proc/interrupts "$OUT/interrupts-after.txt"
echo "pin_irqs done: log in $OUT (interrupts-before.txt / -after.txt)"