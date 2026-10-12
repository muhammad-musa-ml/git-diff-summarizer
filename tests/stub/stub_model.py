"""Stand-in for the llamafile binary so tests never need the real model.

Understands the few flags the scripts pass: --cli -f FILE, and --server --port N.
The "summary" is built from the prompt, so tests can see what was sent.
"""
import hashlib
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def summarize(prompt: str) -> str:
    # STUB_WORDS=n makes the reply n words long (0 gives an empty reply)
    words = os.environ.get("STUB_WORDS")
    if words is not None:
        return " ".join(["word"] * int(words))
    digest = hashlib.sha256(prompt.encode()).hexdigest()[:12]
    diff_lines = sum(1 for line in prompt.splitlines() if line.startswith("diff --git"))
    cut = " truncated" if "The diff was cut" in prompt else ""
    return f"stub summary {digest}: {diff_lines} file diffs, {len(prompt)} chars{cut}."


def flag(args, name, default=None):
    if name in args:
        return args[args.index(name) + 1]
    return default


def serve(port: int) -> None:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def reply(self, code, body):
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self.reply(200, {"status": "ok"})

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            prompt = body["messages"][-1]["content"]
            if body.get("temperature") != 0:
                self.reply(400, {"error": "temperature must be 0"})
                return
            self.reply(200, {
                "choices": [{"message": {"content": summarize(prompt)}}],
                "usage": {"prompt_tokens": len(prompt) // 3, "completion_tokens": 12},
                "timings": {"prompt_ms": 1.5, "predicted_ms": 2.5},
            })

    HTTPServer(("0.0.0.0", port), Handler).serve_forever()


def main() -> None:
    args = sys.argv[1:]
    if "--server" in args:
        serve(int(flag(args, "--port", "8080")))
        return
    path = flag(args, "-f")
    if path is None:
        sys.exit("stub: -f FILE is required")
    with open(path, encoding="utf-8") as fh:
        print(summarize(fh.read()))


main()
