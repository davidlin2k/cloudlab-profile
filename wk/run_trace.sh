#!/bin/bash
# run_trace.sh -- the trace-driven mechanism matrix, executed on real cores.
# Replays a wk/trace2pktemu.py trace through pktemu's placement policies.
#   usage: ./run_trace.sh <trace> [reps]   (run from anywhere; needs the
#   flowlet-eval checkout next to cloudlab-profile, as in the workspace)
set -euo pipefail
TRACE=${1:?usage: run_trace.sh <trace> [reps]}
REPS=${2:-3}
EMU=$(cd "$(dirname "$0")/../../flowlet-eval/emu" && pwd)
C="--flows=128 --hot=65536 --hl=32 --sl=48 --alu=600 --idealpp=615"
ONE="--wcpus=0,1,2,3,4,5,6,7 --genbase=8"
out="$EMU/../results/TRACE_matrix.txt"
mkdir -p "$(dirname "$out")"
{
for spec in "rss:rss:" "pa2:portassign:" "pax:portassign:--pa-exact" \
            "gen2:gen2:"; do
	IFS=: read tag pol e <<< "$spec"
	for r in $(seq "$REPS"); do
		"$EMU/pktemu" --policy=$pol --trace="$TRACE" $C $ONE $e 2>/dev/null \
			| head -2 | tail -1 | sed "s/^policy=[a-z0-9]*/policy=$tag/"
	done
done
} | tee "$out"
echo "results in $out"