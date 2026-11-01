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
- **No server to type, and the app can be anywhere.** "Sign in with Revoked"
  opens a panel with a QR code for a phone and a link for this device. The
  Revoked app knows the person's server; the person approves the sign-in there,
  and the answer names the server in `iss`.
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

The Revoked app on this device is then signed in to that server.

Then, in this folder:

```bash
npm install
cp .env.example .env
npm start
```

The shop is at <http://localhost:4000>. Signing in needs the Revoked app,
signed in to that server; an entry with the key `shipping_address` in its vault
is offered first when the app asks what to share. The app delivers its answer
to the shop directly, so on `localhost` it has to run on the same machine. To
scan the code with a phone, set `PUBLIC_URL` to an address the phone can reach.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `PUBLIC_URL` | `http://localhost:4000` | Where the shop is reached. Its origin is the client id; `/callback` on it is the redirect address. |
| `PORT` | `4000` | The port to listen on. |
| `REVOKED_SERVERS` | empty | When set, the only servers that may be used, comma-separated. |
| `REQUESTED_KEYS` | `shipping_address,phone` | Vault keys asked for at sign-in. Empty asks for none. |

Nothing is registered at the Revoked server: the client id is the shop's
origin, and PKCE takes the place of a client secret.

## How it is put together

```
src/
  server.js    routes: the start page, /login/start, /login/wait, /callback, /logout
  signins.js   sign-ins in progress, and the two keys that keep them apart
  auth.js      discovery, the authorization request, the code exchange
  grants.js    reading shared entries, honouring maxAge and ETags
  sessions.js  in-memory sessions behind an HttpOnly cookie
  views.js     HTML, with everything from elsewhere escaped
  config.js    settings from the environment, checked at startup
public/
  style.css
../sign-in-button/
  revoked-sign-in.js   the button and the panel, for your own service too
```

The sign-in follows the authorization code flow:

1. The button calls `POST /login/start`, which builds the authorization request
   — a PKCE challenge, a `state`, a `nonce`, and a `claims` request for the
   vault keys — and answers with the `revoked://signin` link, its check code,
   and a `wait` key only this page holds. The button shows the link as a QR code
   and as a link for this device, then asks `POST /login/wait` every two seconds.
2. In the app, the person decides what to share and approves. The app then
   requests the shop's `/callback` itself, with no browser in between.
3. `GET /callback` takes the server from the answer's `iss`, discovers it, and
   hands the answer to `openid-client`, which checks `state` and `iss`, redeems
   the code with the PKCE verifier, and verifies the ID token against the
   server's published key. The shop then reads userinfo, which carries the grant
   (`revoked_links`), and keeps the result for the page. `POST /login/wait`
   hands it over and starts the session in that browser.
4. Each view of the account page reads the grant through
   `POST /api/grants/resolve` on the person's server, unless the last answer
   is still within its `maxAge`.

## Before using this pattern in production

The demo keeps things short on purpose. A real service would also:

- keep sessions in a store that survives restarts, and rotate the session id
  after sign-in;
- restrict `REVOKED_SERVERS`, or resolve and check server names before
  fetching them, since the answer's `iss` decides which host the shop
  contacts;
- keep `signins.js` in a shared store if it runs more than one instance;
- protect `POST /logout` with a CSRF token, rather than relying on the
  `SameSite=Lax` cookie alone;
- serve over https, which also marks the session cookie `Secure`.
