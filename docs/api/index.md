# API

Everything the app does, this API does — it is the same surface, with no
private endpoints held back. Operators run it under their own domain, so there
is no shared base URL: substitute your own host throughout.

## Where to start

| If you want to | Read |
|---|---|
| Call the API from a script | [Authentication](authentication.md), then the [reference](reference/index.md) |
| Read or write vault data | [Records](reference/records.md) |
| Consume a share someone sent you | [Shares](reference/shares.md) |
| Collect data from other people | [Requests](reference/requests.md), then [Callbacks](callbacks.md) |
| Verify who a share or request came from | [Trust chain](trust-chain.md) |
| Generate a client | [`openapi.yaml`](openapi.yaml) |

## Two things that will surprise you

**Grants are living, not snapshots.** A share resolves the record's *current*
value each time it is read. Rotating a secret updates every share pointing at
it, with no republish step — and revoking one takes effect on the next read,
not the next sync. This is the whole point of the product, and it means you
should not cache a resolve result any longer than you would cache the secret
itself.

**Public endpoints are protected by slug entropy alone.** Anything under
`/api/public` or `/s` is reachable by whoever holds the slug. Slugs are
unguessable by construction and never derived from anything user-visible, and
there is deliberately no endpoint that lists them. Treat a slug as the
credential it is.

## Error handling

Failures come back in one envelope:

```json
{ "code": "link_password_required", "message": "This link requires a password.", "status": 401 }
```

Key off `code`, never off `message` — the prose may be reworded, the code will
not. Authorization failures name what was missing rather than returning a bare
denial, so a 403 tells you which scope or grant you lack.

Error messages may echo values you sent, but never server-held state. That is
deliberate: an error outlives the credential that produced it and ends up in
logs, tickets and screenshots read by people who hold no key.
