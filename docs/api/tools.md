# Building a tool

A tool proposes a share to the owner of a vault and, once it has been
connected, can see what became of that share. The vault itself is never read,
the owner's credentials are never held, and nothing is stored on the owner's
server for the tool. The user-facing side is described in
[Tools & link proposals](../guide/tools.md);
[Notfallkarte](../guide/notfallkarte.md) is a complete tool built this way.

The whole process has three parts, and a tool may stop after any of them:

1. **Proposal** of a share through a `revoked://p` link — no server call and
   no token involved.
2. **Connection**, through PKCE, which results in a connection token.
3. **Use of the token** (`X-Revoked-Connection`) for reading link status,
   receiving handed-over links, revoking, or disconnecting.

Which server a user runs is not known in advance, since every instance is
self-hosted. The address reaches the tool when the app returns to it, or when
the owner enters it in the tool.

## 1. The proposal

A proposal is a `revoked://p` link, opened by the installed app. Values are
percent-encoded, with a space written as `%20` rather than `+`.

| Parameter | Required | Meaning |
|---|---|---|
| `label` | yes | Names the share, up to 120 characters. |
| `keys` | yes | Comma-separated record keys, 1–50, each `[a-z0-9_-]{1,64}`. |
| `from` | | The name the tool gives itself, up to 40 characters. Shown as a claim. |
| `template` | | A template name, up to 80 characters, describing the keys — so the app can ask for a key the vault does not hold yet. |
| `days` | | Expiry, 1–365 days. Left out: no expiry. |
| `stamp` | | Watermark text for files, up to 120 characters. |
| `purpose` | | `application` (requires `stamp`). |
| `client` | | The tool's origin: `https://host[:port]`, or `http://localhost` / `127.0.0.1` in development. Nothing else — no path. |
| `redirect` | needs `client` | The address the owner is sent back to; on `client`'s origin. |
| `state` | needs `redirect` | The tool's own value, `[A-Za-z0-9._~-]{1,128}`, handed back unchanged. |
| `ref` | | The tool's own reference for this link, up to 80 characters. Returned with the link's status once connected. |
| `challenge` | needs `state` | A PKCE S256 challenge, for connecting along the way (see below). |
| `revoke_reason`, `links_reason` | | Why the tool wants each permission, up to 120 characters each. Shown when it connects. |
| `poll` | needs `client` | The server origin the tool will ask for the answer itself. |

A link with any invalid part is refused as a whole. A label and keys are the
minimum; with a template named as well, the app can ask for any key the vault
lacks:

```text
revoked://p?label=Wi-Fi%20for%20guests&keys=network_name,wifi_password&template=Wi-Fi%20access
```

`wifi_password` is a hidden record in the *Wi-Fi access* template. A share
that includes a hidden record or a file is never handed to a tool, connected
or not — such a link is copied by the owner.

## 2. The connection

A connection is always the owner's decision, made in their app. The tool
sends a PKCE challenge, and the one-time code it receives in return can only
be redeemed with the matching verifier.

The challenge travels either as part of a proposal (`challenge`, together
with `client`, `redirect` and `state`) or in a connect link of its own:

```text
revoked://connect?client=https://tool.example
  &name=Guestbook
  &redirect=https://tool.example/
  &state=<random>
  &challenge=<base64url(SHA-256(verifier))>
```

### Answer through the return address

The app opens `redirect` with these query parameters added:

| Parameter | When |
|---|---|
| `state` | Always; compared by the tool with the value it sent. |
| `status` | `connected`, `created` or `declined`. |
| `server` | The owner's server origin — the one trustworthy source for it. |
| `code` | When the tool was just connected. Valid once, for five minutes. |
| `link` | With `created`: the id of the new link. |

The code is exchanged at the owner's server:

```bash
curl -X POST "$SERVER/api/connect/token" \
  -H "Content-Type: application/json" \
  -d '{"code":"…","verifier":"…","redirectUri":"https://tool.example/"}'
```

```json
{
  "token": "…",
  "connection": { "id": "…", "clientName": "Guestbook", "expiresAt": "…",
                  "allowRevoke": false, "allowHandOver": true }
}
```

The token is returned once, and only its hash is stored on the server. A
code is spent the moment it is presented, whether right or wrong, so a stolen
code cannot be tried again against the verifier.

### Answer through polling

The return address is opened in whichever browser the system picks, which is
not necessarily the tab that asked. A tool that already knows the owner's
server can collect the answer itself instead: with `poll=<server origin>` in
the link, the app opens nothing, and the page asks the server with its
verifier alone, every few seconds:

```js
const res = await fetch(server + '/api/connect/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ verifier, redirectUri: location.origin + '/' }),
});
// 202 {"pending": true}: not answered yet — ask again
// 200 {"token": …}:      connected
// 400:                    the answer lapsed or was not this page's
```

The answer is only handed to a request whose `Origin` is the tool's own, and
it is kept for five minutes. Since nothing ties a polled answer to the owner's
browser, the app never gives one unasked: a check code is shown on the tool's
page and compared by the owner with the one in the app. Both sides derive it
the same way — the first three bytes of `SHA-256(challenge)`, as upper-case
hex, split `3-3`:

```js
const d = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(challenge)));
const hex = [...d.slice(0, 3)].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
const code = hex.slice(0, 3) + '-' + hex.slice(3); // "83C-047"
```

## 3. The token

The token is sent in `X-Revoked-Connection`, not in `Authorization`. It is
not a user session and no collection rule admits it, so neither the vault nor
anything else outside these endpoints can be read with it.

| Endpoint | Does |
|---|---|
| `GET /api/connection` | The connection and the links its proposals became, newest first: `id`, `ref`, `label`, `status`, `viewCount`, `maxViews`, `expiresAt`, `created`, `handedOver`, and `url` — only on a handed-over, active link while the owner allows `allowHandOver`. |
| `POST /api/connection/links/{id}/revoke` | Revokes one of those links, where the owner allowed `allowRevoke`. |
| `DELETE /api/connection` | Disconnects the tool. The links remain the owner's. |

```bash
curl "$SERVER/api/connection" -H "X-Revoked-Connection: $TOKEN"
```

A `401` with `connection_unauthorized` means the tool was disconnected;
`connection_expired` means its 90 days have run out. In both cases the token
is of no further use, and a new connection can only be made by the owner,
from the app. The full schemas are in the
[Connections reference](reference/connections.md).

## A minimal tool

A single HTML file that proposes a share, is connected along the way, and
lists what became of its links. It works from any https origin (or from
`http://localhost`) on a machine with the app installed.

```html
<!doctype html>
<meta charset="utf-8">
<title>Guestbook</title>
<button id="propose">Register for the summer party</button>
<ul id="links"></ul>
<script type="module">
  const here = location.origin + '/';
  const b64url = (bytes) => btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const random = (n) => b64url(crypto.getRandomValues(new Uint8Array(n)));
  const sha256 = async (s) =>
    new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
  const enc = encodeURIComponent;

  // 1. The proposal, with a request to be connected along the way.
  document.querySelector('#propose').onclick = async () => {
    const state = random(16), verifier = random(32);
    sessionStorage.setItem('pending:' + state, verifier);
    const q = {
      label: 'Summer party', keys: 'full_name,email,dietary_restrictions',
      template: 'Event registration', from: 'Guestbook',
      client: location.origin, redirect: here, state, ref: 'summer-2026',
      challenge: b64url(await sha256(verifier)),
      links_reason: 'To put your registration on the guest list',
    };
    location.href = 'revoked://p?' + Object.entries(q).map(([k, v]) => k + '=' + enc(v)).join('&');
  };

  // 2. Back from the app: the state is checked and the code redeemed.
  const p = new URLSearchParams(location.search);
  const verifier = p.get('state') && sessionStorage.getItem('pending:' + p.get('state'));
  history.replaceState(null, '', location.pathname);
  if (verifier && p.get('code') && p.get('server')) {
    sessionStorage.removeItem('pending:' + p.get('state'));
    const res = await fetch(p.get('server') + '/api/connect/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: p.get('code'), verifier, redirectUri: here }),
    });
    if (res.ok) {
      const { token } = await res.json();
      localStorage.setItem('connection', JSON.stringify({ server: p.get('server'), token }));
    }
  }

  // 3. With a token, the status of the proposed links is read.
  const conn = JSON.parse(localStorage.getItem('connection') || 'null');
  if (conn) {
    const res = await fetch(conn.server + '/api/connection', {
      headers: { 'X-Revoked-Connection': conn.token },
    });
    if (res.status === 401) localStorage.removeItem('connection');
    else for (const l of (await res.json()).links) {
      const li = document.createElement('li');
      li.textContent = `${l.label} (${l.ref}): ${l.status}, opened ${l.viewCount}× ${l.url ?? ''}`;
      document.querySelector('#links').append(li);
    }
  }
</script>
```

Left out here, and covered by Notfallkarte: polling with a check code,
admitting a second browser into an existing connection, revoking, and the
case of an unreachable server.

## Notes

- **The server address** is only taken from the app (`server` in the return
  address) or from what the owner entered — never from the tool's own link
  or from a third party.
- **`state`** ties an answer to a link the page actually sent; answers
  without a matching state are ignored.
- **Links** open data, so they are best read from `/api/connection` when
  needed rather than kept as a copy.
- **CORS:** the owner's server is called from the browser. A server started
  with a restricted `--origins` list needs the tool's origin on it.
- **Rate limits:** `/api/connect/token` allows 60 requests per minute per IP
  by default (`RATELIMIT_CONNECT_REQUESTS`), enough for polling every few
  seconds from a couple of tabs.
