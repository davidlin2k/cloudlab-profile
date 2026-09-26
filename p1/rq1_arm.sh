#!/bin/bash
# p1/rq1_arm.sh -- run N RQ1 cells of one arm sequentially, detached.
# Usage: rq1_arm.sh <arm> <n> [first]   e.g. rq1_arm.sh A 8 1
set -u
ARM="${1:?arm A|B}"; N="${2:-8}"; FIRST="${3:-1}"
for i in $(seq "$FIRST" $((FIRST + N - 1))); do
  bash /root/p1/rq1_run.sh "$ARM-$i" >> /root/p1/rq1/arm-$ARM.log 2>&1
  sleep 5
done
echo "ARM $ARM DONE ($N cells)" >> /root/p1/rq1/arm-$ARM.log
