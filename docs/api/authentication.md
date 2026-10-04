# Authentication

Three credentials reach the API, and each has its own header. A credential
sent in another one's header authenticates as nobody — an API key sent as a
Bearer token, for example, is treated as a guest and refused by the
collection rules.

| Credential | Header | Used by |
|---|---|---|
| API key | `X-API-Key: <key>` | Scripts and integrations of the workspace's own |
| Session token | `Authorization: Bearer <jwt>` | The app itself, after signing in with a passkey |
| Connection token | `X-Revoked-Connection: <token>` | A connected tool, for the links it proposed |

## Choosing a credential

| Situation | Credential | Reach |
|---|---|---|
| A **personal setup** — a cron job, a home server, a script keeping a record current | An [API key](#api-keys), created in the app | The scopes granted to it, never the vault |
| A tool used by **other people** with **their own** data | A [connection](tools.md), granted by each of them in their app | The links created from its proposals: status, and — where allowed — receiving or revoking them. Never the vault. |
| Answers collected from other people into the **own** workspace | A [request](reference/requests.md), optionally with a [callback](callbacks.md) | What is submitted |

The difference lies in whose credential it is: an API key belongs to the
workspace that created it, a connection to the person who granted it. An API
key handed out for someone else's tool would be a long-lived string carrying
all of its permissions, pasted into a foreign service. A connection, by
contrast, is limited to the links that were approved, appears under
*Connected tools*, lapses after 90 days and ends with a disconnect.

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

## Connection tokens

A connection token is issued at `POST /api/connect/token`, in exchange for a
one-time code and its PKCE verifier, after the tool was connected in the app.
It travels as `X-Revoked-Connection` and opens only the `/api/connection`
endpoints; it is not a session, so no collection rule admits it. The whole
flow, including a minimal working page, is described in
[Building a tool](tools.md).

## Reading a failure

| Code | Meaning |
|---|---|
| `not_authenticated` | No usable credential arrived — wrong header, an unexpanded variable, or an empty value. |
| `invalid_api_key` | The header arrived, but no key matches it: mistyped, revoked, or expired. |
| `api_key_vault_scope` | The key being created asks for the vault, which no key may hold. |
| `connection_unauthorized` | No connection matches the `X-Revoked-Connection` token: mistyped, or the owner disconnected the tool. |
| `connection_expired` | The connection lapsed, 90 days after the owner last connected the tool. Only the owner can connect it again. |
| A named scope error | The key is valid but was not granted that permission. Create a key with the right grants; scopes are fixed at creation. |

## Revoking

Revoke from the same settings list. The next request with that key fails —
there is no grace period.

Treat a key that has left its intended channel (pasted into a chat, committed,
written to a log) as compromised: revoke it and create a replacement. The
plaintext cannot be rotated in place, because the server never had it.
