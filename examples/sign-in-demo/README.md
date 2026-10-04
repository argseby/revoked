# Corner Shop — Sign in with Revoked

A small web service that signs people in with their Revoked account and reads
the delivery address they share, without storing it. It is a complete,
working example of [Sign in with Revoked](../../docs/api/sign-in.md) and uses
[`openid-client`](https://github.com/panva/openid-client), an ordinary OpenID
Connect library; nothing in it is specific to Revoked beyond choosing the
server and asking for vault entries.

What it shows:

- **No accounts and no passwords.** The shop knows a person by the `sub` it
  receives, which is the shop's own: the same person has a different one at
  every other service.
- **No server to type.** "Sign in with Revoked" opens the Revoked app, which
  knows the person's server and continues there; the answer names the
  server in `iss`. Only on a device without the app does the person name
  their server.
- **Data as a grant, not a copy.** The shop asks for `shipping_address` and
  `phone`. The person picks entries from their vault, or none. The shop
  receives a grant and reads the current value from the person's server
  whenever the page is shown, keeping it no longer than that server's
  `maxAge`. An edit in the vault appears on the next read; a revocation
  removes the value.

## Running it

The demo needs Node 22 or later and a Revoked server. A local server
answers as `http://localhost:<port>` when it is reached at localhost, whatever
its `DOMAIN`, so the usual development setup works as it is:

```bash
# in the repository root
go run ./cmd/revoked serve --http=127.0.0.1:3000
```

`REVOKED_SERVER` in `.env` then names `localhost:3000`.

Then, in this folder:

```bash
npm install
cp .env.example .env
npm start
```

The shop is at <http://localhost:4000>. Signing in needs an account with a
passkey on the Revoked server; an entry with the key `shipping_address` in
its vault is offered first on the consent screen. "Sign in with Revoked"
needs the Revoked app on the same device, signed in to that server; the
form under "No Revoked app on this device?" works without it.

Passkeys are bound to `localhost`, not `127.0.0.1`, so both are opened under
`localhost`.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `PUBLIC_URL` | `http://localhost:4000` | Where the shop is reached. Its origin is the client id; `/callback` on it is the redirect address. |
| `PORT` | `4000` | The port to listen on. |
| `REVOKED_SERVER` | empty | The server prefilled on the start page. |
| `REVOKED_SERVERS` | empty | When set, the only servers that may be used, comma-separated. |
| `REQUESTED_KEYS` | `shipping_address,phone` | Vault keys asked for at sign-in. Empty asks for none. |

Nothing is registered at the Revoked server: the client id is the shop's
origin, and PKCE takes the place of a client secret.

## How it is put together

```
src/
  server.js    routes: the start page, /login/app, /login, /callback, /logout
  auth.js      discovery, the authorization request, the code exchange
  grants.js    reading shared entries, honouring maxAge and ETags
  sessions.js  in-memory sessions behind an HttpOnly cookie
  views.js     HTML, with everything from elsewhere escaped
  config.js    settings from the environment, checked at startup
public/
  style.css
```

The sign-in follows the authorization code flow:

1. `POST /login/app` builds the authorization request — a PKCE challenge, a
   `state`, a `nonce`, and a `claims` request for the vault keys — and sends
   the browser to `revoked://signin` with it. The app opens the authorization
   page of the person's own server with the same parameters.
   Without the app, `POST /login` turns the server the person typed into an
   issuer URL and sends the browser to its authorization page directly.
2. On the Revoked server, the person confirms with their passkey and decides
   what to share.
3. `GET /callback` takes the server from the answer's `iss` when it was not
   known before, discovers it, and hands the answer to `openid-client`, which
   checks `state` and `iss`, redeems the code with the PKCE verifier, and
   verifies the ID token against the server's published key. The shop then
   reads userinfo, which carries the grant (`revoked_links`).
4. Each view of the account page reads the grant through
   `POST /api/grants/resolve` on the person's server, unless the last answer
   is still within its `maxAge`.

## Before using this pattern in production

The demo keeps things short on purpose. A real service would also:

- keep sessions in a store that survives restarts, and rotate the session id
  after sign-in;
- restrict `REVOKED_SERVERS`, or resolve and check server names before
  fetching them, since the person's input decides which host the shop
  contacts;
- protect `POST /logout` with a CSRF token, rather than relying on the
  `SameSite=Lax` cookie alone;
- serve over https, which also marks the session cookie `Secure`.
