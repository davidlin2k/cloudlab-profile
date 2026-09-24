#!/bin/bash
# wedge-m: placement x C-state x 4 reps, interleaved order (policy
# changes every cell - kills the order confound), then fig1-3b: the W1
# re-run for the four flow-split-victim policies (AN-003 class).
set -u
cd /root/k2
for rep in 1 2 3 4; do
  for pin in 1 0; do
    for pol in P2 P3 P4; do
      PIN_IDLE=$pin ./p1cell.sh $pol W1 790000 64 $rep wedge-m
    done
  done
done
for pol in P0X P2 P3 P4; do
  for rate in 130000 390000 525000 790000 1050000 1300000; do
    for rep in 1 2 3; do
      ./p1cell.sh $pol W1 $rate 64 $rep fig1-3b
    done
  done
done
touch /root/p1/CHAIN2-DONE
