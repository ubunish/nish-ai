"""Local stand-in for the TypeSafe endpoint, used by tests/jev.sh.

Writes one line per request to the log file given as its argument, so a test
can assert both how many requests reached the API and the exact body `jev`
sent. A request whose path ends in /fail answers 500, which exercises the
error path without touching the network.

Prints the port it bound to on the first line of stdout.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG_PATH = sys.argv[1]
ANSWER = {
    "model": "jev-stub",
    "answers": {
        "ok": {"type": "noul", "noul": 0.9},
        # A canned Choice, so a caller that ranks or routes has something with
        # a distribution and a confidence to read.
        "category": {
            "type": "choice",
            "choice": "C",
            "probabilities": {"A": 0.05, "B": 0.05, "C": 0.8, "D": 0.05, "E": 0.05},
            "confidence": 0.8,
        },
    },
    "usage": {"input_tokens": 1, "output_tokens": 1},
}


class StubHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", "replace")
        with open(LOG_PATH, "a", encoding="utf-8") as log:
            log.write(body.replace("\n", " ") + "\n")

        if self.path.endswith("/fail"):
            self.send_response(500)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        payload = json.dumps(ANSWER).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        """Silence the default stderr access log; the test owns the output."""


server = HTTPServer(("127.0.0.1", 0), StubHandler)
print(server.server_port, flush=True)
server.serve_forever()
