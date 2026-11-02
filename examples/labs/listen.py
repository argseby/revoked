#!/usr/bin/env python3
"""Print every request it receives, for the labs at docs.revoked.link/labs.

    python3 listen.py [port]

Never run it where strangers can reach it for long: it prints what it's sent.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8", "replace")
        print(f"\n{self.command} {self.path}")
        request_id = self.headers.get("X-Revoked-Request")
        if request_id:
            print(f"X-Revoked-Request: {request_id}")
        if raw:
            try:
                print(json.dumps(json.loads(raw), indent=2, ensure_ascii=False))
            except ValueError:
                print(raw)
        sys.stdout.flush()
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_any

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f"Listening on http://localhost:{port}. Press Ctrl+C to stop.")
    try:
        HTTPServer(("0.0.0.0", port), Handler).serve_forever()
    except KeyboardInterrupt:
        pass
