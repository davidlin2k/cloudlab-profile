#!/bin/bash
# wdiagbatch.sh -- the pre-registered wdiag v2 matrix (DR-002/DR-003).
# 6 arms x 8 reps x 195 s. On the FIRST cell with an onset, the recovery
# test runs immediately (decision 4), then the matrix continues. No
# waiters; creates WDIAG-DONE itself. The counter watcher runs
# throughout and is stopped at the end.
set -u
cd /root/k2
mkdir -p /root/p1/wdiag
echo "WDIAG START $(date -u +%FT%TZ)"
bash /root/k2/wdiag.sh watch-start wdiag
FIRST=""
for arm in mis-P4 mis-P3 ali-P4 ali-P3 P2 unpin; do
  for rep in 1 2 3 4 5 6 7 8; do
    echo "== batch cell $arm rep$rep $(date -u +%FT%TZ)"
    bash /root/k2/wdiag.sh cell $arm 195 $rep > /root/p1/wdiag/cell-$arm-$rep.log 2>&1
    python3 /root/k2/wdiageval.py /root/p1/wdiag/wdiag-$arm-rep$rep >> /root/p1/wdiag/cell-$arm-$rep.log 2>&1
    tail -3 /root/p1/wdiag/cell-$arm-$rep.log
    if [ -z "$FIRST" ] && grep -qE "ONSET|WEDGE-CLASS" /root/p1/wdiag/cell-$arm-$rep.log; then
      FIRST=$arm
      echo "== FIRST CONFIRMED WEDGE ($arm rep$rep): recovery NOW (decision 4) $(date -u +%FT%TZ)"
      bash /root/k2/wdiag.sh recovery $arm 20 > /root/p1/wdiag/recovery.log 2>&1
      echo "== recovery done -- PERMANENT STALL = ping the PI at once (run order 2)"
    fi
  done
done
bash /root/k2/wdiag.sh watch-stop
python3 /root/k2/wdiageval.py --summary /root/p1/wdiag/wdiag-*rep* > /root/p1/wdiag/summary.txt 2>&1
cat /root/p1/wdiag/summary.txt
echo "WDIAG DONE $(date -u +%FT%TZ)"
touch /root/p1/WDIAG-DONE
