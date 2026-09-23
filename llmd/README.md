# llm-d six-node bring-up (convergence instrument)

Production router under test on CPU-only CloudLab nodes. No Kubernetes:
EPP as a native binary with file-discovery, KV indexer in centralized
(static-endpoint) mode, engines publish ZMQ events to it.

## Layout

| Node | Host | IP | Role |
| --- | --- | --- | --- |
| n1 | clnode366 | 10.10.1.1 | router host under test: EPP + KV indexer (binds tcp://0.0.0.0:5557) |
| n2 | clnode337 | 10.10.1.10 | second router replica (later) |
| n3 | clnode323 | 10.10.1.11 | engine fleet (2 sim pods, ports 8000-8001) |
| n4 | clnode386 | 10.10.1.12 | engine fleet (2 sim pods) |
| n5 | clnode322 | 10.10.1.13 | engine fleet (2 sim pods) |
| n6 | clnode331 | 10.10.1.14 | clients, render service, ground truth, PTP |

PTP: n1 is grand master (chrony disciplines its CLOCK_REALTIME from NTP;
phc2sys glues the NIC PHC to CLOCK_REALTIME). Slaves: ptp4l -2 -H
--step_threshold=1 syncs PHC to the GM; phc2sys -s enp195s0np0 -c
CLOCK_REALTIME -S 1 -O 0 steps CLOCK_REALTIME onto the PHC.

## Build (per node)

    # Go 1.25.4 in /usr/local/go on n1, n3-n5
    git clone https://github.com/llm-d/llm-d-router.git        # n1
    cd llm-d-router && CGO_ENABLED=0 go build -o /opt/llmd/epp ./cmd/epp
    git clone https://github.com/llm-d/llm-d-inference-sim.git # n3-n5
    cd llm-d-inference-sim && git apply llmd/sim-eventlog.patch
    CGO_ENABLED=0 go build -o /opt/llmd/llm-d-inference-sim cmd/llm-d-inference-sim/main.go

## Run

    # n1 (config: epp-config.yaml, endpoints: endpoints.yaml, 6 sims)
    sudo bash -c 'OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317 \
      nohup /opt/llmd/epp --config-file=/etc/epp/config.yaml \
      --pool-name=file-discovery --pool-namespace=default \
      --grpc-port=9002 --grpc-health-port=9003 --metrics-port=9090 \
      --secure-serving=false --v=9 > /var/log/llmd/epp.log 2>&1 &'
    # otelcol-contrib on 127.0.0.1:4317 -> /var/log/llmd/spans.json

    # n3-n5, per pod (POD_NAME sim-txX-Y, distinct --model per pod for pairing)
    POD_IP=<node ip> POD_NAME=sim-tx1-0 KV_EVENT_LOG=/var/log/llmd/events-tx1-0.jsonl \
      nohup /opt/llmd/llm-d-inference-sim \
      --model TinyLlama-tx1-0 --served-model-name TinyLlama-tx1-0 \
      --port 8000 --mode random --force-dummy-tokenizer \
      --enable-kvcache --kv-cache-size 256 --block-size 16 \
      --zmq-endpoint tcp://10.10.1.1:5557 --event-batch-size 16 \
      > /var/log/llmd/sim-tx1-0.log 2>&1 &

## Convergence instrument

- Engine side: the sim's publisher (sim-eventlog.patch) appends
  {"wall_ns", "seq", "topic", "bytes"} to KV_EVENT_LOG just before the
  socket send. Seq is per-publisher monotonic (gap detection free).
- Router side (UNMODIFIED llm-d): kvEventsConfig.tracing=true emits
  events_receive / events_decode / events_process spans with
  llm_d.kv_cache_events.sequence attributes to OTLP 127.0.0.1:4317
  (otelcol-contrib file exporter). --v=9 also logs "Processing event
  batch" (podID, modelName, eventCount) with ns timestamps.
- Convergence L = events_process.start - engine wall_ns (PTP-synced clocks).
- Pairing: per (topic-derived pod, publisher order); the pool preserves
  per-source order, so the Nth batch for a topic pairs with the Nth
  applied batch for that pod.

## Lessons (do not relearn)

1. **The 36.8 s clock offset.** A fixed L of ~36.8 s was CLOCK SKEW, not
   pipeline delay: engine nodes' CLOCK_REALTIME sat ~35 s behind UTC
   while their PHCs were synced. Every cross-node timestamp comparison
   must first pass a clock sanity check (date deltas << measurement
   resolution). phc2sys without -w/-O dies with usage text; -S is the
   step threshold; ptp4l needs --step_threshold or it slews forever.
2. **PUB drops with no subscriber.** Events published before the EPP's
   subscriber binds are silently dropped (ZMQ PUB semantics). The
   driver must wait for llm_d_epp_kv_cache_events_active_subscribers==1
   before driving load.
3. **EPP startup is slow (~40 s)** before the subscriber binds
   (plugin/index init). Gate on the metric, not on pgrep.
4. Strict config decoding: file-discovery goes under
   dataLayer.discovery.endpoints.pluginRef; kvEventsConfig.tracing is
   the span opt-in; tracing init happens before plugin instantiation.
5. EPP-internal event handling is ~200 us idle (span-verified). The
   wire->apply path is sub-ms. What remains for storms is queueing
   under load — the actual subject.

## Verified idle-path numbers (2026-09-23)

- publish -> applied: L = 342 us (one request, seq 5, 2-block batch)
- events_receive -> events_process end: ~200 us inside the EPP
- NIC->socket: no loss at 150k pps offered (rx0 delta = offered)
