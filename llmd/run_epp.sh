#!/bin/bash
# run_epp.sh -- launch the EPP (router under test) on n1 with the
# convergence instrument wired: OTel spans -> local otelcol -> file.
set -u
sudo mkdir -p /var/log/llmd /etc/epp
sudo install -m644 epp-config.yaml /etc/epp/config.yaml
sudo install -m644 endpoints.yaml /etc/epp/endpoints.yaml
# collector: otelcol-contrib with config otelcol.yaml (otlp grpc 4317 -> file)
if ! pgrep -x otelcol-contrib >/dev/null; then
  sudo bash -c 'nohup /opt/llmd/otelcol-contrib --config=/etc/epp/otelcol.yaml > /var/log/llmd/otelcol.log 2>&1 &'
fi
sudo pkill -x epp 2>/dev/null; sleep 1
sudo bash -c 'OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317 \
  nohup /opt/llmd/epp --config-file=/etc/epp/config.yaml \
  --pool-name=file-discovery --pool-namespace=default \
  --grpc-port=9002 --grpc-health-port=9003 --metrics-port=9090 \
  --secure-serving=false --v=9 > /var/log/llmd/epp.log 2>&1 &'
echo "wait for subscriber readiness before driving load:"
echo "  until curl -s localhost:9090/metrics | grep -q 'active_subscribers 1'; do sleep 1; done"
