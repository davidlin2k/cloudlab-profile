#!/bin/bash
# deploy.sh -- provision the CloudLab nodes. Run from cloudlab-profile/ on
# YOUR machine (needs root ssh access to the nodes).
#   usage: ./deploy.sh [--local-homa] <rx-ip> [<tx-ip>...]
#
# Default: HomaModule is CLONED on every node from
#   https://github.com/PlatformLab/HomaModule.git
# (upstream main; the deployed commit is recorded to /root/homa-commit).
# --local-homa: instead rsync the workstation tree, which carries the
# uncommitted rotating-grants patch (needed only for that experiment).
# flowlet-eval is private and always rsync'd to rx. Senders get the e0 kit.
set -euo pipefail
LOCAL_HOMA=0
if [ "${1:-}" = "--local-homa" ]; then LOCAL_HOMA=1; shift; fi
[ $# -ge 1 ] || { echo "usage: deploy.sh [--local-homa] <rx-ip> [<tx-ip>...]"; exit 1; }
RX=$1; shift
WS=/home/david/network-workspace
SSHOPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

for host in "$RX" "$@"; do
	echo "== deploying e0/k2 kit to $host"
	rsync -az --exclude '*.o' -e "ssh $SSHOPTS" \
		"$(dirname "$0")/e0" "root@$host:/root/"
	rsync -az -e "ssh $SSHOPTS" "$(dirname "$0")/k2" "root@$host:/root/"
done

echo "== HomaModule on all nodes"
for host in "$RX" "$@"; do
	if [ "$LOCAL_HOMA" = 1 ]; then
		echo "   rsync (local tree w/ rotating-grants patch) -> $host"
		rsync -az --exclude '*.o' --exclude '*.ko' --exclude '*.mod*' \
			-e "ssh $SSHOPTS" "$WS/HomaModule" "root@$host:/root/"
	else
		echo "   git clone upstream -> $host"
		ssh $SSHOPTS "root@$host" '
			if [ -d /root/HomaModule/.git ]; then
				git -C /root/HomaModule fetch --depth 1 origin &&
				git -C /root/HomaModule reset --hard origin/main
			else
				rm -rf /root/HomaModule &&
				git clone --depth 1 \
					https://github.com/PlatformLab/HomaModule.git /root/HomaModule
			fi
			git -C /root/HomaModule rev-parse HEAD > /root/homa-commit
			echo "   deployed: $(cat /root/homa-commit)"
		'
	fi
done

echo "== flowlet-eval (private) -> $RX"
rsync -az -e "ssh $SSHOPTS" "$WS/flowlet-eval" "root@$RX:/root/"

echo "== building"
for host in "$RX" "$@"; do
	ssh $SSHOPTS "root@$host" \
		'cd /root/e0 && gcc -Wall -O2 -o sportgen sportgen.c; \
		 cd /root/k2 2>/dev/null && gcc -Wall -O2 -o k2_rx k2_rx.c || true'
done

echo "== building homa.ko on all nodes (headers from setup.sh phase 1)"
for host in "$RX" "$@"; do
	echo "   make -> $host (kernel $(ssh $SSHOPTS root@$host 'uname -r'))"
	ssh $SSHOPTS "root@$host" '
		cd /root/HomaModule || exit 1
		if ! make >/root/homa-build.log 2>&1; then
			echo "   BUILD FAILED on $(hostname); last 20 lines:" >&2
			tail -20 /root/homa-build.log >&2
			exit 1
		fi
		ls -la homa.ko >> /root/homa-build.log
		echo "   homa.ko built: $(stat -c %y homa.ko | cut -d. -f1)"
	'
done
echo "deploy done. homa: $(ssh $SSHOPTS root@$RX 'cat /root/homa-commit 2>/dev/null || echo local-tree'), homa.ko built on all nodes (NOT loaded)."