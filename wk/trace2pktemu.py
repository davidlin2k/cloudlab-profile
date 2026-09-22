#!/usr/bin/env python3
"""trace2pktemu.py -- Mooncake/AgentX request traces -> pktemu replay traces.

Input: the FAST'25 JSONL traces (timestamp ms, input_length, output_length,
hash_ids at 512-token blocks), one or more files concatenated in time order.

Output: lines "<t_ns> <npkt> <flow_id> <class>" sorted by t, where
  class 0 = KV pull chunk (store -> decode host, the receive load)
  class 1 = KV push chunk (prefill -> store, first-seen blocks only)
  class 2 = control / agentic short call
and flow ids are disjoint families: pulls round-robin over --store-flows,
pushes over --prefill-flows, control over --agent-flows.

Model (matches Mooncake's architecture, FINDINGS.md W-AI):
  per-request KV bytes = input_length x --kv-per-token;
  blocks whose hash_id was seen earlier = cache hit -> the pull still
  happens (decode reads from the KVCache store), but only first-seen
  blocks generate a prefill->store push;
  both directions stream as layer-wise chunks, log-uniform in
  [--chunk-min, --chunk-max], one message per chunk (one flow each, the
  parallel streams of a chunked transfer).

Time: --time-scale stretches gaps (1.0 = production pace); --window-seconds
bounds the emitted span; --max-messages bounds the replay size. The tool
prints the implied offered bandwidth for every run so a target load
fraction is chosen from numbers, not hope.
"""
import argparse, json, math, random, sys

DEFAULTS = dict(kv_per_token=65536, chunk_min=262144, chunk_max=8388608,
                store_flows=32, prefill_flows=32, agent_flows=8,
                control_per_request=2, max_messages=900000,
                window_seconds=None, time_scale=1.0, seed=42)

def chunk_sizes(rng, total, cmin, cmax):
    """Log-uniform chunks summing to ~total bytes."""
    out, remain = [], total
    while remain > 0:
        c = min(remain, int(math.exp(math.log(cmin) +
              rng.random() * (math.log(cmax) - math.log(cmin)))))
        out.append(c)
        remain -= c
    return out

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("traces", nargs="+", help="JSONL trace files, in time order")
    p.add_argument("--out", required=True)
    p.add_argument("--kv-per-token", type=int, default=DEFAULTS["kv_per_token"])
    p.add_argument("--chunk-min", type=int, default=DEFAULTS["chunk_min"])
    p.add_argument("--chunk-max", type=int, default=DEFAULTS["chunk_max"])
    p.add_argument("--store-flows", type=int, default=DEFAULTS["store_flows"])
    p.add_argument("--prefill-flows", type=int, default=DEFAULTS["prefill_flows"])
    p.add_argument("--agent-flows", type=int, default=DEFAULTS["agent_flows"])
    p.add_argument("--control-per-request", type=int,
                   default=DEFAULTS["control_per_request"])
    p.add_argument("--max-messages", type=int, default=DEFAULTS["max_messages"])
    p.add_argument("--window-seconds", type=float,
                   default=DEFAULTS["window_seconds"])
    p.add_argument("--time-scale", type=float, default=DEFAULTS["time_scale"])
    p.add_argument("--seed", type=int, default=DEFAULTS["seed"])
    a = p.parse_args()

    rng = random.Random(a.seed)
    nflows = a.store_flows + a.prefill_flows + a.agent_flows
    sflow = lambda i: i % a.store_flows
    pflow = lambda i: a.store_flows + (i % a.prefill_flows)
    aflow = lambda i: a.store_flows + a.prefill_flows + (i % a.agent_flows)

    rows = []
    for path in a.traces:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    rows.append(json.loads(line))
    rows.sort(key=lambda r: r["timestamp"])
    if a.window_seconds is not None:
        t0 = rows[0]["timestamp"]
        rows = [r for r in rows if r["timestamp"] - t0 <= a.window_seconds * 1000]
    if not rows:
        sys.exit("no rows in window")

    seen = set()
    msgs, reqs, pull_b, push_b, ctrl_b = [], 0, 0, 0, 0
    for r in rows:
        reqs += 1
        kv = r["input_length"] * a.kv_per_token
        blocks = r["hash_ids"]
        hit = sum(1 for h in blocks if h in seen)
        for h in blocks:
            seen.add(h)
        miss_bytes = int(kv * (len(blocks) - hit) / max(len(blocks), 1))
        hit_bytes = kv - miss_bytes

        mid_t = int((r["timestamp"] - rows[0]["timestamp"]) * 1e6 * a.time_scale)
        for i, c in enumerate(chunk_sizes(rng, hit_bytes, a.chunk_min, a.chunk_max)):
            msgs.append((mid_t, c, sflow(i), 0)); pull_b += c
        for i, c in enumerate(chunk_sizes(rng, miss_bytes, a.chunk_min, a.chunk_max)):
            msgs.append((mid_t, c, pflow(i), 1)); push_b += c
        for i in range(a.control_per_request):
            msgs.append((mid_t + (i + 1) * 1000,
                         1 + (rng.random() < 0.25), aflow(i), 2))
            ctrl_b += 1500
        if len(msgs) >= a.max_messages:
            break
    msgs = msgs[:a.max_messages]
    msgs.sort(key=lambda m: (m[0], m[3]))
    span_s = (msgs[-1][0] - msgs[0][0]) / 1e9 if len(msgs) > 1 else 0
    total = pull_b + push_b + ctrl_b
    gbps = total * 8 / span_s / 1e9 if span_s > 0 else 0.0
    with open(a.out, "w") as f:
        for t, c, fl, cls in msgs:
            f.write(f"{t} {-(-c // 1500)} {fl} {cls}\n")
    print(f"trace2pktemu: {a.out}")
    print(f"  requests={reqs} messages={len(msgs)} "
          f"window={span_s:.0f}s (scale {a.time_scale})")
    print(f"  bytes: pull={pull_b/1e9:.2f}GB push={push_b/1e9:.2f}GB "
          f"control={ctrl_b/1e6:.0f}MB")
    print(f"  implied offered bandwidth: {gbps:.1f} Gbps "
          f"({gbps/100:.2f} of a 100G line)")
    print(f"  flows: {nflows} (store {a.store_flows}, prefill "
          f"{a.prefill_flows}, agent {a.agent_flows}) -> run pktemu "
          f"--flows>={nflows}")
    if len(msgs) >= a.max_messages:
        print(f"  NOTE: message budget hit at request {reqs} -- the window "
              f"is a prefix of the trace span")

if __name__ == "__main__":
    main()
