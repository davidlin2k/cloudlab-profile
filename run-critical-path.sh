#!/bin/bash
# run-critical-path.sh -- the whole gated program on the live experiment,
# end to end. Run from cloudlab-profile/. Idempotent; every stage reports.
#
#   usage: ./run-critical-path.sh
#   (node addressing defaults to the davidlin-317389 experiment:
#    rx = clnode366.clemson.cloudlab.us, tx0..4 = clnode337/323/386/322/331)
#
# Stages:
#   0. reachability + boot setup verification (setup.sh ran at boot)
#   1. deploy.sh       -- kits to all nodes, HomaModule cloned+built, flowlet-eval to rx
#   2. E0 actuation gate (K1)      -- e0_result.json, verdict
#   3. K2 DDIO causality -- the decisive figure (k2_result.json)
# Each stage prints its verdict; the script stops on a K1 fire.
set -uo pipefail
U=${CLOUDLAB_USER:-davidlin}
RXH=${RXH:-clnode366.clemson.cloudlab.us}
TXS=${TXS:-"clnode337.clemson.cloudlab.us clnode323.clemson.cloudlab.us clnode386.clemson.cloudlab.us clnode322.clemson.cloudlab.us clnode331.clemson.cloudlab.us"}
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15"
SSHC() { $SSH davidlin@$RXH "sudo bash -c '$*'"; }

echo "=== stage 0: reachability + boot state ==="
$SSH davidlin@$RXH hostname || { echo "SSH FAILED: add this machine's public key to the CloudLab portal (Manage SSH Keys), then rerun"; exit 1; }
$SSH davidlin@$RXH 'sudo cat /root/setup-status 2>/dev/null | tail -2 || echo "setup.sh has not run/finished yet -- wait for boot services, then rerun"'
$SSH davidlin@$RXH 'sudo cat /root/topology.txt 2>/dev/null | head -5'
echo "   senders:"; for t in $TXS; do $SSH davidlin@$t hostname; done

echo "=== stage 1: deploy (kits everywhere, HomaModule cloned + built, flowlet-eval to rx) ==="
RSYNC="rsync -az --exclude '*.o' --exclude '*.ko' -e 'ssh -o StrictHostKeyChecking=no'"
ssh davidlin@$RXH "sudo rm -rf /root/e0 /root/k2" 2>/dev/null
for h in $RXH $TXS; do
	$SSH davidlin@$h "sudo mkdir -p /root && sudo chown \$(whoami) /root && $RSYNC" 2>/dev/null
	rsync -az --exclude '*.o' -e "$SSH" "$(dirname "$0")/e0" "davidlin@$h:/tmp/e0" \
		&& $SSH davidlin@$h "sudo mv /tmp/e0 /root/e0 && cd /root/e0 && sudo gcc -Wall -O2 -o sportgen sportgen.c"
done
rsync -az --exclude '*.o' -e "$SSH" "$(dirname "$0")/k2" "davidlin@$RXH:/tmp/k2" \
	&& $SSH davidlin@$RXH "sudo mv /tmp/k2 /root/k2 && cd /root/k2 && sudo gcc -Wall -O2 -o k2_rx k2_rx.c"
$SSH davidlin@$RXH "cd /root && sudo rm -rf HomaModule && sudo git clone --depth 1 https://github.com/PlatformLab/HomaModule.git /root/HomaModule && cd /root/HomaModule && sudo make > /root/homa-build.log 2>&1 && ls -la homa.ko || { echo BUILD-FAILED; sudo tail -20 /root/homa-build.log; }"
rsync -az -e "$SSH" ~/network-workspace/flowlet-eval "davidlin@$RXH:/tmp/flowlet-eval" \
	&& $SSH davidlin@$RXH "sudo mv /tmp/flowlet-eval /root/flowlet-eval"

echo "=== stage 2: E0 actuation gate (K1) ==="
$SSH davidlin@$RXH "cd /root/e0 && sudo ./e0_gate.sh --sender 10.10.1.10"
$SSH davidlin@$RXH "sudo cat /root/e0/e0_result.json 2>/dev/null"

echo "=== stage 3: K2 DDIO causality (the decisive figure) ==="
$SSH davidlin@$RXH "cd /root/k2 && sudo ./k2_ddio.sh 10.10.1.10"
$SSH davidlin@$RXH "sudo cat /root/k2_result.json 2>/dev/null"
echo "=== critical path complete: see /root/k2_results.txt, e0_result.json ==="