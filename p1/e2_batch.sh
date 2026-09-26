#!/bin/bash
# p1/e2_batch.sh -- DR-008 E2: verified-aligned re-run.
# Wiring per cell: ch7 napi kthread pinned to CPU 8 (its IRQ core), IRQ 312
# on CPU 8 (preflight), 1 Hz manipulation sampler throughout.
# Pre-registered (DR-008 memo): predict 0 wedges; a cell counts only if
# aff_change ~ 0 throughout (gate: delta <= 5 over the cell) and the
# thread mask reads "8" every sample.
set -u
cd /root/p1
: > /root/p1/e2.log
sudo bash /root/p1/preflight.sh >> /root/p1/e2.log 2>&1 || exit 1
CH=$(sudo python3 /tmp/b2_dump.py 7 0 2 2>/dev/null | grep -m1 -oE "ch7 \(WEDGED\) @ 0x[0-9a-f]+" | grep -oE "0x[0-9a-f]+")
[ -n "$CH" ] || { echo "E2: discovery failed" >> /root/p1/e2.log; exit 1; }
echo "E2 ch7 addr $CH $(date -u +%FT%TZ)" >> /root/p1/e2.log
mkdir -p /root/p1/e2
for i in 1 2 3 4 5 6 7 8; do
  D=/root/p1/metastab/M10-e2-$i
  # pin ch7's napi kthread to cpu 8 (its IRQ core)
  sudo python3 - "$CH" <<'EOF' >> /root/p1/e2.log 2>&1
import re, subprocess, sys
ch = int(sys.argv[1], 16)
import drgn
prog = drgn.program_from_kernel()
try:
    prog.load_debug_info(["/scratch/kbuild/linux/vmlinux"], main=False)
except Exception:
    pass
def u(a, n): return int.from_bytes(bytes(prog.read(a, n)), "little")
nid = u(ch + 10000 + 380, 4)
comm = f"napi/enp195s0np0-{nid}"
pid = None
for p in subprocess.run(["bash", "-c", "ls /proc | grep -E '^[0-9]+$'"],
                        capture_output=True, text=True).stdout.split():
    try:
        if open(f"/proc/{p}/comm").read().strip() == comm:
            pid = p
            break
    except Exception:
        continue
if pid:
    subprocess.run(["taskset", "-pc", "8", pid], capture_output=True)
    print(f"E2 pinned {comm} pid {pid} -> cpu 8")
else:
    print(f"E2 PIN FAIL: no thread {comm}")
EOF
  sudo mkdir -p "$D"
  sudo python3 /tmp/e2_sampler.py "$CH" "$D" > /dev/null 2>&1 &
  SPID=$!
  sudo bash /root/p1/metastab.sh M 10 "e2-$i" >> /root/p1/e2.log 2>&1
  sleep 1
  sudo pkill -f "e2_sampler.py" 2>/dev/null
  wait $SPID 2>/dev/null
  V=$(grep -E "PROBE-(DEAD|OK)" "$D/cell.env" 2>/dev/null | tail -1)
  # manipulation gate: aff_change delta and mask mismatches
  G=$(python3 - "$D/e2-sampler.csv" <<'EOF'
import csv, sys
rows = list(csv.reader(open(sys.argv[1])))
d = []
mism = 0
for r in rows[1:]:
    d.append(int(r[3]))
    if r[1] != "8":
        mism += 1
print(f"gate aff_delta={d[-1]-d[0] if d else '?'} mask_mismatch={mism}/{len(rows)-1}")
EOF
)
  echo "== cell e2-$i: $V | $G $(date -u +%FT%TZ)" >> /root/p1/e2.log
  sleep 5
done
echo "E2-DONE $(date -u +%FT%TZ)" >> /root/p1/e2.log
