# Revoked

Revoked replaces stale copies of data with a reference that resolves its
current value at read time and stops working the moment you revoke it.
Recipients hold a link, never your data — so what they see is always current
and never leaves your control.

## The one idea

Everything in Revoked is a **living grant**:

- A **share** resolves the record's *current* value on every read. Rotate a
  secret and every share pointing at it updates; there is no republish step.
- Revocation is **instant**. Pause or revoke a grant and the next read is
  refused — not the next sync.
- Both sides can **prove who is asking**. Every share and request is bound to
  a cryptographic identity anchored in the sender's DNS, so a claim of
  "this came from example.com" is checkable, not decorative.

## Where to go

| You want to | Start at |
|---|---|
| Run your own server, or install the app | [Installation](installation/index.md) |
| Use the app — keep a vault, share secrets, collect data | [Guide](guide/index.md) |
| Script against the HTTP API or integrate a system | [Developer API](api/index.md) |

There is no hosted instance: you run the server, and the whole trust chain —
data, keys and domain — stays under your own control. The app connects to
whichever server you point it at.
