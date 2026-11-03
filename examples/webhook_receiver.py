#!/usr/bin/env python3
"""Receive Revoked webhooks on this machine, check them, and hand each event
to handle() below, which prints it with a link to what it means.

    python examples/webhook_receiver.py                 # 127.0.0.1:47381
    python examples/webhook_receiver.py --port 9000
    REVOKED_WEBHOOK_SECRET=whsec_... python examples/webhook_receiver.py

Point a webhook endpoint at http://127.0.0.1:47381/ in the app. The server
refuses loopback addresses unless it runs with ALLOW_PRIVATE_CALLBACKS=true,
so start your local server that way for this to receive anything. Without a
secret every delivery is printed unchecked, with a warning.

What arrives, and how to answer it:
  payload        https://docs.revoked.link/api/webhooks/#what-an-event-carries
  event types    https://docs.revoked.link/api/webhooks/#event-types
  signature      https://docs.revoked.link/api/webhooks/#verifying-the-signature
  retries        https://docs.revoked.link/api/webhooks/#delivery

Only the standard library is used.
"""

import argparse
import collections
import hashlib
import hmac
import json
import os
import sys
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_PORT = 47381
TOLERANCE_SECONDS = 300
MAX_BODY_BYTES = 1 << 20

DOCS = "https://docs.revoked.link/api"

# What `data` holds for each kind of event, and where the API reference
# describes the object it names. An event never carries a value: read what
# you need through the API with an API key.
OBJECTS = {
    "link": ("id, status, kind (share or answer), request for an answer", f"{DOCS}/reference/shares/"),
    "request": ("id, status, deleted if it was deleted", f"{DOCS}/reference/requests/"),
    "response": ("id of the answer, request, status, server if kept elsewhere", f"{DOCS}/reference/grants/"),
    "record": ("id, key", f"{DOCS}/reference/vault/"),
    "attestation": ("id, type, status", f"{DOCS}/reference/attestations/"),
    "identity": ("id, fingerprint, status", f"{DOCS}/reference/identity/"),
    "member": ("id, user, permissions", f"{DOCS}/reference/workspaces/"),
    "apikey": ("id, user", f"{DOCS}/authentication/#api-keys"),
    "connection": ("id, clientId", f"{DOCS}/reference/connections/"),
}


class Refused(Exception):
    """A delivery this receiver turns away, with the status it answers."""

    def __init__(self, status, reason):
        super().__init__(reason)
        self.status = status
        self.reason = reason


def verify(secret, header, body):
    """HMAC-SHA256 over "{t}.{body}", as in the signature docs. After a secret
    rotation the header holds two v1 values for a day; either may match."""
    if not header:
        raise Refused(401, "no Revoked-Signature header")
    parts = [p.split("=", 1) for p in header.split(",") if "=" in p]
    stamps = [v for k, v in parts if k == "t"]
    if not stamps or not stamps[0].isdigit():
        raise Refused(401, "the signature has no timestamp")
    if abs(time.time() - int(stamps[0])) > TOLERANCE_SECONDS:
        raise Refused(401, "the signature is more than five minutes old")
    expected = hmac.new(secret.encode(), f"{stamps[0]}.".encode() + body, hashlib.sha256).hexdigest()
    if not any(hmac.compare_digest(expected, v) for k, v in parts if k == "v1"):
        raise Refused(401, "the signature doesn't match: check the endpoint's signing secret")


def handle(event):
    """Your code goes here. This one prints the event and where it is
    explained. It runs after the delivery was answered, so it may take its
    time; an exception here is logged, and the event can be replayed from the
    app."""
    kind = event["type"].split(".", 1)[0]
    fields, reference = OBJECTS.get(kind, ("see the event types table", f"{DOCS}/webhooks/#event-types"))
    test = "  (test event)" if event.get("test") else ""
    print(f"\n> {time.strftime('%H:%M:%S')} {event['type']} {event['id']}{test}", flush=True)
    print(json.dumps(event, indent=2), flush=True)
    print(f"  data holds: {fields}", flush=True)
    print(f"  about it:   {reference}", flush=True)


class Receiver(BaseHTTPRequestHandler):
    secret = ""
    # Every delivery of an event carries the same id; a retry or a replay must
    # not be handled twice. The last thousand are enough for a demo.
    seen = collections.deque(maxlen=1000)

    def _answer(self, status, reason=""):
        self.send_response(status)
        if status == 405:
            self.send_header("Allow", "POST")
        self.end_headers()
        if reason:
            print(f"! {status}: {reason}", file=sys.stderr, flush=True)

    def _read(self):
        if "json" not in self.headers.get("Content-Type", ""):
            raise Refused(415, "expected Content-Type: application/json")
        length = self.headers.get("Content-Length")
        if length is None:
            raise Refused(411, "no Content-Length")
        if not length.isdigit():
            raise Refused(400, "Content-Length isn't a number")
        if int(length) > MAX_BODY_BYTES:
            raise Refused(413, "the body is larger than this receiver accepts")
        return self.rfile.read(int(length))

    def do_POST(self):
        try:
            body = self._read()
            if self.secret:
                verify(self.secret, self.headers.get("Revoked-Signature", ""), body)
            try:
                event = json.loads(body)
            except ValueError:
                raise Refused(400, "the body isn't JSON")
            if not isinstance(event, dict) or not event.get("id") or not event.get("type"):
                raise Refused(400, f"not an event: see {DOCS}/webhooks/#what-an-event-carries")
        except Refused as refused:
            # Anything but a 2xx is retried, so a delivery refused here comes
            # back: fix the cause and it goes through on the next try.
            self._answer(refused.status, refused.reason)
            return
        except Exception:
            self._answer(500, "the receiver failed before checking the delivery")
            traceback.print_exc()
            return

        # Answer first: the server gives each attempt ten seconds.
        self._answer(204)

        if event["id"] in self.seen:
            print(f"= {event['id']} again, already handled", flush=True)
            return
        self.seen.append(event["id"])
        if not self.secret:
            print("! unchecked: set REVOKED_WEBHOOK_SECRET to verify deliveries", file=sys.stderr, flush=True)
        try:
            handle(event)
        except Exception:
            print(f"! handling {event['id']} failed; replay it from the app once fixed:", file=sys.stderr, flush=True)
            traceback.print_exc()

    def do_GET(self):
        self._answer(405, "webhooks arrive as POST")

    do_PUT = do_PATCH = do_DELETE = do_GET

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1", help="address to listen on (default 127.0.0.1)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"port to listen on (default {DEFAULT_PORT})")
    args = parser.parse_args()

    Receiver.secret = os.environ.get("REVOKED_WEBHOOK_SECRET", "").strip()
    if not Receiver.secret:
        print("! no REVOKED_WEBHOOK_SECRET set: deliveries are printed without checking their signature",
              file=sys.stderr, flush=True)

    try:
        server = ThreadingHTTPServer((args.host, args.port), Receiver)
    except OSError as err:
        sys.exit(f"Can't listen on {args.host}:{args.port}: {err.strerror}. Try another --port.")
    print(f"Listening on http://{args.host}:{args.port}/  (Ctrl+C to stop)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
