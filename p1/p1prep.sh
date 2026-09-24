#!/bin/bash
# p1prep.sh -- p1-LADDER preflight. Run as ROOT on rx (clnode366).
# Builds the kit everywhere, locks the platform, sets the known RSS key,
# re-pins IRQs, maps the target queue's NAPI thread, and smoke-tests the
# whole collection path. All state lands in /root/p1/.
set -u
IFACE=enp195s0np0
DIP=10.10.1.1
TQ=7                     # target RSS queue (RSS key = DPDK_KEY, identity tbl)
APP_CPU=8                # app core = queue-7 IRQ home (pin_irqs convention)
DPDK_KEY=6d5a56da255b0ec24167253d43a38fb0d0ca2bcbae7b30b477cb2da38030f20c6a42b73bbeac01fa
# W1 authoring (sip_oct -> sport) hitting queue 7 at dport 7777 (porttable-p1)
W1_SPORTS="10:32704 11:32726 12:32706 13:32724 14:32725"
TXIPS="10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13 10.10.1.14"

mkdir -p /root/p1
exec > >(tee /root/p1/prep.log) 2>&1
echo "== p1prep $(date -u +%FT%TZ) on $(hostname)"

echo "== build kit on rx"
cd /root/k2 && for f in k5blast k4send k3mot k4reins; do
  gcc -Wall -O2 -o $f $f.c -lpthread 2>/dev/null && echo "built $f" || echo "FAIL $f"
done
gcc -Wall -O2 -o k2_rx k2_rx.c && echo "built k2_rx" || echo "FAIL k2_rx"
cd /root/e0 && gcc -Wall -O2 -o sportgen sportgen.c && echo "built sportgen" || echo "FAIL sportgen"

echo "== build kit on senders (experiment LAN only)"
for ip in $TXIPS; do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@$ip \
    'cd /root/k2 && gcc -Wall -O2 -o k5blast k5blast.c && gcc -Wall -O2 -o k4send k4send.c -lpthread && cd /root/e0 && gcc -Wall -O2 -o sportgen sportgen.c && echo built $(hostname)' \
    || echo "FAIL build on $ip"
done

echo "== platform record"
{
  date -u +%FT%TZ; uname -a
  lscpu | grep -E "Model name|Socket|Core|Thread|NUMA node|CPU\(s\)"
  lscpu -e=CPU,NODE,SOCKET,CORE,CACHE | head -40
  echo "-- nic"; ethtool -i $IFACE | head -4
  ethtool -l $IFACE | tail -3
  ethtool -c $IFACE | head -12
  echo "-- smt"; cat /sys/devices/system/cpu/smt/active
  echo "-- numa_nic"; cat /sys/class/net/$IFACE/device/numa_node
  echo "-- siblings cpu$APP_CPU"; cat /sys/devices/system/cpu/cpu$APP_CPU/topology/thread_siblings_list
  echo "-- l3 id cpu$APP_CPU"; cat /sys/devices/system/cpu/cpu$APP_CPU/cache/index3/id
  echo "-- cpuidle"; cat /sys/devices/system/cpu/cpu$APP_CPU/cpuidle/state*/name 2>/dev/null | tr '\n' ' '; echo
  echo "-- pstate"; sudo dmesg | grep -iE "amd.*pstate|_CPC" | tail -2
  echo "-- governor"; cat /sys/devices/system/cpu/cpu$APP_CPU/cpufreq/scaling_governor 2>/dev/null || echo "NO cpufreq driver"
  echo "-- irqbalance"; systemctl is-active irqbalance
} > /root/p1/platform.txt
cat /root/p1/platform.txt

echo "== known RSS key"
ethtool -X $IFACE hkey $DPDK_KEY && echo "key set" || echo "FAIL set hkey"
ethtool -x $IFACE | head -6 > /root/p1/rss-after-key.txt
cat /root/p1/rss-after-key.txt

echo "== re-pin IRQs (pin_irqs.sh convention: comp_i -> cpu i+1, comp31 -> 33)"
bash /root/k2/pin_irqs.sh $IFACE /root/p1/irqpin >/dev/null 2>&1
echo "comp$TQ affinity: $(cat /proc/irq/$(grep -E "mlx5_comp${TQ}@pci:0000:c3" /proc/interrupts | awk '{print $1}' | tr -d ':')/smp_affinity_list)"

echo "== NAPI thread map for queue $TQ"
echo 1 > /sys/class/net/$IFACE/threaded
sleep 0.5
declare -A PRE
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  c=$(cat /proc/$p/comm 2>/dev/null)
  case "$c" in napi/*) PRE[$p]=$(awk '{print $1}' /proc/$p/schedstat 2>/dev/null);; esac
done
# blast queue 7 from tx0 (authored sport)
sip10sport=$(echo "$W1_SPORTS" | tr ' ' '\n' | grep '^10:' | cut -d: -f2)
ssh -o StrictHostKeyChecking=no davidlin@10.10.1.10 \
  "sudo /root/e0/sportgen --dip $DIP --dport 7777 --sport $sip10sport --n 300000 --proto udp --plen 64 --batch 64 --pause 500" >/dev/null
sleep 0.3
NAPI_PID=""
for p in "${!PRE[@]}"; do
  now=$(awk '{print $1}' /proc/$p/schedstat 2>/dev/null)
  d=$(( ${now:-0} - ${PRE[$p]:-0} ))
  if [ "$d" -gt 10000000 ]; then NAPI_PID=$p; echo "queue $TQ -> napi pid $p ($(cat /proc/$p/comm)) +${d}ns oncpu"; fi
done
[ -n "$NAPI_PID" ] && echo "$NAPI_PID" > /root/p1/napi-pid-q$TQ || echo "FAIL: no NAPI thread moved for queue $TQ"
echo 0 > /sys/class/net/$IFACE/threaded

echo "== smoke: k2_rx + k5blast through the whole path"
/root/k2/k2_rx --port 7777 --core $APP_CPU --secs 8 > /root/p1/smoke-rx.txt 2>&1 &
RXPID=$!
sleep 1
for pair in 10:32704 11:32726; do
  o=$(echo "$pair" | cut -d: -f1); s=$(echo "$pair" | cut -d: -f2)
  ssh -o StrictHostKeyChecking=no davidlin@10.10.1.$o \
    "sudo bash -c 'nohup /root/k2/k5blast --dip $DIP --sip $o --sport $s --dport 7777 --n 300000 --rate 50000 --plen 64 --core 4 >/tmp/k5-smoke-$o.txt 2>&1 &'" || echo "FAIL launch $o"
done
wait $RXPID
sleep 1
echo "-- consumer:"; cat /root/p1/smoke-rx.txt
for pair in 10 11; do
  echo "-- sender $pair:"; ssh -o StrictHostKeyChecking=no davidlin@10.10.1.$pair 'cat /tmp/k5-smoke-'"$pair"'.txt' 2>/dev/null
done
echo "== p1prep done"
