# Webhooks

A webhook tells your server the moment something happens in a workspace: a
share was revoked, a request was answered, a member left. You register an
address once, pick the events it should hear, and every event is POSTed to it,
signed, retried until it lands, and logged so you can see and resend what was
sent.

Webhooks belong to a **workspace**, not to a single request. The older
per-request [callback URL](callbacks.md) keeps working and is unaffected; for
new integrations, use webhooks.

## What an event carries

An event names what changed and its new state. It **never carries a value**:
no record values, no answers, no labels, no share slugs. Your server reads
what it needs through the API with an [API key](authentication.md), where a
revoked share or answer simply stops answering. That keeps sealed records
sealed and keeps secrets out of the logs on both sides.

```json
{
  "id": "q8m2k4x7p1zvwy3",
  "type": "link.revoked",
  "created": "2026-11-03T09:14:03Z",
  "workspace": "lxt7nlkvfqairg5",
  "data": {
    "object": "link",
    "id": "9k2m4pqx81zvwy3",
    "status": "revoked",
    "kind": "share"
  }
}
```

| Field | Meaning |
|---|---|
| `id` | The event's id. Every delivery and resend of the event carries the same id, so use it to drop duplicates. |
| `type` | One of the [event types](#event-types). |
| `created` | When it happened. |
| `workspace` | The workspace it happened in. |
| `data` | `object` and `id` name what changed; the other fields depend on the type. |
| `test` | Present and `true` only on a [test event](#testing). |

## Event types

`GET /api/webhooks/event-types` serves this list, so a client never has to
hard-code it.

| Type | Sent when | `data` |
|---|---|---|
| `link.created` | A share was created, or an answer was given from this workspace. | `id`, `status`, `kind` (`share` or `answer`), `request` for an answer |
| `link.updated` | A share's records, limits or label changed. | as above |
| `link.viewed` ¹ | Someone opened a share. | as above, plus `views` |
| `link.paused` / `link.resumed` | A share was paused, or turned back on. | as above |
| `link.revoked` | A share was revoked or deleted. | as above, `deleted: true` if deleted |
| `link.expired` | A share reached its end date or its view limit. | as above, `reason: "max_views"` for the limit |
| `request.created` | A request was created. | `id`, `status` |
| `request.paused` / `request.resumed` | A request was paused, or turned back on. | `id`, `status` |
| `request.closed` | A request was revoked, expired, completed or deleted. | `id`, `status`, `deleted: true` if deleted |
| `response.submitted` | Someone answered one of this workspace's requests. | `id` (the answer), `request`, `status`, `server` for an answer kept on another server |
| `response.changed` | An answer's entries changed, it was answered again, paused or resumed. | as above |
| `response.revoked` | The responder took their answer back. | as above |
| `response.expired` | An answer reached its end date or view limit. | as above |
| `record.created` / `record.deleted` | A vault record was added or deleted. | `id`, `key` |
| `record.updated` ¹ | A vault record changed. | `id`, `key` |
| `attestation.issued` / `attestation.revoked` | An attestation was accepted, or revoked. | `id`, `type`, `status` |
| `identity.created` / `identity.revoked` | An identity was created, or revoked. | `id`, `fingerprint`, `status` |
| `member.joined` / `member.updated` / `member.removed` | Someone joined, their permissions changed, or they left. | `id`, `user`, `permissions` |
| `apikey.created` / `apikey.revoked` | An API key was created or deleted. | `id`, `user` |
| `connection.approved` / `connection.revoked` | A tool was connected or removed. | `id`, `clientId` |

¹ Frequent. An endpoint subscribed to `"*"` gets every type **except** these
two; name them to receive them.

`response.*` goes to the workspace that **asked**. The answer itself lives in
the responder's workspace, which sees it as `link.*` with `kind: "answer"`.

Events are recorded only while the workspace has an enabled endpoint that
subscribes to them. Nothing is collected for a workspace with no webhooks.

## Delivery

- `POST`, `Content-Type: application/json`, `User-Agent: Revoked-Webhooks/1`.
- Headers: `Revoked-Event-Id`, `Revoked-Event-Type`, `Revoked-Signature`.
- Each attempt has **10 seconds**. Redirects are not followed.
- Any `2xx` is delivered. Anything else, or no answer, is **retried**: after
  30 seconds, then doubling up to six hours, 12 tries over about a day and a
  half. Answer quickly and do the work afterwards.
- A delivery can therefore arrive more than once and out of order. Drop
  repeats by `id`; order by `created`.
- An endpoint that has failed for **three days** without a single success is
  turned off, and whoever created it gets a notification. Turn it back on and
  [replay](#resending) what it missed.

The address policy is the one callbacks use: an absolute `http`/`https` URL,
loopback and private ranges refused unless the server runs with
`ALLOW_PRIVATE_CALLBACKS=true`, the resolved address re-checked at connect
time. See [Callbacks → Security](callbacks.md#security).

## Verifying the signature

Every delivery carries

```
Revoked-Signature: t=1793704443,v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd
```

`v1` is the hex HMAC-SHA256, keyed with the endpoint's signing secret, of the
timestamp, a full stop, and the raw request body: `"{t}.{body}"`. Check it
against the bytes you received, before parsing them, and refuse a timestamp
more than five minutes old so a captured delivery cannot be replayed.

```python
import hashlib, hmac, time

def verify(secret: str, header: str, body: bytes, tolerance=300) -> bool:
    parts = [p.split("=", 1) for p in header.split(",")]
    t = next(v for k, v in parts if k == "t")
    if abs(time.time() - int(t)) > tolerance:
        return False
    expected = hmac.new(secret.encode(), f"{t}.".encode() + body, hashlib.sha256).hexdigest()
    return any(hmac.compare_digest(expected, v) for k, v in parts if k == "v1")
```

After a [rotation](#endpoints) the header carries two `v1` values, one per
secret, for 24 hours. Accept a match against either.

## Endpoints

All routes are under `/api/webhooks`, take a session or an API key, and need
the **Manage webhooks** permission (`webhook:manage` on a key). Every route
acts on the caller's active workspace (a key's own workspace); another
workspace's webhooks answer `404`.

| Route | Does |
|---|---|
| `GET /event-types` | The event catalogue. |
| `GET /endpoints` | Your endpoints, each with the last day's `stats`. |
| `POST /endpoints` | Create one: `url`, optional `description`, `events` (defaults to `["*"]`). The answer holds the `secret`. |
| `GET /endpoints/{id}` | One endpoint. |
| `PATCH /endpoints/{id}` | Change `url`, `description`, `events`, or `enabled`. |
| `DELETE /endpoints/{id}` | Delete it and its log. |
| `GET /endpoints/{id}/secret` | The current signing secret. |
| `POST /endpoints/{id}/rotate-secret` | A new secret; the old one keeps signing for 24 hours. |
| `POST /endpoints/{id}/test` | Send a sample `type` now; answers with the delivery. |
| `POST /endpoints/{id}/replay` | Queue every failed delivery since `since` (RFC 3339, default 24 hours ago) again. |
| `GET /events?type=` | The event log, newest first. |
| `GET /deliveries?endpoint=&status=&type=&event=` | The delivery log, newest first. `status` is `pending`, `succeeded` or `failed`. |
| `GET /deliveries/{id}` | One delivery: its `payload` and every attempt (`attemptLog`), with the status, the first 2 KB of what your server answered, and how long it took. |
| `POST /deliveries/{id}/resend` | Try it again now. A resend that lands marks it delivered; one that fails leaves the automatic retries as they were. |

Lists take `page` and `perPage` (at most 100). A workspace holds up to 16
endpoints. Creating, changing and deleting an endpoint is written to the audit
log; the secret never is.

## Resending

Every delivery is kept for **30 days**, with its payload and every attempt. In
the app, open Settings → Webhooks → your endpoint, tap a delivery, and
**Resend**. **Resend failed** on the endpoint's page queues everything that
failed in the last day, which is what you want after fixing your server.

## Testing

**Send test** on an endpoint's page, or `POST /endpoints/{id}/test`, sends one
sample of the type you pick through the real path: the same signature, the
same client, the same address policy. The sample's ids start with `example_`
and the body carries `"test": true`. A test is tried once and never retried.

## Errors

| `code` | Means |
|---|---|
| `webhook_url_invalid` | Not an absolute `http`/`https` URL, or one the address policy refuses. |
| `webhook_events_invalid` | No events, or a name that is not in the catalogue. |
| `webhook_limit_reached` | The workspace already has 16 endpoints. |
| `webhook_not_found` / `webhook_delivery_not_found` | Not in your workspace. |
| `webhook_disabled` | Replay on an endpoint that is turned off. |
| `missing_permission` | You or the key lack Manage webhooks. |
