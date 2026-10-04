# Sign in with Revoked

Every Revoked server is an OpenID Connect provider. A service — a game
server, a shop, a forum — signs people in with their Revoked account through
an ordinary OpenID Connect client library, without keeping passwords or
accounts of its own. What the service learns is decided by the person on a
consent screen, and data it asks for arrives as a living grant rather than a
copy.

The endpoint reference is under [OpenID Connect](reference/openid-connect.md).
A complete example service is in
[`examples/sign-in-demo`](https://github.com/argseby/revoked/tree/main/examples/sign-in-demo).

## What a service needs

Nothing is registered in advance. The values a client library asks for are:

| Setting | Value |
|---|---|
| Issuer | `https://<domain>` of the person's server. Discovery is at `https://<domain>/.well-known/openid-configuration`. A server developed on locally answers as `http://localhost:<port>` when reached there. |
| Client id | The service's origin, e.g. `https://game.example`. |
| Redirect URI | Any address on that origin, e.g. `https://game.example/auth/callback`. |
| Client secret | None. The client is public; PKCE with `S256` is required in its place. |
| Flow | Authorization code. |

## Finding the person's server

Which server a person uses is not known in advance, since every instance is
self-hosted. The person's Revoked app knows it, so a sign-in usually starts
there.

### Through the app

A "Sign in with Revoked" button opens the app with the authorization request
itself, which depends on nothing about the server:

```
revoked://signin?client_id=https%3A%2F%2Fgame.example
  &redirect_uri=https%3A%2F%2Fgame.example%2Fauth%2Fcallback
  &response_type=code&scope=openid%20profile%20email
  &state=…&nonce=…&code_challenge=…&code_challenge_method=S256
  &claims=…
```

The app opens the authorization page of the server it is signed into, in
the browser, with the same parameters. The person confirms with their passkey
there, and the browser returns to the redirect address with the code, the
state, and `iss` — the issuer of the server that answered (RFC 9207).

The service then works as with a known server, starting from that issuer:

1. `iss` is checked like any server the service accepts: an `https` origin,
   on an allow-list if the service keeps one.
2. Discovery runs against `iss`. Client libraries refuse metadata whose
   `issuer` differs, and refuse an answer whose `iss` differs from the
   discovered issuer.
3. The code is redeemed at that server's token endpoint, with the PKCE
   verifier and the `state` and `nonce` the service remembered.

A person is known by the issuer and `sub` together. An answer from a server
other than the person's own cannot sign anyone in as one of that server's
users: the code, the ID token and the subject all belong to the server that
issued them.

The app opens the system browser, so the service's session cookie must be
there for the `state` to be found: the button belongs on pages opened in the
default browser.

### Without the app

On a device without the app, `revoked://` leads nowhere: most browsers stay on
the page, some show an error. The service then asks for the server's domain
and starts the sign-in there, as above. Remembering the issuer after the
first sign-in spares the question on later visits.

## Scopes and claims

| Scope | Claims |
|---|---|
| `openid` (required) | `sub` |
| `profile` | `name` |
| `email` | `email`, `email_verified` |
| `revoked_identity` | `revoked_identity` — the fingerprint of the person's primary identity, the same at every service |

`sub` is different at every service: the same person signing in to two
services gives each its own identifier, so services cannot match their users
with each other. It stays the same for one service across sign-ins.

The person can decline every scope but `openid` on the consent screen. The
`scope` returned by the token endpoint lists what was granted.

## Asking for vault entries

Entries from the person's vault are asked for by key, through the `claims`
parameter:

```json
{ "userinfo": { "revoked_links": { "values": ["shipping_address", "phone"] } } }
```

On the consent screen the person picks one of their entries for each key, or
none. The userinfo endpoint then returns a grant over the chosen entries:

```json
{
  "sub": "4kS0…",
  "revoked_links": {
    "endpoint": "https://<domain>/api/grants/resolve",
    "grants": [ { "id": "q8w2…", "token": "…", "keys": ["shipping_address"] } ]
  }
}
```

The values are read from `endpoint` with the grant's id and token, whenever
they are needed:

```
POST /api/grants/resolve
{ "grants": [ { "id": "q8w2…", "token": "…" } ] }
```

Each answer carries the current values, an `etag` for asking again cheaply,
and `maxAge`, the number of seconds a value may be kept before it is read
again. When the person edits the entry, the next read returns the new value;
when they revoke the grant, the next read returns `revoked` and no values.

The grant appears in the person's app as a link of their own, labelled with
the service's origin. Signing in again and sharing again updates that same
link and replaces its token.

## Sessions

Every sign-in is confirmed with the person's passkey, and the provider keeps
no session of its own. Consequently:

- `prompt=none` is always answered with `login_required`.
- There are no refresh tokens. The ID token proves a sign-in that just
  happened; the service keeps its own session after that.
- There is nothing to log out of at the provider.

## The signing key

ID tokens are signed with RS256 by a key published at `/oidc/jwks`. It is not
the server's root key but a separate key the root key certifies; the
certification is published with it as `revoked_certification`. A service that
walks the [trust chain](trust-chain.md) from the DNS pin to the root key can
check that certification and so tie every ID token to the domain. Ordinary
client libraries ignore the member and verify tokens against the JWKS as
usual.
