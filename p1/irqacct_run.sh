#!/bin/bash
# p1/irqacct_run.sh -- C-014 / AN-007 accounting measurement on a
# c6420 pair (DR-015 Day 4).  Receiver-side script (run as root ON the
# receiver, which must be on its STOCK kernel for this measurement).
#   irqacct_run.sh <SENDER_IP> <RECEIVER_IP> <IFACE> <IRQCPU>
# The receiver is flooded at 158k pps 64 B to one steered queue for
# 60 s while perf (cycles,ref-cycles on the IRQ core) and a 1 Hz
# /proc/stat sampler run over the SAME window.  Outputs one results
# line + the raw artifacts, per AN-007 (facts only).
set -u
SENDER=${1:?sender ip}; RCIP=${2:?receiver ip}; IFACE=${3:-enp24s0f1np1}
IRQCPU=${4:-6}; Q=${Q:-7}; DUR=${DUR:-60}; RATE=${RATE:-158000}
OUT=/root/p1/irqacct
mkdir -p "$OUT"; cd "$OUT"

echo "== irqacct $(date -u +%FT%TZ) recv=$RCIP sender=$SENDER" | tee run.txt

# --- kernel facts (the C-024 criterion) ---
K=$(uname -r)
{ uname -a
  cat /proc/cmdline
  for f in /boot/config-$K /proc/config.gz; do
    case "$f" in
      *.gz) zcat "$f" 2>/dev/null;;
      *)    cat "$f" 2>/dev/null;;
    esac
  done | grep -E "IRQ_TIME_ACCOUNTING|NO_HZ_FULL|^CONFIG_HZ=|NO_HZ_IDLE|PREEMPT="
  lscpu | grep -E "^Model name|^CPU\(s\)|^Socket|^Thread|^NUMA"
  ethtool -i $IFACE | head -3
} >> run.txt 2>&1
grep -E "IRQ_TIME_ACCOUNTING|NO_HZ_FULL" run.txt || echo "config-not-found" >> run.txt

# --- steering: one FD rule to queue Q (delete-then-add = idempotent) ---
ethtool -N $IFACE delete 0 2>/dev/null
ethtool -N $IFACE flow-type udp4 dst-ip $RCIP src-ip $SENDER \
  dst-port 7777 src-port 32704 action $Q loc 0 >> run.txt 2>&1
IRQ=$(grep -E "i40e-${IFACE}-TxRx-$Q\b" /proc/interrupts | awk -F: '{print $1}' | tr -d ' ')
echo $IRQCPU > /proc/irq/$IRQ/smp_affinity_list
echo "steer: rule loc0 -> q$Q, irq $IRQ pinned to cpu $IRQCPU" >> run.txt

# --- the aligned measurement bracket ---
# The flood is normally launched here over ssh to the sender.  With
# NO_SSH=1 the caller launches the flood itself (same k5blast line)
# and passes SENT=<n> afterwards; this avoids needing the receiver's
# root key on the sender.
P0=$(ethtool -S $IFACE | awk -F: -v q="rx-$Q.packets" '$1==q{gsub(/ /,"",$2); print $2}')
awk -F, -v c=$((IRQCPU+1)) 'NR==1{print $c}' /sys/kernel/irq/$IRQ/per_cpu_count > irq0.txt
grep "^cpu$IRQCPU " /proc/stat > stat-start.txt
perf stat -C $IRQCPU -e cycles,ref-cycles -x, -o perf.csv -- sleep $((DUR + 4)) &
PERFPID=$!
sleep 2
if [ "${NO_SSH:-0}" != "1" ]; then
  ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
    "davidlin@$SENDER" \
    "sudo bash -c 'nohup /root/k2/k5blast --dip $RCIP --sip ${SENDER##*.} --sport 32704 --dport 7777 --rate $RATE --secs $DUR --plen 64 --core 4 > /tmp/flood-irqacct.txt 2>&1 </dev/null &'" \
    >> run.txt 2>&1
fi
for i in $(seq 1 $DUR); do
  grep "^cpu$IRQCPU " /proc/stat >> stat-samples.txt
  sleep 1
done
wait $PERFPID
P1=$(ethtool -S $IFACE | awk -F: -v q="rx-$Q.packets" '$1==q{gsub(/ /,"",$2); print $2}')
awk -v c=$((IRQCPU+1)) 'NR==1{print $c}' /sys/kernel/irq/$IRQ/per_cpu_count > irq1.txt
grep "^cpu$IRQCPU " /proc/stat > stat-end.txt
SENT=${SENT:-$(ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
  "davidlin@$SENDER" "tail -1 /tmp/flood-irqacct.txt" 2>/dev/null \
  | grep -oE "sent=[0-9]+" | cut -d= -f2)}

# --- the AN-007 numbers ---
BUSY_STAT=$(python3 - "$OUT" <<'EOF'
import sys
def busy(p):
    v = open(p).read().split()[1:9]
    return sum(float(x) for i, x in enumerate(v) if i not in (3, 4))  # not idle/iowait
a = busy(sys.argv[1] + "/stat-start.txt")
b = busy(sys.argv[1] + "/stat-end.txt")
print("%.2f" % (b - a))
EOF
)
PMU=$(python3 - "$OUT" <<'EOF'
import sys
cyc = ref = None
for l in open(sys.argv[1] + "/perf.csv"):
    r = l.rstrip("\n").split(",")
    if len(r) < 3:
        continue
    try:
        v = float(r[0])
    except ValueError:
        continue
    if r[2] == "cycles":
        cyc = v
    elif r[2] == "ref-cycles":
        ref = v
if not (cyc and ref):
    print("perf-parse-fail"); raise SystemExit
print("%.2f" % (cyc / ref))
EOF
)
PKTS=$((P1 - P0))
IRQD=$(python3 -c "print(int(open('$OUT/irq1.txt').read().split()[0]) - int(open('$OUT/irq0.txt').read().split()[0]))" 2>/dev/null)
echo "RESULT irqacct: pkts=$PKTS sent=${SENT:-?} irq_delta=${IRQD:-?} cpu${IRQCPU}_busy_stat_s=$BUSY_STAT pmu_busy_s=$PMU ratio=$(python3 -c "print('%.1f' % ($PMU / max(float('$BUSY_STAT'), 0.01)))" 2>/dev/null)" | tee -a run.txt
echo "RESULT irqacct: pkts=$PKTS sent=${SENT:-?} irq_delta=${IRQD:-?} cpu${IRQCPU}_busy_stat_s=$BUSY_STAT pmu_busy_s=$PMU"