#!/bin/bash
# run_sims.sh -- launch the sim fleet on an engine node (n3/n4/n5).
# Usage: run_sims.sh <node_ip> <node_shortname> [pods] [kv_blocks] [epp_ip]
# node_shortname is tx1|tx2|tx3 (clnode323|386|322); pods default 2.
set -u
IP=${1:?node ip}; SHORT=${2:?tx1|tx2|tx3}; N=${3:-2}; BLOCKS=${4:-256}; EPP=${5:-10.10.1.1}
sudo mkdir -p /var/log/llmd
for pod in $(seq 0 $((N-1))); do
  PORT=$((8000+pod))
  sudo bash -c "POD_IP=$IP POD_NAME=sim-$SHORT-$pod \
    KV_EVENT_LOG=/var/log/llmd/events-$SHORT-$pod.jsonl \
    nohup /opt/llmd/llm-d-inference-sim \
    --model TinyLlama-$SHORT-$pod --served-model-name TinyLlama-$SHORT-$pod \
    --port $PORT --mode random --force-dummy-tokenizer \
    --enable-kvcache --kv-cache-size $BLOCKS --block-size 16 \
    --zmq-endpoint tcp://$EPP:5557 --event-batch-size 16 \
    > /var/log/llmd/sim-$SHORT-$pod.log 2>&1 &"
done
sleep 2
pgrep -c -f "llm-d-inference-sim" && echo "sims up on $SHORT"
