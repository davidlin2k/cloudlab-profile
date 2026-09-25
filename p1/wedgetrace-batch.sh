#!/bin/bash
set -u
for cell in unpin:1 unpin:2 unpin:3 ali-P4:1 ali-P4:2 ali-P4:3; do
  A=${cell%%:*}; R=${cell##*:}
  echo "== wedgetrace $A rep$R $(date -u +%FT%TZ)"
  bash /root/k2/wdiagtrace.sh "$A" "$R"
  bash /root/k2/wedgextract.sh "$A" "$R" || true
done
echo "WEDGETRACE BATCH DONE $(date -u +%FT%TZ)"
touch /root/p1/WEDGETRACE-DONE
