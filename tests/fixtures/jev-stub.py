"""Local stand-in for the TypeSafe endpoint, used by the jev test suites.

Writes one line per request to the log file given as its argument, so a test
can assert both how many requests reached the API and the exact body `jev`
sent.

The endpoint path picks the answer: the default carries one of every primitive,
and each suffix in VARIANTS overrides the fields a test needs to be different.
A path ending in /fail answers 500 instead, for the error path. Pointing
JEV_ENDPOINT at a suffix is how a test chooses a judgment without the network.

Prints the port it bound to on the first line of stdout.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG_PATH = sys.argv[1]

ANSWERS = {
    "ok": {"type": "noul", "noul": 0.9},
    "drifted": {"type": "noul", "noul": 0.9},
    "risky": {"type": "noul", "noul": 0.9},
    "pasted_only": {"type": "noul", "noul": 0.05},
    "category": {
        "type": "choice",
        "choice": "C",
        "probabilities": {"A": 0.05, "B": 0.05, "C": 0.8, "D": 0.05, "E": 0.05},
        "confidence": 0.8,
    },
}

VARIANTS = {
    "/low": {"risky": {"noul": 0.02}},
    "/spread": {
        "category": {
            "choice": "A",
            "probabilities": {"A": 0.4, "B": 0.3, "C": 0.2, "D": 0.05, "E": 0.05},
            "confidence": 0.55,
        }
    },
    "/pasted": {"pasted_only": {"noul": 0.95}},
    "/steady": {"drifted": {"noul": 0.05}},
}


def answers_for(path):
    answers = json.loads(json.dumps(ANSWERS))
    for suffix, overrides in VARIANTS.items():
        if path.endswith(suffix):
            for question_id, fields in overrides.items():
                answers[question_id].update(fields)
    return answers


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

        payload = json.dumps(
            {
                "model": "jev-stub",
                "answers": answers_for(self.path),
                "usage": {"input_tokens": 1, "output_tokens": 1},
            }
        ).encode()
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
