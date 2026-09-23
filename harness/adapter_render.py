"""Chat-render adapter for the llm-d EPP's token-producer.

MIRRORS the llm-d-inference-sim SimpleTokenizer exactly so the EPP's
request-side block hashes land in the same keyspace as the engines'
event hashes (the sim vendors llm-d's kvblock token_processor, so the
HASH ALGORITHM matches by construction; only the token ids must match):

1. Flatten conversation: per message `role + ": " + content`,
   concatenated with no separator (sim's Message.PlainText(true)).
2. Tokenize with the sim's regex (tokens KEEP trailing whitespace):
   (\{|\}|:|,|-|\.|\?|\!|;|@|#|\$|%|\^|&|\*|\(|\)|\+|-|_|~|/|\\|>|<|\[|\]|=|"|'|\w+)(\s*)
3. id = FNV-1a-32(token string) per token (sim's fnv32).

Run on n1: python3 adapter_render.py 8100
EPP config token-producer vllm.url -> http://127.0.0.1:8100
"""

import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RE = re.compile(
    r'(\{|\}|:|,|-|\.|\?|\!|;|@|#|\$|%|\^|&|\*|\(|\)|\+|-|_|~|/|\\|>|<|'
    r'\[|\]|=|"|\'|\w+)(\s*)', re.ASCII)


def fnv32(s):
    h = 2166136261
    for b in s.encode():
        h ^= b
        h = (h * 16777619) & 0xFFFFFFFF
    return h


def flatten(convo):
    parts = []
    for m in convo or []:
        if not isinstance(m, dict):
            continue
        role = m.get("role", "")
        tool = m.get("tool_call_id") or ""
        head = f"{role}({tool}): " if tool else f"{role}: "
        c = m.get("content")
        if isinstance(c, list):
            c = " ".join(str(x.get("text", "")) if isinstance(x, dict)
                         else str(x) for x in c)
        parts.append(head + (c or ""))
    return "".join(parts)


def tokenize(text):
    return [fnv32(m.group(0)) for m in RE.finditer(text)]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        try:
            req = json.loads(body)
            convo = req.get("conversation") or []
            text = flatten(convo)
            if not text:
                text = req.get("prompt") or ""
            out = json.dumps({"token_ids": tokenize(text)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)
        except Exception as ex:
            msg = json.dumps({"error": str(ex)}).encode()
            self.send_response(400)
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8100
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()