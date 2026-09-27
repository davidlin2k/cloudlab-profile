#!/bin/bash
# p1/arm_sn_arm.sh -- DR-012 step 2: N stale-arm cells, one at a time,
# each with the eq-filtered completion-event logger attached.
# Usage: arm_sn_arm.sh <AS|SM> <n> [first]
#   AS = the stale-arm cells (HOP wiring, the race reachable)
#   SM = the smoke cells (static pin10 wiring, the healthy-queue check:
#        the logger must show sn parity walking normally with events)
set -u
ARM="${1:?AS|SM}"; N="${2:-4}"; FIRST="${3:-1}"
RUNARM=HOP; [ "$ARM" = SM ] && RUNARM=SMOKE
for i in $(seq "$FIRST" $((FIRST + N - 1))); do
  bash /root/p1/arm_sn_cell.sh "$ARM-$i" "$RUNARM" >> /root/p1/migrate/arm-$ARM.log 2>&1
  sleep 5
done
echo "ARM_SN $ARM DONE ($N cells)" >> /root/p1/migrate/arm-$ARM.log
