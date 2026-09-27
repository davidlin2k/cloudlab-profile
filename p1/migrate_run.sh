#!/bin/bash
# p1/migrate_run.sh -- one p1-MIGRATE cell. Usage: migrate_run.sh <cell> <MA|MB|HOP>
set -u
CELL="${1:?cellname}"; ARM="${2:?arm MA|MB|HOP}"
WIRE=unpin
[ "$ARM" = MB ] && WIRE=pin46
[ "$ARM" = HOP ] && WIRE=pin10   # the hopper takes over the affinity
                                 # right after the wiring pins to 10
[ "$ARM" = SMOKE ] && WIRE=pin10 # the static healthy-queue smoke (the
                                 # DR-012 step-2 logger sanity cell)
[ "$ARM" = SWEEP ] && WIRE="pin${SWEEP_CPU:?SWEEP_CPU env not set}"
                                 # the DR-012 step-3 locality sweep
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
D=/root/p1/migrate/$CELL
rm -rf "$D"; mkdir -p "$D"
exec >> "$D/cell.log" 2>&1
echo "MIGRATE CELL $CELL ($ARM wire=$WIRE) START $(date -u +%FT%TZ)"

bash /root/p1/preflight.sh || { echo PREFLIGHT-RETRY; sleep 60; bash /root/p1/preflight.sh || { echo PREFLIGHT-FAIL; exit 1; }; }

CH=$(sudo python3 /tmp/b2_dump.py 7 0 1 2>/dev/null | awk '/^== ch7 /{print $5; exit}')
case "$CH" in 0x[0-9a-f]*) ;; *) echo "DISCOVERY-FAIL ch='$CH'"; exit 1;; esac

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

# the readiness probe covers the whole cell (TRACE=1 lengthens it).
# T1A=1 (DR-013): the probe gets the eq pointer + irqn so the CSV
# carries the comp-EQ state columns (specs/p1-T1A.md).
PROBE_ARGS=("$CH" "$D/probe.csv" 330 "$RQ1_NAPI_PID")
if [ "${T1A:-0}" = 1 ]; then
  EQA=$(sudo python3 /root/p1/eqdump.py "$CH" 2>/dev/null \
        | grep -oE 'EQ=0x[0-9a-f]+' | cut -d= -f2)
  case "$EQA" in
    0x[0-9a-f]*) PROBE_ARGS+=("$EQA" "$IRQ");;
    *) echo "T1A-EQ-FAIL eq='$EQA'"; PROBE_ARGS+=(0 "");;
  esac
fi
(taskset -c 0 python3 /root/p1/rq1_probe.py "${PROBE_ARGS[@]}" > "$D/probe.meta" 2>&1 &)

if [ "$ARM" = HOP ]; then
  # the forced-migration arm: pin + hop 10<->46 every 100 ms
  (python3 /root/p1/hopper.py "$RQ1_NAPI_PID" 10 46 100 400 "$D/hops.csv" > "$D/hopper.out" 2>&1 &)
fi

# the cell WITH the wake trace (metastab TRACE=1: napi/sched/irq events)
TRACE=1 bash /root/p1/metastab.sh M 10 "$CELL" "$WIRE" 1 8 158000 20 >> "$D/cell.log" 2>&1
echo "CELL $CELL END $(date -u +%FT%TZ)"
tail -4 "$D/cell.log"
