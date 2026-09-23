#!/bin/bash
# /local/repository/setup.sh <rx|tx> <nsenders> <iommu_off>
#
# Runs at every boot (ExecuteService) and is safe to run by hand.
# Phase 1 (first boot only): packages + optional grub edit -> one reboot.
# Phase 2 (every boot): NIC queue layout, IRQ affinity, governor, topology
# dump. Only the receiver gets the full phase 2 -- senders are load
# generators and their exact core layout does not matter.
set -uo pipefail   # no -e: every step tolerates failure, we report at the end

ROLE=${1:-rx}
IOMMU_OFF=${3:-0}
MARKER=/root/.cloudlab-setup-phase
LOG=/root/setup.log
exec >>"$LOG" 2>&1
echo "=== setup.sh $(date -u +%FT%TZ) role=$ROLE iommu_off=$IOMMU_OFF ==="

PHASE=$(cat "$MARKER" 2>/dev/null || echo 0)

log_fail() { echo "SETUP-FAIL: $*" >> /root/setup-status; }
echo -n > /root/setup-status

# ---------------- phase 1: packages (first boot) ----------------
if [ "$PHASE" -lt 1 ]; then
	apt-get update -y
	DEBIAN_FRONTEND=noninteractive apt-get install -y \
		build-essential "linux-headers-$(uname -r)" \
		ethtool numactl sysstat git pciutils python3 \
		linux-tools-common "linux-tools-$(uname -r)" \
		bc jq rsync || log_fail "apt install"
	# irqbalance moves IRQs under us: placement experiments need them fixed.
	systemctl disable --now irqbalance 2>/dev/null || log_fail "irqbalance"
	if [ "$IOMMU_OFF" = 1 ]; then
		GRUB=/etc/default/grub
		if ! grep -q 'amd_iommu=off' "$GRUB" 2>/dev/null && \
		   ! grep -q 'intel_iommu=off' "$GRUB" 2>/dev/null; then
			ARG=intel_iommu=off
			grep -qi amd /proc/cpuinfo && ARG=amd_iommu=off
			sed -i "s/^\(GRUB_CMDLINE_LINUX_DEFAULT=\"\)\(.*\)\"/\1\2 $ARG\"/" "$GRUB"
			update-grub || log_fail "update-grub"
			echo 1 > "$MARKER"
			echo "rebooting for iommu change" >> /root/setup-status
			reboot
			exit 0
		fi
	fi
	echo 1 > "$MARKER"
fi

# ---------------- phase 2: per-boot tuning ----------------
# Governor -> performance on every CPU (best effort; amd_pstate may own it).
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
	echo performance > "$f" 2>/dev/null
done

# Topology record: CPU, physical core, L3 id. The L3 id IS the CCD id on
# Genoa -- this file is the ground truth for every placement experiment.
{
	echo "cpu core l3id"
	for c in /sys/devices/system/cpu/cpu[0-9]*; do
		n=${c##*cpu}
		core=$(cat "$c/topology/core_id" 2>/dev/null)
		l3=$(cat "$c/cache/index3/id" 2>/dev/null)
		echo "$n $core $l3"
	done
} > /root/topology.txt

if [ "$ROLE" = rx ]; then
	# UDP-consumer experiments need real socket buffers: the default
	# rmem_max (212992) clamps SO_RCVBUF to ~145 packets of headroom
	# at 1 Mpps and produces RcvbufErrors storms (see FINDINGS §GENOA).
	sysctl -w net.core.rmem_max=134217728 net.core.wmem_max=134217728 \
		>/dev/null 2>&1 || log_fail "rmem_max"
	# The experiment NIC: the one on 10.10.1.0/24 (eth-exp).
	IFACE=$(ip -o addr show to 10.10.1.0/24 | awk '{print $2}')
	[ -n "$IFACE" ] || { log_fail "no experiment iface"; IFACE=$(ip -o route get 10.10.1.1 | awk '{print $3}'); }
	# Physical cores only, one queue per physical core (32c -> 32 queues).
	NPROC_PHYS=$(grep -c ^processor /proc/cpuinfo)
	siblings=$(cat /sys/devices/system/cpu/cpu0/topology/thread_siblings_list)
	SMT=1; [ "${siblings#*,}" != "$siblings" ] && SMT=2
	NQ=$((NPROC_PHYS / SMT))
	ethtool -L "$IFACE" combined "$NQ" 2>/dev/null || log_fail "ethtool -L"
	# Spread mlx5 vector IRQs 1:1 across physical cores. After this, queue k's
	# NAPI runs on core k and its DDIO writes land in core k's L3 domain.
	i=0
	for irq in $(grep -E "mlx5.*\b${IFACE}" /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
		echo $i > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null
		i=$((i + 1)); [ $i -ge $NQ ] && i=0
	done
	{
		echo "iface=$IFACE queues=$NQ smt=$SMT"
		ethtool -i "$IFACE"; ethtool -l "$IFACE"
		ethtool -k "$IFACE" | head -40
	} > /root/nic-state.txt
	ethtool -x "$IFACE" > /root/rss-key.txt 2>/dev/null || log_fail "ethtool -x"
fi

echo "setup complete: role=$ROLE phase=2" >> /root/setup-status
echo "OK" >> /root/setup-status
exit 0
