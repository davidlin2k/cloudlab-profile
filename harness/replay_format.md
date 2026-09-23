# Replay format (one format for all traces)

Each request, one JSON line:

    {"ts": <float seconds since trace start>,
     "session": <str session id>,
     "blocks": [<int block hash ids, prefix-inclusive chain>],
     "input_len": <int tokens>,
     "output_len": <int tokens>,
     "bs": <int block size in tokens>,
     "src": "<trace id>"}

Rules:
- `blocks` is a PREFIX-INCLUSIVE chain: blocks[i] identifies the token
  prefix [0..(i+1)*bs). Equal ids anywhere = same token prefix. This is
  Mooncake's remapped hash_ids convention and the harness's only cache
  model.
- A request reuses exactly the cached prefix: walk the chain while the
  engine holds that block id; the first missing block ends reuse.
- Sessions: for traces without session ids (BurstGPT), sessions are
  SYNTHESIZED (documented per normalizer); Mooncake sessions = root
  block id (hash chains share the root within a conversation).
- Synthetic structure is always labeled in "src" and in the trace
  file name; no synthetic trace is ever presented as real.
