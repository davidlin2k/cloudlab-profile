#!/bin/bash
# chain7 -- W5 time-series matrix for Fig 5 (launch ONLY after CHAIN6-DONE
# and a zero-driver check; creates CHAIN7-DONE itself; no waiters).
# 36 cells: P0/P2/P4/P7 x ramp/burst/step x 3 reps. Interleaved pattern
# and policy order to kill order confounds.
set -u
cd /root/k2
echo "CHAIN7 START $(date -u +%FT%TZ)"
for rep in 1 2 3; do
  for pattern in ramp burst step; do
    for pol in P7 P0 P2 P4; do
      bash /root/k2/p1w5.sh $pol $pattern $rep w5
    done
  done
done
echo "CHAIN7 DONE $(date -u +%FT%TZ)"
touch /root/p1/CHAIN7-DONE
