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
CH=$(sudo python3 /tmp/b2_dump.py 7 0 1 2>/dev/null | awk '/== ch7 /{print $6; exit}')
case "$CH" in 0x[0-9a-f]*) ;; *) echo "DISCOVERY-FAIL ch='$CH'"; exit 1;; esac
echo "ch7=$CH"

# the probe covers the whole cell (~260 s), pinned to cpu 0
(taskset -c 0 python3 /tmp/rq1_probe.py "$CH" "$D/probe.csv" 260 > "$D/probe.meta" 2>&1 &)

# the cell: flood -> wedge -> reduce -> monitor -> probe
bash /tmp/metastab.sh M 10 "$CELL" pin10 1 8 158000 20 >> "$D/cell.log" 2>&1
echo "CELL $CELL END $(date -u +%FT%TZ)"
tail -4 "$D/cell.log"
