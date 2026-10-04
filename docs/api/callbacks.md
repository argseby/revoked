# Request callbacks

A request can name a **callback URL**. Every time a responder submits — or
updates — a response, the server POSTs the submission to that URL. Callbacks
are how a request feeds an external system (a CRM, a script, a spreadsheet
importer) without anything polling the API.

Callbacks exist on **requests only**. Shares have no callback; their data is
pulled, not pushed.

Besides submissions, a callback receives [grant events](#grant-events): a
note that an answer was revoked, changed or expired, without its values.

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
- **At-most-once, no retries** for submissions. Any transport error,
  timeout, or a response status ≥ 400 marks the delivery failed. Answer with
  a 2xx quickly and do your processing after responding. Grant events are
  retried; see below.
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
| `identity` | The responder's identity id, **only if it was cryptographically proven** by a handshake. A merely claimed identity is dropped, never delivered. Empty when the request did not require a handshake. |
| `identifier` | The identifier the responder entered, when the request requires one. |
| `senderName` | The free-text name the responder typed. Unverified — display data, not an identity. |
| `data` | Key → value map of the fields the responder **typed directly**. |

**`data` does not contain vault-linked fields.** When a responder links a
field to a record in their own vault, the response stores a living grant that
resolves at read time — the whole point is that the value is *not* copied
around. Those fields are absent from the callback payload; fetch the response
through the API (or the app) to see grants resolved to their current values.

### Answers kept on another server

A responder whose account is on another Revoked server answers through that
server, and the answer stays in their vault there. The submission callback
then carries one more field, `server`, naming the responder's server, and
`data` holds the values as this server read them from there at the moment
of submission. `identity` is the identity's fingerprint rather than an id,
since the identity is registered on the other server.

## Grant events

An answer is a living grant, so it can change after it was submitted: the
responder edits the entry behind it, pauses or revokes it, deletes the
entry, or the grant reaches its expiry. Each of these is delivered to the
callback as an event:

```json
{
  "event": "grant.revoked",
  "requestId": "lxt7nlkvfqairg5",
  "slug": "vendor-onboarding",
  "responseId": "9k2m4pqx81zvwy3",
  "linkId": "9k2m4pqx81zvwy3",
  "status": "revoked",
  "at": "2026-10-02T09:14:03Z"
}
```

| `event` | Sent when |
|---|---|
| `grant.changed` | An entry the answer resolves changed value, directly or through an alias, or the answer was paused, resumed, or answered again with different entries. `status` says which state it is in now. |
| `grant.revoked` | The responder revoked the answer, deleted it, or deleted the last entry behind it. |
| `grant.expired` | The answer reached its expiry or view cap. |

An event never carries a value. When the current value matters, it is read
through `GET /api/requests/{id}/links`, which resolves every answer at the
moment of the call. For an answer kept on another server, the event also
carries `server`, and it reaches this server first as a signed event from
that server (`POST /api/grants/events`), which is checked against that
server's DNS-pinned root key before anything is passed on.

Unlike submissions, events are **retried**: a transport error, a timeout,
`408`, `429` or a `5xx` is tried again after 30 seconds, then after doubling
intervals up to six hours, for about a day and a half in total. Any other
`4xx` ends the delivery at once. An event can therefore arrive more than
once, and late; `responseId` together with `at` identifies it, and an event
older than one already processed for the same `responseId` can be ignored.

A payload with `event` set is an event; a payload without it is a
submission.

## Failures

A failed delivery emits an in-app notification (`callback_failed`) to the
request's owner, naming the request and the reason — a blocked URL, a timeout,
or the status your endpoint returned. A submission is not retried; after the
endpoint is fixed, the responder can re-submit, or the response can be read
through the API. A grant event raises the notification only once its retries
are used up.

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

## Testing the URL

The request editor has a **Send test payload** button under the callback field.
It posts one sample delivery and tells you what came back — a status, a refusal,
or a timeout — so a wrong URL surfaces while you are still typing it rather than
on the first real submission.

The send happens **on the server**, through the client a real delivery uses, so
the result answers the question that matters: can *this host* reach that URL
under the policy above. It is `POST /api/requests/callback-test` if you want it
from a script.

The sample has the shape of a real payload with obviously fake values, plus one
extra field:

```json
{ "...": "...", "test": true }
```

Branch on `test` so an example never lands in a CRM as a real answer. While the
request is unsaved the id and slug are placeholders; once it exists they are the
real ones, and `X-Revoked-Request` carries the real request id.

A failure comes back as a `code`, because all three otherwise read as "not
found" and each has a different fix:

| `code` | Means | Fix |
|---|---|---|
| `blocked` | The policy above refuses the address. | `ALLOW_PRIVATE_CALLBACKS=true` for a loopback or LAN hook. |
| `unreachable` | Nothing answered — refused, DNS, or timeout. | Check the host and port from *the server's* network, not yours. |
| `status` | The hook answered 4xx/5xx. | Its own logs. n8n answers 404 on a `/webhook-test/` URL unless the editor is listening, and on a production URL unless the workflow is active. |

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
