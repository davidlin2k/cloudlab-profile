#!/bin/bash
# clean wedge-condition re-run (the wedge-m block is tossed: PIN_IDLE was
# not in the cell name, so pin=1/pin=0 runs overwrote each other).
# Tags wedge-m0 / wedge-m1 ARE the pin label. Interleaved policy order.
set -u
cd /root/k2
for rep in 1 2 3 4; do
  for pin in 1 0; do
    for pol in P2 P3 P4; do
      PIN_IDLE=$pin ./p1cell.sh $pol W1 790000 64 $rep wedge-m$pin
    done
  done
done
touch /root/p1/CHAIN3-DONE
