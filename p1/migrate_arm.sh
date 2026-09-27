#!/bin/bash
# p1/migrate_arm.sh -- run N p1-MIGRATE cells of one arm, detached.
# Usage: migrate_arm.sh <MA|MB> <n> [first]
set -u
ARM="${1:?MA|MB}"; N="${2:-8}"; FIRST="${3:-1}"
for i in $(seq "$FIRST" $((FIRST + N - 1))); do
  bash /root/p1/migrate_run.sh "$ARM-$i" "$ARM" >> /root/p1/migrate/arm-$ARM.log 2>&1
  sleep 5
done
echo "ARM $ARM DONE ($N cells)" >> /root/p1/migrate/arm-$ARM.log
