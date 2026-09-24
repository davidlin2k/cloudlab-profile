#!/bin/bash
# wdiag.sh -- AN-003 wedge diagnostic, PI-designed 2026-09-24 (DR-002).
# mlx5 poll-affinity hypothesis: since 2017 mlx5's poll checks whether
# it runs on a CPU in the IRQ affinity mask; if busy and not on one it
# completes NAPI and re-arms the CQs so the next IRQ moves polling to
# the "right" CPU. Threaded NAPI runs wherever pinned -> busy polls may
# bail and wait for an IRQ; a lost re-arm under a full ring = the
# AN-003 signature (IRQ masked, kthread asleep, ring overflowing).
#
# usage: wdiag.sh inventory | watch-start | watch-stop
#        wdiag.sh ab POLICY MASK [DUR]   (MASK: narrow=8 wide=8,9)
#        wdiag.sh recovery POLICY [DUR]
#   ab        -- the decisive A/B: P4 flood cell via the SAME p1cell
#                harness as every other run, with IRQ 312's mask either
#                narrow (8: wedge expected) or wide (8,9: kthread's CPU
#                IN the mask -> wedge should vanish and aff_change stay
#                flat, confirming the mechanism).
#   recovery  -- stop the flood mid-wedge, then a 10k probe: a queue
#                that stays dead = remotely triggerable DoS (severity).
set -u
IFACE=enp195s0np0
IRQ=$(grep -E 'mlx5_comp7@pci:0000:c3' /proc/interrupts | awk '{print $1}' | tr -d ':')

case "${1:-}" in
  inventory)
    echo "== ch counters (aff/arm/rearm/poll):"
    ethtool -S $IFACE | grep -iE 'ch[0-9]+_.*(aff|arm|rearm|poll)'
    echo "== napi threads:"; pgrep -af 'napi/enp195s0np0' || true
    echo "== IRQ $IRQ line:"; grep -E "^ *${IRQ}:" /proc/interrupts
    echo "== threaded:"; cat /sys/class/net/$IFACE/threaded
    ;;
  watch-start)
    mkdir -p /root/p1/wdiag
    nohup taskset -c 62 bash /root/k2/wcounters.sh \\
      > /root/p1/wdiag/live-${2:-run}.log 2>&1 < /dev/null &
    echo $! > /root/p1/wdiag/watch.pid
    echo "watcher pid $! -> /root/p1/wdiag/live-${2:-run}.log"
    ;;
  watch-stop)
    # kill by pidfile: the script's comm is "bash", so exact-name pkills
    # never match it (learned the hard way 2026-09-24)
    [ -f /root/p1/wdiag/watch.pid ] && kill "$(cat /root/p1/wdiag/watch.pid)" 2>/dev/null
    rm -f /root/p1/wdiag/watch.pid
    echo "watcher stopped"
    ;;
  ab)
    POL=${2:?P2|P3|P4}; MASK=${3:-narrow}; DUR=${4:-30}
    TAG="wdiag-ab-${POL}-${MASK}"
    echo "== A/B $TAG: IRQ $IRQ affinity -> ${MASK} ($(date -u +%FT%TZ))"
    if [ "$MASK" = wide ]; then
      echo "8,9" > /proc/irq/$IRQ/smp_affinity_list
    else
      echo "8" > /proc/irq/$IRQ/smp_affinity_list
    fi
    cat /proc/irq/$IRQ/smp_affinity_list > /root/p1/wdiag/$TAG.mask
    bash /root/k2/p1cell.sh "$POL" W1 790000 64 1 "$TAG"
    D=$(grep "sum=" /root/p1/results/$TAG/*/rep1/consumer.err 2>/dev/null | tail -1)
    echo "verdict $TAG: $D"
    ;;
  recovery)
    POL=${2:?P2|P3|P4}; DUR=${3:-20}
    TAG="wdiag-rec-$POL"
    OUT=/root/p1/wdiag/$TAG
    mkdir -p "$OUT"
    echo "== recovery $TAG: flood ${DUR}s then kill then 10k probe"
    pkill -xc k2_rx >/dev/null 2>&1; pkill -xc k5blast >/dev/null 2>&1
    echo 0 > /sys/class/net/$IFACE/threaded
    bash /root/k2/p1pol.sh "$POL" > "$OUT/policy.txt" 2>&1
    /root/k2/k2_rx --port 7777 --core 8 --secs $((DUR + 25)) --skip 0 \
      > "$OUT/consumer.txt" 2> "$OUT/consumer.err" &
    APP=$!
    for pair in 10:32704 11:32726 12:32706 13:32724 14:32725; do
      o=${pair%%:*}; s=${pair##*:}
      ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
        "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip $o --sport $s \
        --dport 7777 --rate 158000 --secs $((DUR + 5)) --plen 64 --core 4 \
        > /tmp/wdiag-snd-$o.txt 2>&1 </dev/null &'"
    done
    sleep "$DUR"
    echo "t=$(date +%s.%N) killing senders mid-wedge" | tee -a "$OUT/wdiag.log"
    for o in 10 11 12 13 14; do
      ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.$o \
        "sudo pkill -xc k5blast; true" 2>/dev/null
    done
    sleep 8
    echo "t=$(date +%s.%N) 10k probe (5s)" | tee -a "$OUT/wdiag.log"
    ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
      "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 \
      --dport 7777 --rate 10000 --secs 5 --plen 64 --core 4 \
      > /tmp/wdiag-probe.txt 2>&1 </dev/null &'"
    sleep 8
    kill $APP 2>/dev/null
    PROBE=$(ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
      "cat /tmp/wdiag-probe.txt" 2>/dev/null | grep -oE 'sent=[0-9]+' | head -1)
    echo "probe $PROBE" | tee -a "$OUT/wdiag.log"
    tail -3 "$OUT/consumer.err" | tee -a "$OUT/wdiag.log"
    echo "verdict: probe packets delivered appear in consumer.err win lines;"
    echo "  zero consumption after the flood = permanent stall (DoS severity)"
    ;;
  *)
    echo "usage: wdiag.sh inventory|watch-start [name]|watch-stop|ab POL MASK [DUR]|recovery POL [DUR]"
    ;;
esac
