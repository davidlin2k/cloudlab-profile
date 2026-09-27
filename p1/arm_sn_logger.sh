#!/bin/bash
# p1/arm_sn_logger.sh v2 -- the completion-event + IRQ-entry timelines
# (DR-013 T1a, specs/p1-T1A.md; the DR-012 step-2 v1 is superseded,
# kept in git).
#   E lines: kprobe:mlx5_eq_comp_int (nb filter) -- completion events.
#   I lines: tracepoint:irq:irq_handler_entry (irq filter) -- the
#            vector's hardware IRQ entries (irq_int_handler is static,
#            so the tracepoint carries the IRQ timeline).
#   WALL line: the wall clock at launch; BEGIN line: bpftrace's nsecs.
#   The clocks join as wall = WALL + (nsecs - BEGIN)/1e9.
#   v6.17 signature: mlx5_eq_comp_int(struct notifier_block *nb, ...)
#   so arg0 = &eq_comp->irq_nb = eq + 120 (DWARF, build-tree ko).
#   Embedding the hex literal directly -- $((0xff...)) overflows
#   signed bash arithmetic and never matches in bpftrace's unsigned
#   compare; %u truncation also broke the first smoke.
# Usage: arm_sn_logger.sh <eq_ptr_hex> <irqn> [out] [timeout_s]
set -u
EQADDR="${1:?eq pointer 0x... (mlx5_core_cq.eq of the ch7 rq cq)}"
IRQN="${2:?vector irq number from /proc/interrupts (mlx5_comp7)}"
OUT="${3:-/tmp/eqint.log}"
TMO="${4:-400}"
case "$EQADDR" in
  0x*|0X*) EQHEX="${EQADDR#0x}"; EQHEX="${EQHEX#0X}";;
  *) EQHEX="$EQADDR";;
esac
NB=$((0x$EQHEX + 120))
NBHEX=$(printf '%x' "$NB")
echo "WALL $(date +%s.%N)" > "$OUT"
timeout "$TMO" bpftrace -e "BEGIN { printf(\"BEGIN %d\\n\", nsecs); }
kprobe:mlx5_eq_comp_int /arg0 == 0x$NBHEX/ { printf(\"E %d %d\\n\", nsecs/1000, cpu); }
tracepoint:irq:irq_handler_entry /args->irq == $IRQN/ { printf(\"I %d %d\\n\", nsecs/1000, cpu); }" >> "$OUT" 2>&1