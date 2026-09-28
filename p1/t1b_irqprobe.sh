#!/bin/bash
IRQ=131
echo "per_cpu_count BEFORE: $(cat /sys/kernel/irq/$IRQ/per_cpu_count)"
ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no davidlin@10.10.1.10 \
  "sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 --dport 7777 --rate 10000 --secs 5 --plen 64 --core 4 > /tmp/f5.txt 2>&1 </dev/null &'"
sleep 9
echo "per_cpu_count AFTER:  $(cat /sys/kernel/irq/$IRQ/per_cpu_count)"
echo "/proc/interrupts:"
grep "i40e-enp24s0f1np1-TxRx-7" /proc/interrupts | awk -F: '{print $NF}'