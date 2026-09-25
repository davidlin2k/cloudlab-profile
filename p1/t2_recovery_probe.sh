#!/bin/bash
# t2_recovery_probe.sh OUTFILE SECS -- DR-005 task 2 step 2 (the memo's exact
# bpftrace shape: per-second per-CQ completion counts, for the whole cell)
set -u
O="$1"; SECS="${2:-60}"
bpftrace -e 'kprobe:mlx5e_completion_event { @cq[((struct mlx5_core_cq *)arg0)->cqn] = count(); } interval:s:1 { time("%H:%M:%S "); print(@cq); clear(@cq); }' > "$O" 2>&1 &
BPID=$!
sleep "$SECS"
kill $BPID 2>/dev/null || true
