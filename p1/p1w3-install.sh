#!/bin/bash
# p1w3-install.sh HOST -- install the W3 (memcached+mutilate) kit.
# Run on rx as root for memcached; on each tx as root for mutilate.
# Requires a QUIET node (no running cells): package installs touch CPUs.
set -eu
case "$1" in
  rx)
    apt-get install -y memcached >/dev/null
    memcached -h | head -1
    ;;
  tx)
    apt-get install -y scons libevent-dev gengetopt libzmq-dev git >/dev/null
    if [ ! -x /root/k2/mutilate/mutilate ]; then
      git clone -q https://github.com/leverich/mutilate.git /root/k2/mutilate
    fi
    cd /root/k2/mutilate && scons >/dev/null
    /root/k2/mutilate/mutilate --version 2>&1 | head -1
    ;;
esac
echo "w3-install OK on $1"
