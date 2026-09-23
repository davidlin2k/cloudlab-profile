"""T4: agent-shaped session trace (synthetic, labeled).

Calibrated to published agent-workload structure: long sessions of
multi-turn reuse, a stable per-agent system prompt, tool-output
appends, and a hot shared base prompt across agents (TraceLab reports
~95% of agent tokens served from cache; most reuse is within-session).
Chain caps at 64 blocks (32k tokens) for context-window realism.
Output: replay format (bs=512).
"""
import json, random, sys

rng = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 11)
N = int(sys.argv[1]) if len(sys.argv) > 1 else 60000
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/t4_replay.jsonl"
HOT = 12            # hot shared base-prompt blocks (all agents)
AGENTS = 2000
root = [9000000 + k for k in range(HOT)]
# per-agent stable preamble (predictable by session identity)
agent_head = {a: [8000000 + a * 100 + k for k in range(6)] for a in range(AGENTS)}
t = 0.0
last = {}
n = 0
with open(OUT, "w") as out:
    while n < N:
        t += rng.expovariate(25.0)          # ~25 req/s arrival
        if rng.random() < 0.97:
            a = rng.randrange(AGENTS)        # continuing agents dominate
        else:
            a = rng.randrange(AGENTS)
        sid = f"agent-{a}"
        if a in last and rng.random() < 0.9:
            chain = last[a][:]
            # tool outputs + new user turn append (fresh blocks)
            for _ in range(rng.randrange(1, 5)):
                newb = rng.randrange(2, 10)
                chain += [7000000 + a * 10000 + k for k in range(newb)]
        else:
            chain = root[:] + agent_head[a][:]
            newb = rng.randrange(2, 10)
            chain += [7000000 + a * 10000 + k for k in range(newb)]
        chain = chain[-64:]
        last[a] = chain
        out.write(json.dumps({"ts": round(t, 3), "session": sid,
            "blocks": chain, "input_len": len(chain) * 512,
            "output_len": rng.randrange(50, 400), "bs": 512,
            "src": "T4-agent-synth"}) + "\n")
        n += 1
print(f"T4: {n} requests")