# Sign in with Revoked

Every Revoked server is an OpenID Connect provider. A service — a game
server, a shop, a forum — signs people in with their Revoked account through
an ordinary OpenID Connect client library, without keeping passwords or
accounts of its own. What the service learns is decided by the person in the
Revoked app, and data it asks for arrives as a living grant rather than a
copy.

The endpoint reference is under [OpenID Connect](reference/openid-connect.md).
To add it to a service, start with
[Add it to your service](#add-it-to-your-service). A complete example service
is in
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

## Add it to your service

A person's Revoked app is often not on the device they are browsing with, and
a web page cannot find out: a `revoked://` link with no app behind it simply
does nothing. So the button opens a panel that works either way, with the
request as a QR code for a phone and as a link for this device. The page then
waits, and the app delivers the answer to your server. Revoked hosts nothing
for this, and nothing is registered.

**1. Add the button.** Copy
[`examples/sign-in-button`](https://github.com/argseby/revoked/tree/main/examples/sign-in-button)
next to your static files:

```html
<script type="module" src="/revoked/revoked-sign-in.js"></script>
<revoked-sign-in start="/auth/revoked/start" wait="/auth/revoked/wait"></revoked-sign-in>
```

It brings its own QR code, check code, translations and layout, and needs only
`script-src 'self'` and `connect-src 'self'` from a Content-Security-Policy. An
app that draws its own interface keeps its own button and shows the same three
things: the `app_link` as a QR code, that link to open on this device, and the
`check_code`.

**2. Add three routes.** The paths are yours. Keep what `start` remembers for
ten minutes, in memory or wherever suits you.

| Route | Does | Answers |
|---|---|---|
| `POST /auth/revoked/start` | Makes a PKCE verifier, a `state`, a `nonce` and a random `wait` key, and remembers them. | `{ "app_link": "revoked://signin?…", "check_code": "0D2-99B", "wait": "…" }` |
| `GET /auth/revoked/callback` | The app delivers its answer here. Finds the sign-in by `state`, redeems the code as usual, and keeps the result for `wait`. | Any status below 400; the app does not follow redirects. |
| `POST /auth/revoked/wait` | Takes `{ "wait": "…" }`. Once there is a result, hands it over once and starts the session on this response. | `{ "done": false }`, then `{ "done": true }` or `{ "done": true, "error": "access_denied" }`. `401` once expired or already collected. |

`app_link` is an ordinary authorization request, with `redirect_uri` pointing at
your callback, plus `revoked_return=background`:

```
revoked://signin?client_id=https%3A%2F%2Fgame.example
  &redirect_uri=https%3A%2F%2Fgame.example%2Fauth%2Frevoked%2Fcallback
  &response_type=code&scope=openid%20profile
  &state=…&nonce=…&code_challenge=…&code_challenge_method=S256
  &revoked_return=background
```

`check_code` is the first three bytes of SHA-256 over the `code_challenge`, as
upper-case hex in two groups. The app computes the same one and shows it next
to the request.

Redeeming the code is the same as in any OpenID Connect client: take the server
from `iss`, discover it, and let your library check the answer. See
[Finding the person's server](#finding-the-persons-server) for what to check on
`iss`. [`examples/sign-in-demo`](https://github.com/argseby/revoked/tree/main/examples/sign-in-demo)
has all three routes running, in about a hundred lines
([`server.js`](https://github.com/argseby/revoked/blob/main/examples/sign-in-demo/src/server.js),
[`signins.js`](https://github.com/argseby/revoked/blob/main/examples/sign-in-demo/src/signins.js)).

**Three things to get right:**

- **Keep `wait` away from the link.** `state` is in the QR code, where anyone
  who can see the screen can read it. It may only answer. `wait` goes to the
  page that started and nowhere else, and it alone collects the result.
- **Start the session on the `wait` response, never on the callback.** The
  callback comes from the person's phone, or from whoever scanned the code.
  Don't ask for a cookie there either: a phone has none.
- **Take each answer once.** Forget the `state` when the callback arrives, and
  the result when `wait` hands it over.

Your callback must be reachable from the person's phone, so a service on
`localhost` can only be tested with the app on the same machine.

## Approving in the app

A sign-in is approved in the person's Revoked app and nowhere else. There is
no passkey prompt and no consent screen in the browser: the authorization
endpoint only hands the request to the app.

The app shows who is asking, as which account, and what the service would
learn. An approval asks for the person's fingerprint, face or device PIN —
Face ID or Touch ID on Apple devices, the biometric prompt on Android,
Windows Hello on Windows — and the app signs it with an identity key that
never leaves the device. Linux has no such prompt; there the identity key is
the only proof. A session token on its own, or a copied link opened
elsewhere, approves nothing.

Once the person decides, the app hands the service the redirect address with
the code, the state, and `iss` — the issuer of the server that answered
(RFC 9207). With `revoked_return=background` it requests that address itself.
Without it, it opens the address in the system browser, which then has to be
the browser the sign-in started in. That is why a service's button should
always use the former.

## Finding the person's server

Which server a person uses is not known in advance, since every instance is
self-hosted. The person's Revoked app knows it, so a sign-in starts there.

### Through the app

A "Sign in with Revoked" button carries the authorization request itself as a
`revoked://signin` link, which depends on nothing about the server. The app
opens the request on the server it is signed into, and the person approves it
there, in the app.

The service then works as with a known server, starting from `iss`:

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

### Approving someone else's sign-in

A service that waits hands the session to the browser that holds the pending
sign-in, so a sign-in can be approved on a device other than the one that ends
up signed in. As with any QR sign-in, someone could show a person their own
code and ask them to approve it. The app names the service and the check code,
and asks the person to approve only what they just started themselves. The
page shows the same code, so the person can compare the two.

If the app cannot reach the service, it opens the redirect address in the
browser instead. The service records the answer as usual, so the waiting page
carries on.

### Through the authorization endpoint

A client library that sends the browser to a known server's
`authorization_endpoint` reaches a page that opens the app with the same
request, as a `revoked://signin` link. The app answers on the server it is
signed into; a service that expects a particular issuer compares `iss` with
it. This only works when the app is on the same device, and the answer comes
back through that device's default browser. Use the button above unless your
library leaves you no choice.

### Without the app

Signing in needs the Revoked app, though not on the device the person is
browsing with: the QR code covers that case. On a device without the app,
`revoked://` leads nowhere. Most browsers stay on the page, and some show an
error, so the panel says the app is needed.

## Scopes and claims

| Scope | Claims |
|---|---|
| `openid` (required) | `sub` |
| `profile` | `name` |
| `email` | `email`, `email_verified` |
| `revoked_identity` | `revoked_identity` — the fingerprint of the person's primary identity, the same at every service |

`name` is the name the person chose for this service: one of their identities'
names, or a vault entry. A person can give each service a different name, or
none, in which case `profile` is left out of the granted scopes. There is no
account-wide name. Use `sub` to recognise someone, because a name can change.

When the name comes from a vault entry, the userinfo response also carries a
grant with the key `name` (see [Asking for vault entries](#asking-for-vault-entries)).
Read it to follow the current name without another sign-in. Revoking that grant
stops the `name` claim too. The ID token and userinfo always answer with the
name as it stands, but a plain OIDC client that reads them only at sign-in sees
a change at the next sign-in.

`sub` is different at every service: the same person signing in to two
services gives each its own identifier, so services cannot match their users
with each other. Each of the person's workspaces is a separate account as well:
signing in from another workspace gives the service another `sub`, and no name
or entry chosen in the first workspace is offered. `sub` stays the same for one
service and workspace across sign-ins, unless the person asks for a new one
([Pausing and disconnecting](#pausing-and-disconnecting)).

The person can decline every scope but `openid` in the app. The
`scope` returned by the token endpoint lists what was granted.

## Asking for vault entries

Entries from the person's vault are asked for by key, through the `claims`
parameter:

```json
{ "userinfo": { "revoked_links": { "values": ["shipping_address", "phone"] } } }
```

In the app the person picks one of the entries in their active workspace for
each key, types a new value, or shares nothing. A new value is saved as an entry
under that key, or the next free key if it is taken. Picking an entry with
another key adds an alias under the key asked for, unless the key is taken or
the entry is a file. The person can switch workspace from the consent screen,
which opens the request again with a new ticket. An entry from any other
workspace is refused with `oidc_link_record_invalid`. Switching workspace also
switches the account the service sees, so each workspace shares through its own
link. New values and aliases are filed in a
section keyed `signin_<host>` and get the service's host in `requestedBy`;
entries the person already had are not moved. The userinfo endpoint then returns a grant
over the chosen entries:

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

Every approval also leaves a row in the person's `signIns` collection: the
service's origin, the scopes it has learned, its link if it has one, where its
name comes from, and when the person last signed in. The app lists these under **Settings → Connected
tools**. The row can't be written through the collection API and holds no
values, and each approval is written to the audit log as `sign_in_approved`.

## Sessions

Every sign-in is approved in the person's app, and the provider keeps no
session of its own. Consequently:

- `prompt=none` is always answered with `login_required`.
- There are no refresh tokens. The ID token proves a sign-in that just
  happened; the service keeps its own session after that.
- There is nothing to log out of at the provider.

## Pausing and disconnecting

The person can stop a service at any time. None of this reaches the session your
service keeps for itself, so a person stays signed in with you until you end it.

| | Pause | Disconnect | Disconnect with a new ID |
|---|---|---|---|
| Sign-in requests | Answered `access_denied`, exactly as if declined | Asked again, in the app | Asked again, in the app |
| Access tokens and unredeemed codes | Refused while paused, good again after | Refused for good | Refused for good |
| Grants | `paused`, no values | `revoked` | `revoked` |
| `sub` on return | The same | The same | A new one |

The endpoints are `POST /api/sign-ins/{id}/pause`, `/resume` and `/disconnect`
with `{"newId": true}`, in the [reference](reference/openid-connect.md).

A new `sub` is unrelated to the old one, and the grant that comes with the next
share has a new id. Treat that sign-in like anyone else's first one: a new person
to you. Your old account for them stays yours to delete. Don't match them up by
email or name to bring the old account back. They asked to be someone new, and
they may decline to share either.

A paused service gets the same `access_denied` as a decline, so it can't tell a
pause from a no.

## The signing key

ID tokens are signed with RS256 by a key published at `/oidc/jwks`. It is not
the server's root key but a separate key the root key certifies; the
certification is published with it as `revoked_certification`. A service that
walks the [trust chain](trust-chain.md) from the DNS pin to the root key can
check that certification and so tie every ID token to the domain. Ordinary
client libraries ignore the member and verify tokens against the JWKS as
usual.
