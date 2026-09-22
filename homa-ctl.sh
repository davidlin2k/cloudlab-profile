#!/bin/bash
# homa-ctl.sh -- load / unload / inspect homa.ko across the fleet.
#   usage: homa-ctl.sh <rx-ip> [tx-ip...] load|unload|status
#
# Both ends speak the transport: the module must be loaded on the receiver
# AND every sender, or senders silently cannot originate Homa traffic.
# Idempotent; a failed insmod prints the dmesg tail.
set -uo pipefail

[ $# -ge 2 ] || { echo "usage: homa-ctl.sh <rx-ip> [tx-ip...] load|unload|status"; exit 1; }
ACTION=${!#}          # last arg = action
set -- "${@:1:$#-1}"   # remaining args = hosts
SSHOPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

for host in "$@"; do
	echo "== $ACTION homa @ $host"
	ssh $SSHOPTS "root@$host" '
		ACTION='"$ACTION"'
		KO=/root/HomaModule/homa.ko
		case "$ACTION" in
		load)
			if lsmod | grep -q "^homa "; then
				echo "   already loaded"
			else
				[ -f "$KO" ] || { echo "   no $KO -- run deploy.sh first"; exit 1; }
				if insmod "$KO"; then
					echo "   loaded: $(lsmod | grep "^homa ")"
				else
					echo "   INSMOD FAILED; dmesg tail:"
					dmesg | tail -8 | sed "s/^/     /"
					exit 1
				fi
			fi
			;;
		unload)
			if lsmod | grep -q "^homa "; then
				rmmod homa && echo "   unloaded" || {
					echo "   rmmod refused (sockets open? refcount?):"
					lsmod | grep "^homa " | sed "s/^/     /"
					exit 1
				}
			else
				echo "   not loaded"
			fi
			;;
		status)
			lsmod | grep "^homa " || echo "   not loaded"
			sysctl homa 2>/dev/null | sed "s/^/   /"
			;;
		*)
			echo "   bad action: $ACTION" >&2; exit 1;;
		esac
	' || echo "   (failed on $host)" >&2
done