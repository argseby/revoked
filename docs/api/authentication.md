# Authentication

Two credentials reach the API, and each has its own header. An API key sent as
a Bearer token authenticates as nobody — the request is treated as a guest and
refused by the collection rules.

| Credential | Header | Used by |
|---|---|---|
| API key | `X-API-Key: <key>` | Scripts, integrations, anything programmatic |
| Session token | `Authorization: Bearer <jwt>` | The app itself, after signing in with a passkey |

The in-app API preview on every create drawer shows a ready-to-run `curl` with
the correct header for the request in front of you.

## Signing in

People sign in with a passkey and nothing else; there is no password endpoint.
A passkey is bound to the server's address, so the ceremony runs on the
server's own page, `GET /passkey`, in the browser:

1. The app makes a PKCE verifier, and opens
   `/passkey?mode=signin&challenge=<S256>&state=<random>`.
2. The page calls `POST /api/passkeys/login/begin` and `…/finish` around the
   authenticator, and gets a one-time code.
3. The page opens `revoked://auth?code=…&state=…`.
4. The app checks the state and redeems the code with its verifier at
   `POST /api/passkeys/token`, which answers with the session token.

The code is useless to anything else that sees the link: it is bound to the
challenge, and spent on first presentation. Registration runs the same way
through `/api/passkeys/register/*` — with an email address where the operator
allows signups, or with a one-time ticket that adds a passkey to an existing
account. See [Accounts](../installation/accounts.md).

Scripts do not sign in; they use an API key.

## API keys

Create one under **Settings → Developer → API keys**, or over the API by
creating an `apiKeys` record with a session token. The token is minted
server-side either way and returned exactly once — in the app as the
plaintext you copy, over the API in the `X-Plain-Token` response header. The
server stores only its hash; there is no way to retrieve it later.

A key can carry an `expiresAt` date, after which it stops authenticating as
if revoked.

A key carries the permissions granted when it was created, expanded to scopes.
A request outside those scopes is refused with a named error rather than a
generic 403, so the response says which grant is missing.

A key never opens the vault. Creating one with a vault permission
(`vault:read`, `vault:write`) or one of their scopes (`record:*`, `section:*`)
fails with `api_key_vault_scope`: a key is a string that ends up pasted into
other services, and one that reads the vault hands over everything in it. A
tool that needs something from you connects and proposes a link you confirm; a
company sends a request. Keys created before this rule keep what they were
granted until they expire or are revoked — the app marks them, and they should
be replaced.

```bash
curl "https://api.example.com/api/collections/links/records" \
  -H "X-API-Key: $TOKEN"
```

The header value is in double quotes on purpose: `'$TOKEN'` in single quotes
is sent as the six literal characters, since the shell expands variables only
inside double quotes.

## Reading a failure

| Code | Meaning |
|---|---|
| `not_authenticated` | No usable credential arrived — wrong header, an unexpanded variable, or an empty value. |
| `invalid_api_key` | The header arrived, but no key matches it: mistyped, revoked, or expired. |
| `api_key_vault_scope` | The key being created asks for the vault, which no key may hold. |
| A named scope error | The key is valid but was not granted that permission. Create a key with the right grants; scopes are fixed at creation. |

## Revoking

Revoke from the same settings list. The next request with that key fails —
there is no grace period.

Treat a key that has left its intended channel (pasted into a chat, committed,
written to a log) as compromised: revoke it and create a replacement. The
plaintext cannot be rotated in place, because the server never had it.
