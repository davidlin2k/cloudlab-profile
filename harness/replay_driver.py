"""Replay driver: drives a forged trace through a router endpoint at
compressed wall rate; logs per-request hit metrics from the engines.

Usage: replay_driver.py <trace.jsonl> <router_url> <out.jsonl>
       [rate_mult] [concurrency] [limit]
router_url e.g. http://10.10.1.1:9101 (proxy) — requests carry
X-Session. Records usage.prompt_tokens_details.cached_tokens (the
engine's real hit) per request.
"""

import json
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

trace, url, out = sys.argv[1], sys.argv[2], sys.argv[3]
rate = float(sys.argv[4]) if len(sys.argv) > 4 else 50.0   # x wall speed
conc = int(sys.argv[5]) if len(sys.argv) > 5 else 16
limit = int(sys.argv[6]) if len(sys.argv) > 6 else 0

reqs = []
for line in open(trace):
    r = json.loads(line)
    reqs.append(r)
    if limit and len(reqs) >= limit:
        break
t0 = time.time()
lk = threading.Lock()
done = [0]


def fire(r):
    body = json.dumps({"model": "TinyLlama", "max_tokens": 4,
                       "messages": [{"role": "user",
                                     "content": r["prompt"]}]}).encode()
    req = urllib.request.Request(url + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json",
                                          "X-Session": r["session"]})
    rec = {"ts": r["ts"], "session": r["session"], "hash_ids": r["hash_ids"]}
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            u = json.loads(resp.read())["usage"]
            rec["pod"] = resp.headers.get("X-Routed-Pod", "?")
            rec["prompt_tokens"] = u["prompt_tokens"]
            rec["cached"] = u.get("prompt_tokens_details", {}).get(
                "cached_tokens", 0)
    except Exception as ex:
        rec["error"] = str(ex)[:80]
    with lk:
        rec["rt"] = round(time.time() - t0, 3)
        with open(out, "a") as f:
            f.write(json.dumps(rec) + "\n")
        done[0] += 1
        if done[0] % 100 == 0:
            print(f"{done[0]}/{len(reqs)}", flush=True)


t_start = time.time()
with ThreadPoolExecutor(max_workers=conc) as ex:
    for r in reqs:
        # schedule at compressed timestamps
        due = t_start + r["ts"] / rate
        d = due - time.time()
        if d > 0:
            time.sleep(d)
        ex.submit(fire, r)
print("driver done:", done[0], "requests")
