#!/bin/bash
# wdiag.sh v2 -- AN-003 wedge diagnostic, PI-designed 2026-09-24 (DR-002
# pre-registration, DR-003). SUPERSEDES v1: the wide-mask arm is retired
# (if the driver reads EFFECTIVE affinity it is a silent no-op on x86).
# Arms are aligned vs misaligned with SINGLE-CPU masks (unambiguous
# under either reading), plus the unpinned arm (the post-revert default).
#
# Hypothesis: since 2017 mlx5's poll checks whether it runs on a CPU in
# the IRQ affinity mask; if busy and not on one it completes NAPI and
# re-arms CQs so the next IRQ moves polling to the "right" CPU. Threaded
# NAPI runs where pinned/scheduled -> busy polls may bail and wait; a
# lost re-arm under a full ring = the AN-003 signature.
#
# usage: wdiag2.sh inventory | effcheck | watch-start [tag] | watch-stop
#        wdiag2.sh cell ARM DUR REP
#        wdiag2.sh recovery ARM FLOODDUR
# ARM: mis-P3 mis-P4 ali-P4 ali-P3 P2 unpin
#   mis-*: kthread pinned away from IRQ 312's CPU (wedge expected)
#   ali-*: IRQ 312 moved ONTO the kthread's CPU (fix arm)
#   P2:    kthread and IRQ both on CPU 8 (already aligned; wedge there
#          would be the affinity-reset/drift class -> watch the watcher)
#   unpin: threaded with NO setaffinity (0-63) -- the state everyone
#          gets after echo 1 > threaded (PI: the arm that matters most)
# recovery: flood FLOODDUR s wired per ARM, kill, then a 60 s low-rate
#   probe + eq_rearm delta + devlink rx health (DR-003 decision 4).
set -u
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')
KTHREAD_CMD='ps -eo pid,comm | awk '\''$2 ~ /^napi\//{print $1; exit}'\'''

arm_wiring() {
  ARM="$1"
  APPCPU=8
  NICPU=8
  IRQC=8
  PIN=1
  case "$ARM" in
    mis-P3) NICPU=40; IRQC=8; PIN=1 ;;
    mis-P4) NICPU=9; IRQC=8; PIN=1 ;;
    ali-P3) NICPU=40; IRQC=40; PIN=1 ;;
    ali-P4) NICPU=9; IRQC=9; PIN=1 ;;
    P2) NICPU=8; IRQC=8; PIN=1 ;;
    unpin) NICPU=0; IRQC=8; PIN=0 ;;
    *) echo "unknown arm $ARM"; exit 2 ;;
  esac
}

reset_() {
  pkill -xc k2_rx 2>/dev/null || true
  pkill -xc k5blast 2>/dev/null || true
  for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
  sleep 1
}

snap_aff() {
  O="$1"
  echo "irq=$IRQ" > "$O"
  echo "smp_affinity_list: $(cat /proc/irq/$IRQ/smp_affinity_list)" >> "$O"
  echo "effective_affinity_list: $(cat /proc/irq/$IRQ/effective_affinity_list 2>/dev/null || echo n/a)" >> "$O"
  MI=$(eval "$KTHREAD_CMD")
  echo "napi_pid=${MI:-none}" >> "$O"
  if [ -n "${MI:-}" ]; then echo "napi_aff: $(awk '/Cpus_allowed_list/{print $2}' /proc/$MI/status)" >> "$O"; fi
}

snap_ctr() {
  O="$1"
  ethtool -S "$IFACE" | grep -E 'ch7_(aff_change|arm|poll|eq_rearm)' > "$O"
}

case "${1:-}" in
  inventory)
    echo "== ch counters (aff/arm/rearm/poll):"
    ethtool -S "$IFACE" | grep -iE 'ch[0-9]+_.*(aff|arm|rearm|poll)'
    echo "== napi threads (pid|comm):"
    ps -eo pid,comm | awk '$2 ~ /^napi\//{print $1"|"$2}'
    echo "== IRQ $IRQ line:"
    grep -E "^ *${IRQ}:" /proc/interrupts
    echo "== threaded: $(cat /sys/class/net/$IFACE/threaded)"
    ;;
  effcheck)
    echo "requested: $(cat /proc/irq/$IRQ/smp_affinity_list)"
    echo "effective: $(cat /proc/irq/$IRQ/effective_affinity_list 2>/dev/null || echo n/a)"
    ;;
  watch-start)
    TAG="${2:-diag}"
    mkdir -p /root/p1/wdiag
    echo "watcher start $(date -u +%FT%TZ) tag=$TAG"
    nohup bash /root/k2/wcounters.sh > "/root/p1/wdiag/live-$TAG.log" 2>&1 < /dev/null &
    echo "$!" > /root/p1/wdiag/watch.pid
    echo "watcher pid $! -> /root/p1/wdiag/live-$TAG.log"
    ;;
  watch-stop)
    if [ -f /root/p1/wdiag/watch.pid ]; then kill "$(cat /root/p1/wdiag/watch.pid)" 2>/dev/null || true; fi
    rm -f /root/p1/wdiag/watch.pid
    echo "watcher stopped"
    ;;
  cell)
    ARM="${2:?arm}"; DUR="${3:-195}"; REP="${4:-1}"
    arm_wiring "$ARM"
    TAG="wdiag-$ARM-rep$REP"
    O="/root/p1/wdiag/$TAG"
    mkdir -p "$O"
    echo "== cell $TAG dur=${DUR}s $(date -u +%FT%TZ)"
    reset_
    echo 1 > "/sys/class/net/$IFACE/threaded"
    taskset -pc "$APPCPU" "$(eval "$KTHREAD_CMD")" > "$O/app-pin.txt" 2>&1
    if [ "$PIN" = 1 ]; then taskset -pc "$NICPU" "$(eval "$KTHREAD_CMD")" > "$O/ni-pin.txt" 2>&1; else taskset -pc 0-63 "$(eval "$KTHREAD_CMD")" > "$O/ni-pin.txt" 2>&1; fi
    echo "$IRQC" > "/proc/irq/$IRQ/smp_affinity_list"
    sleep 1
    snap_aff "$O/affinity-pre.txt"
    snap_ctr "$O/counters-pre.txt"
    /root/k2/k2_rx --port 7777 --core "$APPCPU" --secs $((DUR + 8)) --skip 0 > "$O/consumer.txt" 2> "$O/consumer.err" &
    APP=$!
    sleep 1
    for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
      o=${pair%%:*}; s=${pair##*:}
      ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport $s --dport 7777 --rate 158000 --secs $((DUR + 3)) --plen 64 --core 4 > /tmp/wdiag-snd-$o.txt 2>&1 </dev/null &'"
    done
    sleep "$DUR"
    for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
    kill "$APP" 2>/dev/null || true
    sleep 6
    snap_aff "$O/affinity-post.txt"
    snap_ctr "$O/counters-post.txt"
    tail -3 "$O/consumer.err" | tee "$O/summary.txt"
    python3 /root/k2/wdiageval.py "$O"
    echo "== cell $TAG done $(date -u +%FT%TZ)"
    ;;
  recovery)
    ARM="${2:?arm}"; FLOOD="${3:-20}"
    arm_wiring "$ARM"
    TAG="wdiag-rec-$ARM"
    O="/root/p1/wdiag/$TAG"
    mkdir -p "$O"
    echo "== recovery $TAG: flood ${FLOOD}s, kill, 60s probe $(date -u +%FT%TZ)"
    reset_
    echo 1 > "/sys/class/net/$IFACE/threaded"
    taskset -pc "$APPCPU" "$(eval "$KTHREAD_CMD")" > /dev/null 2>&1
    if [ "$PIN" = 1 ]; then taskset -pc "$NICPU" "$(eval "$KTHREAD_CMD")" > /dev/null 2>&1; else taskset -pc 0-63 "$(eval "$KTHREAD_CMD")" > /dev/null 2>&1; fi
    echo "$IRQC" > "/proc/irq/$IRQ/smp_affinity_list"
    sleep 1
    snap_aff "$O/affinity-pre.txt"
    snap_ctr "$O/counters-pre.txt"
    /root/k2/k2_rx --port 7777 --core "$APPCPU" --secs 130 --skip 0 > "$O/consumer.txt" 2> "$O/consumer.err" &
    APP=$!
    sleep 1
    for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
      o=${pair%%:*}; s=${pair##*:}
      ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport $s --dport 7777 --rate 158000 --secs $((FLOOD + 3)) --plen 64 --core 4 > /tmp/wdiag-snd-$o.txt 2>&1 </dev/null &'"
    done
    sleep "$FLOOD"
    echo "t=$(date +%s.%N) killing flood senders" | tee -a "$O/wdiag.log"
    for o in 10 11 12 13 14; do ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o 'sudo pkill -xc k5blast; true' 2>/dev/null || true; done
    sleep 5
    snap_ctr "$O/counters-postflood.txt"
    echo "t=$(date +%s.%N) 60s probe at 10k pps" | tee -a "$O/wdiag.log"
    ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 60 --plen 64 --core 4 > /tmp/wdiag-probe.txt 2>&1 </dev/null &'"
    sleep 65
    snap_ctr "$O/counters-postprobe.txt"
    devlink dev health show pci/0000:c3:00.0 > "$O/devlink-health.txt" 2>&1
    kill "$APP" 2>/dev/null || true
    sleep 3
    echo "== consumer tail (probe-window wins):" | tee -a "$O/wdiag.log"
    tail -8 "$O/consumer.err" | tee -a "$O/wdiag.log"
    echo "== ch7 eq_rearm + aff deltas (postflood -> postprobe):" | tee -a "$O/wdiag.log"
    diff "$O/counters-postflood.txt" "$O/counters-postprobe.txt" | tee -a "$O/wdiag.log"
    cat "$O/devlink-health.txt" | tee -a "$O/wdiag.log"
    echo "== verdict rule (DR-003 decision 4):" | tee -a "$O/wdiag.log"
    echo "   probe packets visible in the consumer's late win lines = self-recovering performance bug (netdev patch route)" | tee -a "$O/wdiag.log"
    echo "   queue still dead after the 60s probe = permanent stall = REMOTE DoS: PRIVATE report to security@kernel.org + mlx5 maintainers (MAINTAINERS) per Documentation/process/security-bugs.rst; NOTHING public; PI reviews the draft first" | tee -a "$O/wdiag.log"
    ;;
  *)
    echo "usage: wdiag2.sh inventory|effcheck|watch-start [tag]|watch-stop|cell ARM DUR REP|recovery ARM FLOODDUR"
    ;;
esac
