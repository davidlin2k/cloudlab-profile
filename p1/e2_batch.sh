#!/bin/bash
# p1/e2_batch.sh -- DR-008 E2: verified-aligned re-run (revised).
# metastab.sh M 10 e2-$i pin8 does the wiring (ch7 kthread -> cpu 8, IRQ
# 312 -> cpu 8). The 1 Hz sampler starts 4 s into the cell (after the
# wiring) and logs: thread mask, irq312 effective affinity, ch7
# aff_change/events. Gate per DR-008: aff_delta <= 5 AND mask == 8 on
# every sample. Pre-registered prediction: 0 wedges.
set -u
: > /root/p1/e2.log
sudo bash /root/p1/preflight.sh >> /root/p1/e2.log 2>&1 || exit 1
CH=$(sudo python3 /tmp/b2_dump.py 7 0 2 2>/dev/null | grep -m1 -oE "ch7 \(WEDGED\) @ 0x[0-9a-f]+" | grep -oE "0x[0-9a-f]+")
[ -n "$CH" ] || { echo "E2: discovery failed" >> /root/p1/e2.log; exit 1; }
echo "E2 ch7 addr $CH $(date -u +%FT%TZ)" >> /root/p1/e2.log
for i in 1 2 3 4 5 6 7 8; do
  D=/root/p1/metastab/M10-e2-$i
  rm -rf "$D"
  sudo bash /root/p1/metastab.sh M 10 "e2-$i" pin8 >> /root/p1/e2.log 2>&1 &
  CPID=$!
  sleep 4
  sudo python3 /tmp/e2_sampler.py "$CH" "$D" > /dev/null 2>&1 &
  SPID=$!
  wait $CPID 2>/dev/null
  # wait for the probe verdict (race-free parse)
  for j in $(seq 1 24); do
    sudo grep -qE "PROBE-(DEAD|OK)" "$D/cell.env" 2>/dev/null && break
    sleep 5
  done
  sleep 1
  sudo kill $SPID 2>/dev/null
  wait $SPID 2>/dev/null
  V=$(sudo grep -E "PROBE-(DEAD|OK)" "$D/cell.env" 2>/dev/null | tail -1)
  G=$(python3 - "$D/e2-sampler.csv" <<'EOF'
import csv, sys
try:
    rows = list(csv.reader(open(sys.argv[1])))
except Exception as e:
    print(f"gate sampler-missing ({e})"); raise SystemExit
if len(rows) < 3:
    print("gate too-few-samples"); raise SystemExit
d, mism = [], 0
for r in rows[1:]:
    d.append(int(r[3]))
    if r[1] != "8":
        mism += 1
print(f"gate aff_delta={d[-1]-d[0]} mask_mismatch={mism}/{len(rows)-1}")
EOF
)
  echo "== cell e2-$i: $V | $G $(date -u +%FT%TZ)" >> /root/p1/e2.log
  sleep 5
done
echo "E2-DONE $(date -u +%FT%TZ)" >> /root/p1/e2.log
