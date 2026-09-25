#!/bin/bash
# t2_recovery_probe.sh OUTFILE SECS -- DR-005 task 2 step 2.
# Instrument record (2026-09-25): the memo's exact bpftrace command
# cannot resolve struct mlx5_core_cq on this toolchain (bpftrace 0.20.2
# resolves vmlinux BTF only; the type lives in the mlx5_core module
# BTF). The failure is recorded in OUTFILE, then the offset-grounded
# variant runs: cqn at bits_offset=0 per the module BTF dump
# (bpftool btf dump file /sys/kernel/btf/mlx5_core, STRUCT
# 'mlx5_core_cq' size=192, 'cqn' type_id=35 bits_offset=0). The
# CQ->RQ/ICOSQ mapping remains unavailable (devlink rx diagnose
# returns EINVAL on this platform; recorded in the task 1 cells).
set -u
O="$1"; SECS="${2:-60}"
{
  echo "== instrument attempt 1: the memo's exact bpftrace command"
  bpftrace -e 'kprobe:mlx5e_completion_event { @cq[((struct mlx5_core_cq *)arg0)->cqn] = count(); } interval:s:1 { time("%H:%M:%S "); print(@cq); clear(@cq); }' 2>&1 &
  P=$!
  sleep 4
  kill $P 2>/dev/null || true
  wait $P 2>/dev/null || true
} >> "$O" 2>&1
if grep -q "ERROR" "$O" 2>/dev/null; then
  echo "== fallback (recorded as used): offset-grounded kprobe, cqn at bits_offset=0 (module BTF)" >> "$O"
  bpftrace -e 'kprobe:mlx5e_completion_event { @cq[*(uint32_t *)arg0] = count(); } interval:s:1 { time("%H:%M:%S "); print(@cq); clear(@cq); }' >> "$O" 2>&1 &
else
  echo "== attempt 1 produced counts (no fallback needed)" >> "$O"
  bpftrace -e 'kprobe:mlx5e_completion_event { @cq[((struct mlx5_core_cq *)arg0)->cqn] = count(); } interval:s:1 { time("%H:%M:%S "); print(@cq); clear(@cq); }' >> "$O" 2>&1 &
fi
BPID=$!
sleep "$SECS"
kill $BPID 2>/dev/null || true
