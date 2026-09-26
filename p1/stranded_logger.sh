#!/bin/bash
# p1/stranded_logger.sh -- DR-009 Change 2: observe the contract
# violation at the core + the driver's state per sub-budget poll.
# Usage: stranded_logger.sh <ch_addr_hex> <out_csv> [duration_s]
# Records, for every mlx5e_napi_poll return with work < 64 (the core's
# "done" branch):
#   w (returned work), cpu, napi.state byte, cc, op_own at the cc
#   position, cycle phase, owned (op_own&1 == phase => an unconsumed,
#   HW-written completion at the poll's own consumer index).
# The STRANDED-BACKLOG event (post-processed, per DR-009): w < 64 AND
# owned=1 AND cpu off the channel's affinity mask -- i.e. the driver
# underreported work (work < weight => repoll not set) while the CQ
# still held a pending completion, on an off-mask poll.
# Also logs the core's tracepoint view (trace_napi_poll: work/again) so
# the contract decision is observed at the core, not inferred.
set -u
CH=$1
OUT=$2
DUR=${3:-400}
IF=enp195s0np0
# the core tracepoint's field names, read from the live format file:
FMT=/sys/kernel/tracing/events/napi/napi_poll/format
[ -e "$FMT" ] && grep -E "field:" "$FMT" | head -6 > "${OUT}.fmt" 2>/dev/null
WFIELD=work; AFIELD=again
grep -q "field:int again" "$FMT" 2>/dev/null || AFIELD=""
[ -n "$AFIELD" ] || AFIELD=$(grep -oE "field:[a-z_]+ ([a-z_]+)" "$FMT" 2>/dev/null | awk '{print $2}' | grep -E "again|repoll" | head -1)
echo "logger: ch=$CH dur=${DUR}s work_field=$WFIELD again_field=$AFIELD"

timeout "$DUR" bpftrace -e "
kprobe:mlx5e_napi_poll { @np[tid] = arg0; }
kretprobe:mlx5e_napi_poll /@np[tid]/
{
  \$ch = @np[tid] - 10000;
  \$w = (uint64)retval;
  if (\$w < 64) {
    \$cq = \$ch + 320;
    \$frags = *(uint64*)(\$cq);
    \$logsz = *(uint8*)(\$cq + 16);
    \$lfs = *(uint8*)(\$cq + 18);
    \$cc = *(uint32*)(\$cq + 32);
    \$fi = (\$cc >> \$lfs);
    \$frag = *(uint64*)(\$frags + \$fi * 16);
    \$idx = \$cc & ((1 << \$lfs) - 1);
    \$own = *(uint8*)(\$frag + \$idx * 64 + 63);
    \$phase = (\$cc >> \$logsz) & 1;
    \$state = *(uint8*)(\$ch + 10016);
    printf(\"SUB t=%d w=%d cpu=%d state=%d cc=%d own=%d phase=%d owned=%d\\n\",
           nsecs / 1000000, \$w, cpu, \$state, \$cc, \$own, \$phase,
           (\$own & 1) == \$phase);
  }
  delete(@np[tid]);
}
tracepoint:napi:napi_poll
{
  printf(\"CORE t=%d w=%d again=%s cpu=%d\\n\", nsecs / 1000000,
         args->$WFIELD, args->$AFIELD ? 1 : 0, cpu);
}
" > "$OUT" 2>&1
grep -c "SUB " "$OUT" || true
grep -c "CORE " "$OUT" || true