#!/bin/bash
# p1/e7_trace.sh -- DR-008 E7: classify the two threaded=0 fuzz hits
# (cells 069, 089). Per DR-008: "Minimize + one trace. With softirq NAPI
# there should be no detour, so these are either rxfuzz's mid-cell
# IRQ-affinity perturbation (the 2017 case) or a second mechanism."
# Minimization already ran (notes/p2-RXFUZZ-2.md): 069 and 089 both
# have NON-threaded-requirement wedges in their families.
# This cell: re-create 069's hit config (threaded=0, adaptive on,
# ring 8192, gro on -- the other dims at task-1 defaults), run the
# M-cell, and trace the softirq poll path while dead.
set -u
IFACE=enp195s0np0
exec >> /root/p1/e7.log 2>&1
echo "E7 START $(date -u +%FT%TZ)"

# --- 069's config: threaded=0 (inline softirq), adaptive on, ring 8192,
# gro on. Ring change = channel recreation -> preflight after (protocol).
ethtool -G $IFACE rx 8192 || { echo "ring set FAIL"; exit 1; }
sleep 2
bash /root/p1/preflight.sh || exit 1
ethtool -C $IFACE adaptive-rx on 2>/dev/null || true
ethtool -K $IFACE gro on 2>/dev/null || true
bash /root/p1/preflight.sh || exit 1
echo "wiring: $(ethtool -g $IFACE | grep -A1 'Pre-set maximums' | tail -1) threaded=$(cat /sys/class/net/$IFACE/threaded)"

# --- the cell: task-1 M-cell on this config (threaded=0 -> the wiring
# echo is overridden after metastab's block; threaded=0 means no napi
# kthreads, softirq polls run on the IRQ core) ---
D=/root/p1/metastab/M1-e7-069
rm -rf "$D"
bash /root/p1/metastab.sh M 10 e7-069 unpin 0 8 158000 20
V=$(grep -E "PROBE-(DEAD|OK)" "$D/cell.env" | tail -1)
echo "E7 cell verdict: $V"
if ! echo "$V" | grep -q PROBE-DEAD; then
  echo "E7: no dead queue this cell -- rerun or accept the sample"
  bash /root/p1/preflight.sh
  exit 0
fi

# --- dead: trace the softirq path (no threaded kthread exists) ---
NAPI=$(sudo python3 /tmp/b2_dump.py 7 0 2 2>/dev/null | grep -m1 -oE "ch7 \(WEDGED\) @ 0x[0-9a-f]+" | grep -oE "0x[0-9a-f]+")
sudo python3 /tmp/b2_dump.py 7 0 5 > /tmp/e7_dead_dump.txt 2>&1
timeout 60 bpftrace -e "
kprobe:mlx5e_napi_poll /arg0 == $NAPI/ { printf(\"POLL-ENTER cpu=%d t=%d\n\", cpu, nsecs/1000000); }
kretprobe:mlx5e_napi_poll { printf(\"POLL-RET w=%d cpu=%d t=%d\n\", (int64)retval, cpu, nsecs/1000000); }
kprobe:mlx5e_completion_event /arg0 == $((16#$NAPI + 320 + 56))/ { printf(\"EVENT t=%d\n\", nsecs/1000000); }
" > /tmp/e7_trace.txt 2>&1
grep -c POLL-RET /tmp/e7_trace.txt; grep -c EVENT /tmp/e7_trace.txt

# --- classify: softirq NAPI has no kthread; the detour cannot park a
# threaded poll. If the queue still dies here, the mechanism is
# rxfuzz's IRQ-perturbation (the 2017 case) or a second path; if it
# recovers cleanly, the 069 family wedge needed threaded=1 after all
# (a minimize fluke) -- either way the artifacts decide it.
bash /root/p1/rxrecover.sh /root/p1/rxrecover-e7.log
ethtool -G $IFACE rx 1024
bash /root/p1/preflight.sh
echo "E7 DONE $(date -u +%FT%TZ)"
