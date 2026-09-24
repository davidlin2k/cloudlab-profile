#!/bin/bash
# p1pol.sh -- apply ONE p1-LADDER policy on rx (root). Idempotent; every
# cell calls it, so arms differ ONLY in what this script sets.
# usage: p1pol.sh P0|P0X|P2|P3|P4   (echoes "app_cpu=.. napi_cpu=.. napi_pid=..")
set -u
POLICY=${1:?policy}
IFACE=enp195s0np0
TQ=7
IRQ=$(grep -E "mlx5_comp${TQ}@pci:0000:c3" /proc/interrupts | awk '{print $1}' | tr -d ':')
case "$POLICY" in
  P0)  APP_CPU=8;  NAPI_CPU="" ;;
  P0X) APP_CPU=9;  NAPI_CPU="" ;;
  P2)  APP_CPU=8;  NAPI_CPU=8 ;;
  P3)  APP_CPU=8;  NAPI_CPU=40 ;;
  P4)  APP_CPU=8;  NAPI_CPU=9 ;;
  *) echo "bad policy $POLICY" >&2; exit 1 ;;
esac

# IRQ home of the target queue is ALWAYS cpu 8 (the NAPI-processing home
# for inline arms; the hardirq wakeup point for threaded arms).
echo 8 > /proc/irq/$IRQ/smp_affinity_list

if [ -z "$NAPI_CPU" ]; then
  echo 0 > /sys/class/net/$IFACE/threaded
  echo "app_cpu=$APP_CPU napi_cpu= napi_pid= policy=$POLICY"
  exit 0
fi

echo 1 > /sys/class/net/$IFACE/threaded
sleep 0.3
NAPI_PID=$(cat /root/p1/napi-pid-q$TQ 2>/dev/null || echo "")
# validate or (re)discover the target queue's NAPI thread by schedstat probe
if [ -z "$NAPI_PID" ] || [ ! -d "/proc/$NAPI_PID" ] || \
   ! grep -q "^napi/" /proc/$NAPI_PID/comm 2>/dev/null; then
  snap() {
    for p in $(ls /proc | grep -E '^[0-9]+$'); do
      c=$(cat /proc/$p/comm 2>/dev/null)
      case "$c" in napi/*) echo "$p $(awk '{print $1}' /proc/$p/schedstat 2>/dev/null)";; esac
    done | sort -n
  }
  snap > /tmp/np-pre
  ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 \
    "sudo /root/e0/sportgen --dip 10.10.1.1 --dport 7777 --sport 32704 --n 150000 --proto udp --plen 64 --batch 64 --pause 500" >/dev/null
  snap > /tmp/np-post
  NAPI_PID=$(join /tmp/np-pre /tmp/np-post | awk '{d=$3-$2; if (d>max) {max=d; pid=$1}} END {print pid}')
  [ -n "$NAPI_PID" ] && echo "$NAPI_PID" > /root/p1/napi-pid-q$TQ
fi
taskset -pc $NAPI_CPU $NAPI_PID >/dev/null
echo "app_cpu=$APP_CPU napi_cpu=$NAPI_CPU napi_pid=$NAPI_PID policy=$POLICY"
