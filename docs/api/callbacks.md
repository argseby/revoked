# Request callbacks

A request can name a **callback URL**. Every time a responder submits — or
updates — a response, the server POSTs the submission to that URL. Callbacks
are how a request feeds an external system (a CRM, a script, a spreadsheet
importer) without anything polling the API.

Callbacks exist on **requests only**. Shares have no callback; their data is
pulled, not pushed.

## Configuring

Set the callback when creating or editing a request (the `callbackUrl` field,
under *Limits & callback* in the app). The URL is validated at save time, so a
bad target fails the save rather than failing silently at delivery:

- It must be an **absolute** `http://` or `https://` URL. A bare
  `127.0.0.1:8000` is rejected as unparsable — the scheme and (ideally) a path
  are required: `http://127.0.0.1:8000/hook`.
- Loopback, private-range and other internal addresses are **refused by
  default**. A user-supplied URL the server fetches is a server-side request
  forgery primitive; see [Security](#security) for the policy and the opt-out.

A rejected URL surfaces as the error code `validation_callback_url_blocked`,
with the reason in the message.

## Delivery

- `POST`, `Content-Type: application/json`.
- One extra header: `X-Revoked-Request: <requestId>` — match it against the
  request id you configured the callback for.
- Delivered from a background goroutine; the responder never waits on it.
- Bounded at **10 seconds** total. Redirects are **not followed** — a redirect
  is treated as delivery to a different host and refused.
- **At-most-once, no retries.** Any transport error, timeout, or a response
  status ≥ 400 marks the delivery failed. Answer with a 2xx quickly and do
  your processing after responding.
- Fires for **new and updated** responses alike. The payload does not carry a
  new-vs-update flag; if the distinction matters, key on `responseId` — an
  update re-delivers the same id.

## Payload

```json
{
  "requestId": "lxt7nlkvfqairg5",
  "slug": "vendor-onboarding",
  "responseId": "9k2m4pqx81zvwy3",
  "linkId": "9k2m4pqx81zvwy3",
  "identity": "wt27a6nyfx93u3w",
  "identifier": "customer-4711",
  "senderName": "Ada Lovelace",
  "data": {
    "email": "ada@example.com",
    "phone": "+44 20 7946 0000"
  }
}
```

| Field | Meaning |
|---|---|
| `requestId` | The request this response answers. |
| `slug` | The request's public slug. |
| `responseId` | The response link's id. Stable across updates by the same responder. |
| `linkId` | Same value as `responseId` (legacy alias — responses *are* links). |
| `identity` | The responder's identity id, **only if it was cryptographically proven** by a handshake. A merely claimed identity is dropped, never delivered. Empty for guests. |
| `identifier` | The identifier the responder entered, when the request requires one. |
| `senderName` | The free-text name the responder typed. Unverified — display data, not an identity. |
| `data` | Key → value map of the fields the responder **typed directly**. |

**`data` does not contain vault-linked fields.** When a responder links a
field to a record in their own vault, the response stores a living grant that
resolves at read time — the whole point is that the value is *not* copied
around. Those fields are absent from the callback payload; fetch the response
through the API (or the app) to see grants resolved to their current values.

## Failures

A failed delivery emits an in-app notification (`callback_failed`) to the
request's owner, naming the request and the reason — a blocked URL, a timeout,
or the status your endpoint returned. There is no automatic retry; fix the
endpoint and ask the responder to re-submit, or read the response through the
API.

## Security

Two directions to think about.

**What the server will deliver to (SSRF policy).** The callback URL is
attacker-influenced input this server fetches itself, so it goes through a
hardened client: the URL is validated at save, redirects are refused, and the
**resolved IP is re-checked at connect time** — validating only the hostname
loses to DNS rebinding. Blocked by default: loopback, private ranges
(10/8, 172.16/12, 192.168/16, fc00::/7), link-local (including the
169.254.169.254 cloud-metadata endpoint), multicast and 0.0.0.0.

For LAN-only installs and local development, set

```
ALLOW_PRIVATE_CALLBACKS=true
```

in the **server's** environment. That opens loopback and the private ranges.
Link-local, multicast and 0.0.0.0 stay blocked regardless — no legitimate
callback lives there on any deployment. Leave the flag off on anything
public-facing.

**What your endpoint should trust.** Deliveries are currently **not signed**:
anyone who learns your callback URL can POST a payload of the same shape.
Treat the URL itself as a secret — include an unguessable path segment
(`/hook/f3a9c1…`), serve it over `https`, and check `X-Revoked-Request`
against the request id you expect. For anything security-relevant, verify the
data through the API rather than trusting the pushed payload; the `identity`
field is only as trustworthy as your confidence the payload really came from
your server.

## Testing locally

The repo root has a throwaway listener:

```
python run.py            # listens on http://0.0.0.0:8000/hook
python run.py 9000 spy   # http://0.0.0.0:9000/spy
```

It prints every delivery (headers, pretty-printed JSON body) and answers 404
with a hint for a wrong path. Point the request's callback at
`http://127.0.0.1:8000/hook`, run the server with
`ALLOW_PRIVATE_CALLBACKS=true`, submit a response to the request's public
link, and the payload appears in the terminal.

If the server runs in Docker, `127.0.0.1` is the container itself — use
`http://host.docker.internal:8000/hook` to reach a listener on the host.
