#!/bin/bash
# p1/arm_sn_logger.sh -- the completion-event timeline (DR-012 step 2).
# bpftrace: kprobe:mlx5_eq_comp_int -> one line per completion event
# (ts us, cpu). Writes to $2 (default /tmp/eqint.log).
#
# v6.17 signature: mlx5_eq_comp_int(struct notifier_block *nb, ...)
# so arg0 is &eq_comp->irq_nb (irq_nb @ +120 in mlx5_eq_comp, DWARF
# of the build-tree mlx5_core.ko). The EQ pointer of ch7's rq CQ is
# read at mcq+176 (mlx5_core_cq.eq); the FILTER VALUE is that eq
# pointer + 120 (the nb). Pass the eq pointer as $1; the +120 is
# applied here. Embedding the hex literal directly -- $((0xff...))
# overflows signed bash arithmetic and never matches in bpftrace's
# unsigned compare; %u truncation also broke the first smoke.
set -u
EQADDR="${1:?eq pointer 0x... (mlx5_core_cq.eq of the ch7 rq cq)}"
OUT="${2:-/tmp/eqint.log}"
case "$EQADDR" in
  0x*|0X*) EQHEX="${EQADDR#0x}"; EQHEX="${EQHEX#0X}";;
  *) EQHEX="$EQADDR";;
esac
NB=$((0x$EQHEX + 120))
NBHEX=$(printf '%x' "$NB")
timeout 400 bpftrace -e "kprobe:mlx5_eq_comp_int /arg0 == 0x$NBHEX/ \
  { printf(\"%d %d\\n\", nsecs/1000, cpu); }" > "$OUT" 2>&1
