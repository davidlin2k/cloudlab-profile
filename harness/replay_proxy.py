"""Real-plane routing proxy: P1 (round-robin), P2 (bounded-load
consistent hash on session), P3 (approximate text-prefix tree).

Runs on the router host (n1) in front of the engine fleet. Each policy
is a separate process/port. Forwards OpenAI chat completions to the
chosen engine, echoes X-Routed-Pod, logs decisions to a JSONL file.

Usage: replay_proxy.py <policy> <listen_port> <pod1,pod2,...> <logfile>
       policy in {rr, bch, approx}
Env: BCH_EPS (default 1.0), APPROX_ENTRIES (default 200000)
"""

import json
import os
import sys
import threading
import time
import urllib.request
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

POLICY = sys.argv[1]
PORT = int(sys.argv[2])
PODS = [p.strip() for p in sys.argv[3].split(",") if p.strip()]
LOGF = sys.argv[4]

EPS = float(os.environ.get("BCH_EPS", "1.0"))
ENTRIES = int(os.environ.get("APPROX_ENTRIES", "200000"))

rr_i = [0]
POD_MODEL = {}   # filled from PODS spec "ip:port:model"
for _p in PODS:
    _parts = _p.split(":")
    if len(_parts) == 3:
        PODS[PODS.index(_p)] = _parts[0] + ":" + _parts[1]
        POD_MODEL[_parts[0] + ":" + _parts[1]] = _parts[2]
bch_load = [0.0] * len(PODS)
bch_last = [time.time()]
bch_h = {}
tree = OrderedDict()
tree_lock = threading.Lock()
log_lock = threading.Lock()
decisions = [0] * len(PODS)


def bch_pick(session):
    h = bch_h.setdefault(session, hash(session) & 0xFFFFFFFF)
    now = time.time()
    dt = max(1e-9, now - bch_last[0])
    bch_last[0] = now
    dec = 0.5 ** (dt / 5.0)
    for i in range(len(PODS)):
        bch_load[i] *= dec
    avg = sum(bch_load) / len(PODS)
    cap = EPS * max(avg, 1e-9)
    for k in range(25):
        e = (h + k * 2654435761) % len(PODS)
        if bch_load[e] <= cap or k == 24:
            return e
    return h % len(PODS)


def approx_pick(prompt):
    key = prompt[:2048]
    with tree_lock:
        e = tree.get(key)
        if e is not None:
            tree.move_to_end(key)
            return e
    # no exact key match: longest common prefix probe over recent keys
    best, best_len = None, 0
    for k, e in list(tree.items())[-4096:]:
        i = 0
        a, b = k, key
        m = min(len(a), len(b), 2048)
        while i < m and a[i] == b[i]:
            i += 1
        if i > best_len:
            best, best_len = e, i
    return best if best is not None else min(range(len(PODS)),
                                             key=lambda i: decisions[i])


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        session = self.headers.get("X-Session", "")
        prompt = ""
        try:
            prompt = json.loads(body)["messages"][-1]["content"][:2048]
        except Exception:
            pass
        if POLICY == "rr":
            e = rr_i[0] % len(PODS)
            rr_i[0] += 1
        elif POLICY == "bch":
            e = bch_pick(session or prompt[:64])
            bch_load[e] += 1.0
        else:
            e = approx_pick(prompt)
        decisions[e] += 1
        pod = PODS[e]
        # rewrite to the pod's served model (routers address engines)
        try:
            b = json.loads(body)
        except Exception:
            b = {}
        b["model"] = POD_MODEL.get(pod, b.get("model"))
        body = json.dumps(b).encode()
        t0 = time.time()
        req = urllib.request.Request(
            f"http://{pod}/v1/chat/completions", data=body,
            headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                out = r.read()
        except Exception as ex:
            self.send_error(502, str(ex))
            return
        with log_lock:
            with open(LOGF, "a") as f:
                f.write(json.dumps({
                    "ts": t0, "policy": POLICY, "pod": pod,
                    "session": session,
                    "latency_s": round(time.time() - t0, 4)}) + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.send_header("X-Routed-Pod", pod)
        self.end_headers()
        self.wfile.write(out)


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"{POLICY} proxy on :{PORT} -> {PODS}", flush=True)
    srv.serve_forever()
