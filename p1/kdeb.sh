#!/bin/bash
# kdeb.sh -- fetch Ubuntu mainline v6.4.0 debs (the LAST kernel line with
# the pre-6.5 ksoftirqd deferral) into /root/p1/kdeb. Exact names from
# the kernel.ubuntu.com mainline v6.4/amd64 index. Touches DONE at end.
set -u
cd /root/p1/kdeb || exit 1
B=https://kernel.ubuntu.com/mainline/v6.4/amd64
VER=6.4.0-060400.202306271339
for f in \
  linux-headers-6.4.0-060400_${VER}_all.deb \
  linux-headers-6.4.0-060400-generic_${VER}_amd64.deb \
  linux-image-unsigned-6.4.0-060400-generic_${VER}_amd64.deb \
  linux-modules-6.4.0-060400-generic_${VER}_amd64.deb; do
  wget -q -c "$B/$f" || echo "FAIL $f"
done
wget -q -c "$B/CHECKSUMS" || true
rm -f DONE
ls -la *.deb > LIST.txt
touch DONE
echo "kdeb done: $(ls *.deb | tr '\n' ' ')"
