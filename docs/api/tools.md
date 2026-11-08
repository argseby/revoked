# Building a tool

A tool proposes a share to the owner of a vault and, once it has been
connected, can see what became of that share. The vault itself is read only
if the owner allows it, the owner's credentials are never held, and nothing is stored on the owner's
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
| `vault`, `vault_reason` | connect link only | `vault=read` asks to read the owner's whole vault; see [the connection](#2-the-connection). |
| `section`, `section_reason` | connect link only | `section=1` asks for a section of the owner's vault of the tool's own; see [its own section](#its-own-section). |
| `permissions`, `permissions_reason` | connect link only | Comma-separated permission keys the tool asks for: `shares:read`, `shares:manage`, `requests:manage`, `attestations:issue`, `vault:read`, `vault:write`. |
| `poll` | needs `client` | The server origin the tool will ask for the answer itself. |
| `draft` | needs `client` | A draft id from `POST /api/connection/drafts`: values the connected tool suggests, `[a-z0-9]{24}`. See below. |

A link with any invalid part is refused as a whole. A label and keys are the
minimum; with a template named as well, the app can ask for any key the vault
lacks:

```text
revoked://p?label=Wi-Fi%20for%20guests&keys=network_name,wifi_password&template=Wi-Fi%20access
```

`wifi_password` is a hidden record in the *Wi-Fi access* template. A share
that includes a hidden record or a file is never handed to a tool, connected
or not — such a link is copied by the owner.

### Suggested values

A connected tool that already heard a value from the owner, such as an
assistant they told their phone number, can suggest it rather than have the
owner type it again. The link still carries no value: the tool posts
`{"values": {key: text}}` to `POST /api/connection/drafts` with its token and
adds the returned id as `draft`. The server holds the values in memory for one
hour and hands them only to the owner of that connection.

The proposal screen offers a suggestion only for a typed key the vault does not
hold yet, never for a date, a yes/no or a file, and never over a value already
there. Each one opens prefilled, marked as the tool's suggestion, and is saved
only when the owner saves it. The draft is discarded once the proposal is
created or declined. The audit log (`tool_drafted_values`) names the keys a
tool suggested, never the values.

### Requests, attestations and checks

A tool can propose three more things the same way. Each link opens the
owner's own form, filled in; the owner completes it and saves. None takes a
return address or a challenge: connect first (below), and whatever the owner
saves joins the connection when it names the tool's `client`. Without a live
connection it is saved all the same, and the tool learns nothing.

| Link | Opens | Parameters |
|---|---|---|
| `revoked://pr` | The new-request form | `template` (required, a template name, up to 80), `label` (up to 120), `days` (1–365) |
| `revoked://attest` | The attestation form | `type` (required), `for` (required, the subject's fingerprint), `claims` (comma-separated names); the tool's name goes in `name` |
| `revoked://check` | The check form | `type`, `issuers` (comma-separated attester domains, up to 20), `claims` (up to 50) |

All three take `client` and `ref` as a share proposal does; `pr` and
`check` take `from` for the tool's name. A `ref` without a `client` is
refused. The owner picks the request's identity, every value an attestation
states, and to whom a check's code is shown.

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

A connect link may also ask to read the owner's vault with `vault=read`,
and say why in `vault_reason` (up to 120 characters). The app offers it
switched off, with an explanation, and only when the answer goes to the
return address: the server refuses `allowVaultRead` together with `poll`
(`connection_vault_polled`), and a token collected by polling never reads the
vault even when the connection allows it. A polled answer is tied to the
owner only by a check code that whoever sent the link can read out to them;
a return address on `http://localhost` is reachable only from the owner's
own machine. An owner who already connected the tool is asked again when a
link asks for the vault and the connection does not have it.

### Its own section

With `section=1`, the owner is offered to give the tool a section of their
vault, named after it. That works with polling too: the section starts empty,
so a connect link sent by someone else reaches nothing the owner had. The tool
then keeps records and files there through [`/api/vault`](reference/vault.md),
reads them back, and — with `shares:manage` — shares them. What it writes
belongs to the owner, shows in their vault with the tool's name, and stays
when the tool is disconnected. The tool may change only what it wrote; a
record the owner adds to the section is read-only to it. The owner can also
let the tool read other sections of theirs, from the app. Taking the section
away from the tool keeps it in the vault, and giving it back brings the same
one.

With `permissions`, the tool asks for more than proposing: to create shares
(`shares:manage`) and requests (`requests:manage`) itself. Those join the
connection exactly as a saved proposal does. A request asks strangers for data
in the owner's name, so creating one needs the answer sent to the return
address, as the whole vault does: a token collected by polling is refused with
`connection_polled`.

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
not a user session and no collection rule admits it, so nothing outside these
endpoints can be read with it. The vault endpoints reach the tool's own
section and the sections the owner added; the whole vault only where the owner
allowed `allowVaultRead`, and only to a token that came through the return
address. The response to `GET /api/connection` says which: `permissions`,
`vaultAccess`, `section`, `sections` and `vaultReadable`.

| Endpoint | Does |
|---|---|
| `GET /api/connection` | The connection and what its proposals became, newest first. `links`: `id`, `ref`, `label`, `status`, `viewCount`, `maxViews`, `expiresAt`, `created`, `handedOver`, and `url` — only on a handed-over, active link while the owner allows `allowHandOver`. `requests`: `id`, `ref`, `label`, `status`, `responseCount`, `maxResponses`, `expiresAt`, `created` — never the address or the answers. `attestations`: `id`, `ref`, `type`, `label`, `status`, `subjectName`, `subjectFingerprint`, `subjectDomain`, `expiresAt`, `issuedAt`, `created` — never the claims or the offer token. `checks`: `id`, `ref`, `type`, `status`, `expiresAt`, `answeredAt`, `created`, and once answered a `verdict` with the claims the other person chose to show. |
| `POST /api/connection/links` | Creates a share of records and sections within reach, where the owner allowed `shares:manage`, and answers with its `url`. |
| `POST /api/connection/requests` | Creates a request in the owner's workspace, where the owner allowed `requests:manage`, and answers with the `revoked://r/…` link to pass on. It asks as the identity named in `identity`, or the workspace's primary one. Never with a token collected by polling (`connection_polled`). |
| `POST /api/connection/links/{id}/revoke` | Revokes one of those links, where the owner allowed `allowRevoke` or `shares:manage`. |
| `POST /api/connection/requests/{id}/close` | Stops one of those requests taking answers, where the owner allowed `allowRevoke` or `requests:manage`. Answers already given stay their responders' links. |
| `POST /api/connection/attestations/{id}/revoke` | Revokes one of those attestations, or withdraws its offer, where the owner allowed `allowRevoke` or `attestations:issue`. Final, like any revocation. |
| `GET /api/vault` | The records within reach: `id`, `key`, `label`, `type`, `format`, `updated`, `sections`, `writable`, `writtenByName` — no values. Encrypted records and answers others sent are left out. `403` with `connection_vault_not_allowed` or `connection_vault_polled`. |
| `GET /api/vault/{id}` | One of those records with its current `value` (an alias reads through to its entry; a file record gives `filename`, `mime` and `size`, and its bytes are at `/api/vault/{id}/file`). An encrypted record answers `404`, like a missing one. Each read is written to the audit log with the record's key, never its value. |
| `POST /api/vault` | Writes a record — JSON, or `multipart/form-data` with a `file` — into the tool's own section. `409` with `vault_key_taken`, `413` with `vault_storage_exceeded`. |
| `PATCH /api/vault/{id}`, `DELETE /api/vault/{id}` | Changes or deletes a record the tool wrote; `403` with `vault_read_only` for any other. |
| `DELETE /api/connection` | Disconnects the tool. The links remain the owner's. |

```bash
curl "$SERVER/api/connection" -H "X-Revoked-Connection: $TOKEN"
```

A `401` with `connection_unauthorized` means the tool was disconnected;
`connection_expired` means its 90 days have run out. In both cases the token
is of no further use, and a new connection can only be made by the owner,
from the app.

A `403` with `connection_paused` means the owner paused the tool. Keep the
token: it works again once they activate the tool. Until then the tool can't
connect another browser either, and the links and requests it proposed are
paused. The full
schemas are in the [Connections reference](reference/connections.md).

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
