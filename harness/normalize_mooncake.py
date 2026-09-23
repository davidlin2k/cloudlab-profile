"""Normalize the Mooncake FAST25 trace (T1, real, block-hashed).

Sessions: hash chains are prefix-inclusive, so the FIRST block id is
the conversation root — requests sharing root = same session. Emit the
standard replay format.
"""

import json
import sys

src, dst = sys.argv[1], sys.argv[2]
t0 = None
n = 0
with open(src) as f, open(dst, "w") as out:
    for line in f:
        r = json.loads(line)
        ts = r["timestamp"] / 1000.0
        if t0 is None:
            t0 = ts
        hids = r["hash_ids"]
        if not hids:
            continue
        out.write(json.dumps({
            "ts": round(ts - t0, 3),
            "session": str(hids[0]),
            "blocks": hids,
            "input_len": r["input_length"],
            "output_len": r["output_length"],
            "bs": 512,
            "src": "T1-mooncake",
        }) + "\n")
        n += 1
print(f"mooncake normalized: {n} requests")
