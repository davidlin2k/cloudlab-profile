#!/bin/bash
# p1/t1e_build.sh -- DR-013 T1e: apply the threaded-NAPI cpumask patch
# to the net-next checkout (/scratch/kbuild/linux, at 014d795c7),
# build, install. The patched poller defaults to the L3 siblings of
# its vector's effective affinity (specs/p1-T1E.md).
set -u
cd /scratch/kbuild/linux || exit 1
if git apply --check /root/p1/t1e-napi-thread-cpumask.patch 2>/dev/null; then
  git apply /root/p1/t1e-napi-thread-cpumask.patch && echo PATCH-APPLIED-git
else
  patch -p1 --fuzz=3 < /root/p1/t1e-napi-thread-cpumask.patch && echo PATCH-APPLIED-patch
fi
grep -q "set_cpus_allowed_ptr(n->thread, llc)" net/core/dev.c || {
  echo PATCH-VERIFY-FAIL; exit 1; }
echo PATCH-VERIFIED
make -j"$(nproc)" bzImage modules || exit 1
make modules_install || exit 1
make install || exit 1
echo "T1E-BUILD-OK release=$(make kernelrelease) base=$(git rev-parse --short HEAD) $(date -u +%FT%TZ)"