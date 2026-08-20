# Authentication

Two credentials reach the API, and each has its own header. An API key sent as
a Bearer token authenticates as nobody — the request is treated as a guest and
refused by the collection rules.

| Credential | Header | Used by |
|---|---|---|
| API key | `X-API-Key: <key>` | Scripts, integrations, anything programmatic |
| Session token | `Authorization: Bearer <jwt>` | The app itself, after login |

The in-app API preview on every create drawer shows a ready-to-run `curl` with
the correct header for the request in front of you.

## API keys

Create one under **Settings → Developer → API keys**. The plaintext is
returned once, at creation, and the server stores only its hash — there is no
way to retrieve it later.

A key carries the permissions granted when it was created, expanded to scopes.
A request outside those scopes is refused with a named error rather than a
generic 403, so the response says which grant is missing.

```bash
curl -X POST "https://api.revoked.link/api/collections/records/records" \
  -H "X-API-Key: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key":"env","value":"prod","label":"Environment","type":"text","format":"default","user":"<userId>","workspace":"<workspaceId>"}'
```

The header value is in double quotes on purpose: `'$TOKEN'` in single quotes
is sent as the six literal characters, since the shell expands variables only
inside double quotes.

## Reading a failure

| Code | Meaning |
|---|---|
| `not_authenticated` | No usable credential arrived — wrong header, an unexpanded variable, or an empty value. |
| `invalid_api_key` | The header arrived, but no key matches it: mistyped, revoked, or expired. |
| A named scope error | The key is valid but was not granted that permission. Create a key with the right grants; scopes are fixed at creation. |

## Revoking

Revoke from the same settings list. The next request with that key fails —
there is no grace period.

Treat a key that has left its intended channel (pasted into a chat, committed,
written to a log) as compromised: revoke it and create a replacement. The
plaintext cannot be rotated in place, because the server never had it.
