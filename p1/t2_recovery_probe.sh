#!/bin/bash
# t2_recovery_probe.sh OUTFILE SECS -- DR-005 task 2 recovery-source probe
# Per-CQ completion counts from mlx5e_completion_event (bpftrace, BTF present).
# The CQ->RQ/ICOSQ mapping is NOT derivable from the devlink rx dump on this
# platform (EINVAL recorded in the task 1 cells); the mapping gap is recorded.
set -u
O="$1"; SECS="${2:-60}"
echo "PROBE START $(date -u +%FT%TZ) secs=$SECS" > "$O"
bpftrace -e 'kprobe:mlx5e_completion_event { @cq[((struct mlx5_core_cq *)arg0)->cqn] = count(); } interval:s:'"$SECS"' { print(@cq); exit(); }' >> "$O" 2>&1
echo "PROBE END $(date -u +%FT%TZ)" >> "$O"
