"""Forge text prompts that reproduce a block-hash trace's reuse
structure on REAL engines (llm-d-inference-sim / vLLM).

Each trace block id maps to a FIXED segment of text; a request's
prompt is the concatenation of its chain's segments. Identical chain
prefixes -> identical prompt prefixes -> identical cached blocks on
any engine, whatever its tokenizer/hash. Shared structure = the
trace's structure; absolute block boundaries follow the engine's own
--block-size (granularity differs, reuse structure does not).

Usage: forge_text.py <replay.jsonl> <out.jsonl> [seg_tokens]
Writes {"ts", "session", "prompt", "input_len", "hash_ids", "src"}.
"""

import json
import sys

src, dst = sys.argv[1], sys.argv[2]
SEG = int(sys.argv[3]) if len(sys.argv) > 3 else 512
segs = {}
n = 0
with open(src) as f, open(dst, "w") as out:
    for line in f:
        r = json.loads(line)
        hids = r["blocks"]
        # token budget per block: input_len / len(chain) keeps the
        # prompt's token count near the trace's real token count
        per = max(16, int(r["input_len"] / max(len(hids), 1)))
        parts = []
        for h in hids:
            t = segs.get(h)
            if t is None:
                t = " ".join(f"k{h}v{i}" for i in range(per))
                segs[h] = t
            parts.append(t)
        out.write(json.dumps({
            "ts": r["ts"],
            "session": r["session"],
            "prompt": " ".join(parts),
            "input_len": r["input_len"],
            "output_len": r["output_len"],
            "hash_ids": hids,
            "src": r["src"] + "+text",
        }) + "\n")
        n += 1
print(f"forged {n} prompts, {len(segs)} unique blocks")
