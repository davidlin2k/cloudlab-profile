#!/bin/bash
# p1/t1d_build.sh -- DR-013 T1d: build + install a kernel on the node.
# Usage: t1d_build.sh <v6.18.9|net-next>
# Reuses /scratch/kbuild/linux (the 6.17.8 build tree, .config in
# place); shallow-fetches the target, olddefconfig, -j all, installs
# modules + kernel, records c326f9c68921's presence in the tree.
set -u
K="${1:?v6.18.9|net-next}"
cd /scratch/kbuild/linux || exit 1
if [ "$K" = net-next ]; then
  git remote add netnext https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git 2>/dev/null || true
  git fetch --depth=1 netnext HEAD || exit 1
else
  git fetch --depth=1 origin "$K" || exit 1
fi
git checkout --detach FETCH_HEAD || exit 1
# c326f9c68921's presence (the addendum's September 2026 mlx5e
# backport): shallow trees can fetch a single sha; then is-ancestor.
if git fetch --depth=1 origin c326f9c68921 2>/dev/null \
   || git fetch --depth=1 netnext c326f9c68921 2>/dev/null; then
  if git merge-base --is-ancestor c326f9c68921 HEAD 2>/dev/null; then
    echo "C326F9C68921 PRESENT in $K ($(git rev-parse --short HEAD))"
  else
    echo "C326F9C68921 ABSENT from $K ($(git rev-parse --short HEAD))"
  fi
else
  echo "C326F9C68921 INCONCLUSIVE in $K (the sha fetch failed on the shallow tree)"
fi
cp /boot/config-6.17.8-061708-generic .config || exit 1
# the signing-key paths from the old config do not exist in the
# fetched tree -- drop them (facts for the report: the built kernels
# are unsigned test kernels)
scripts/config --set-str SYSTEM_TRUSTED_KEYS "" \
               --set-str SYSTEM_REVOCATION_KEYS "" \
               -d MODULE_SIG -d MODULE_SIG_FORCE
make olddefconfig || exit 1
make -j"$(nproc)" bzImage modules || exit 1
make modules_install || exit 1
make install || exit 1
REL=$(make kernelrelease 2>/dev/null || cat include/config/kernel.release 2>/dev/null)
echo "BUILD-OK $K release=$REL $(git rev-parse --short HEAD)"