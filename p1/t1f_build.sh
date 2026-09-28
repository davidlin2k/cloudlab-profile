#!/bin/bash
# p1/t1f_build.sh -- DR-014: build + install the rearm/watchdog kernel
# on the NEW receiver (clnode323). Fresh net-next shallow clone to
# /scratch/kbuild/linux (the reimage wiped the old tree); the stock
# 6.8 config as the base; unsigned-kernel hardening.
set -u
mkdir -p /scratch/kbuild && cd /scratch/kbuild || exit 1
if [ ! -d linux ]; then
  git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git linux || exit 1
fi
cd linux || exit 1
git fetch --depth=1 origin HEAD 2>/dev/null || true
git checkout --detach FETCH_HEAD || exit 1
echo "BASE $(git rev-parse --short HEAD) $(git log -1 --format=%cd --date=iso HEAD)"
cp /boot/config-6.8.0-138-generic .config || exit 1
scripts/config --set-str SYSTEM_TRUSTED_KEYS "" \
               --set-str SYSTEM_REVOCATION_KEYS "" \
               -d MODULE_SIG -d MODULE_SIG_FORCE
make olddefconfig || exit 1
make -j"$(nproc)" bzImage modules || exit 1
make modules_install || exit 1
make install || exit 1
REL=$(make kernelrelease 2>/dev/null || cat include/config/kernel.release 2>/dev/null)
echo "BUILD-OK release=$REL $(git rev-parse --short HEAD)"