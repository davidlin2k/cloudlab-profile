#!/bin/bash
# p1/rq1_run.sh -- one RQ1 cell (specs/p1-CAUSAL.md): the readiness
# probe covers the whole cell. Usage: rq1_run.sh <cellname>
set -u
CELL="${1:?cellname}"
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
D=/root/p1/rq1/$CELL
rm -rf "$D"; mkdir -p "$D"
exec >> "$D/cell.log" 2>&1
echo "RQ1 CELL $CELL START $(date -u +%FT%TZ)"

bash /root/p1/preflight.sh || { echo PREFLIGHT-FAIL; exit 1; }

# channel 7 discovery (b2_dump prints "== ch7 (WEDGED) @ 0x<addr>")
CH=$(sudo python3 /tmp/b2_dump.py 7 0 1 2>/dev/null | awk '/^== ch7 /{print $5; exit}')
case "$CH" in 0x[0-9a-f]*) ;; *) echo "DISCOVERY-FAIL ch='$CH'"; exit 1;; esac
# ch7's REAL poll thread, identified by correlation (the napi.thread
# pointer is stale on this build). The finder needs traffic.
RQ1_NAPI_PID=""
if [ -z "${RQ1_NAPI_PID:-}" ]; then
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
    "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 158000 --secs 45 --plen 64 --core 4 > /tmp/rq1-find-flood.txt 2>&1 </dev/null &'" >/dev/null 2>&1
  sleep 2
  RQ1_NAPI_PID=$(sudo python3 /root/p1/find_napi_thread.py "$CH" 25 2>/dev/null | awk '/^PID /{print $2}')
fi
case "$RQ1_NAPI_PID" in ''|*[!0-9]*) echo "NAPI-PID-FAIL"; exit 1;; esac
[ -d "/proc/$RQ1_NAPI_PID" ] || { echo "NAPI-PID-GONE $RQ1_NAPI_PID"; exit 1; }
echo "ch7=$CH napi_pid=$RQ1_NAPI_PID"
export RQ1_NAPI_PID RQ1_CH="$CH"

# the probe covers the whole cell (~260 s), pinned to cpu 0
(taskset -c 0 python3 /tmp/rq1_probe.py "$CH" "$D/probe.csv" 260 "$RQ1_NAPI_PID" > "$D/probe.meta" 2>&1 &)

# the cell: flood -> wedge -> reduce -> monitor -> probe
bash /tmp/metastab.sh M 10 "$CELL" pin10 1 8 158000 20 >> "$D/cell.log" 2>&1
echo "CELL $CELL END $(date -u +%FT%TZ)"
tail -4 "$D/cell.log"
