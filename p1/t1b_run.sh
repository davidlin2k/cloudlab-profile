#!/bin/bash
# p1/t1b_run.sh -- one T1B cell (DR-015 / specs/p1-T1B.md).
# Usage: t1b_run.sh <cell> <A|B|C|D>
#   A = the IRQ core's SMT sibling; B = same socket, other core;
#   C = other socket; D = unpinned.
# Env: SENDER, DUTIP, IRQCPU, Q, IFACE (the preflight's), DUR (the
# probe seconds; the r6615 protocol = 330).
set -u
CELL="${1:?cell}"; ARM="${2:?arm A|B|C|D}"
IFACE=${IFACE:-enp24s0f1np1}
SENDER=${SENDER:-10.10.1.10}
DUTIP=${DUTIP:-10.10.1.1}
IRQCPU=${IRQCPU:-6}
Q=${Q:-7}
DUR=${DUR:-330}
RATE=${RATE:-158000}
SECS=${SECS:-20}

# arm -> the poller cpu
case "$ARM" in
  A) PC=$((IRQCPU + 32));;  # the SMT sibling
  B) PC=10;;                # same socket (node0), other physical core
  C) PC=24;;                # other socket (node1)
  D) PC="";;                # unpinned
  *) echo "bad arm $ARM"; exit 1;;
esac

D=/root/p1/t1b/$CELL
rm -rf "$D"; mkdir -p "$D"
exec >> "$D/cell.log" 2>&1
echo "T1B CELL $CELL arm=$ARM irqcore=$IRQCPU poller=${PC:-unpinned} sender=$SENDER START $(date -u +%FT%TZ)"

bash /root/p1/t1b_preflight.sh || { echo T1B-PREFLIGHT-RETRY; sleep 60; bash /root/p1/t1b_preflight.sh || { echo T1B-PREFLIGHT-FAIL; exit 1; }; }

# the poller = the queue's napi kthread (named napi/<iface>-<id>)
NAPI_PID=$(for p in /proc/[0-9]*; do c=$(tr -d '\0' < "$p/comm" 2>/dev/null); case "$c" in napi/${IFACE}-*) echo "${p#/proc/}";; esac; done | head -1)
case "$NAPI_PID" in ''|*[!0-9]*) echo "NAPI-PID-FAIL"; exit 1;; esac
echo "napi_pid=$NAPI_PID comm=$(cat /proc/$NAPI_PID/comm)"
if [ -n "$PC" ]; then taskset -pc "$PC" "$NAPI_PID" || { echo PIN-FAIL; exit 1; }; else taskset -pc 0-63 "$NAPI_PID" 2>/dev/null; fi

# the readiness probe over the whole cell
( env T1B_ARM="$ARM" T1B_IRQCPU="$IRQCPU" taskset -c 0 \
    python3 /root/p1/t1b_probe.py "$IFACE" "$Q" "$D/probe.csv" "$DUR" \
    > "$D/probe.meta" 2>&1 & )

# the flood
ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
  davidlin@$SENDER \
  "sudo bash -c 'nohup /root/k2/k5blast --dip $DUTIP --sip ${SENDER##*.} --sport 32704 --dport 7777 --rate $RATE --secs $SECS --plen 64 --core 4 > /tmp/flood-$CELL.txt 2>&1 </dev/null &'" \
  >/dev/null 2>&1
echo "FLOOD-LAUNCHED rate=$RATE secs=$SECS $(date -u +%FT%TZ)"

# wait for the probe to finish
for i in $(seq 1 $((DUR + 30))); do
  grep -q "T1B-PROBE-DONE" "$D/probe.meta" 2>/dev/null && break
  sleep 1
done
tail -1 "$D/probe.meta"
echo "T1B CELL $CELL END $(date -u +%FT%TZ)"