# CloudLab profile kit -- one entry point for the whole experiment program.
# Variables:
#   RX   receiver IP   (default 10.10.1.1)
#   TXS  sender IPs    (default tx0..tx4)
# Examples:
#   make deploy                      # provision all 6 nodes (clone+build)
#   make e0 SENDER=10.10.1.10        # K1 actuation gate (on rx, via ssh)
#   make k2  SENDER=10.10.1.10       # K2 DDIO causality (on rx, via ssh)
#   make load / make status / make unload
#   make trace                        # regenerate the replay trace from
#                                     # the real Mooncake/AgentX JSONLs

RX ?= 10.10.1.1
TXS ?= 10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13 10.10.1.14
NODES = $(RX) $(TXS)
SSH = ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10
TRACE_SRC ?= /tmp/toolagent_trace.jsonl /tmp/conversation_trace.jsonl

.PHONY: deploy e0 k2 load unload status trace trace-matrix clean

deploy:
	./deploy.sh $(NODES)

e0:
	$(SSH) root@$(RX) 'cd /root/e0 && ./e0_gate.sh --sender $(SENDER)'

k2:
	$(SSH) root@$(RX) 'cd /root/k2 && ./k2_ddio.sh $(SENDER)'

load:
	./homa-ctl.sh $(NODES) load
unload:
	./homa-ctl.sh $(NODES) unload
status:
	./homa-ctl.sh $(NODES) status

trace: wk/wai_full.trace

wk/wai_full.trace: wk/trace2pktemu.py $(TRACE_SRC)
	cd wk && python3 trace2pktemu.py $(TRACE_SRC) --out wai_full.trace --time-scale 1.0

trace-matrix: wk/wai_full.trace
	cd wk && ./run_trace.sh wk/wai_full.trace 3

clean:
	rm -f e0/sportgen k2/k2_rx wk/wai_full.trace wk/*.cdf
