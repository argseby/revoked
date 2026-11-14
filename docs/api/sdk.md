# JavaScript SDK

`@kiunke.dev/revoked` is a typed client for this API. It runs on Node 20 or later,
Deno, Bun, edge runtimes and browsers. It has no runtime dependencies, and
uses only `fetch` and WebCrypto. Every request in this section of the
documentation has an SDK method. Calls that only the Revoked app makes, such as
passkey sign-in or consent screens, are left out on purpose. The package lists
each of them, with the reason, in `coverage.json`.

```bash
npm install @kiunke.dev/revoked
```

## A first script

An [API key](authentication.md#api-keys) with **Manage vault** for one
section and **Manage shares** is enough to store a value and share it. Saved
as `share.mjs` and run with `node --env-file=.env share.mjs`, where `.env`
holds `REVOKED_API_KEY`:

```js
import { Revoked } from '@kiunke.dev/revoked';

const revoked = new Revoked({ server: 'https://api.example.com', apiKey: process.env.REVOKED_API_KEY });

const record = await revoked.vault.create({ key: 'wifi_password', label: 'Wi-Fi password', value: 'correct-horse' });
const link = await revoked.links.create({ label: 'Wi-Fi for guests', records: [record.id], maxViews: 5 });

console.log(revoked.links.url(link));
```

The printed address opens the share in a browser. Changing the record changes
what the share shows on its next read; `revoked.links.revoke(link.id)` ends
it.

## Credentials

A client acts with at most one credential. Each credential travels in its own
header, as described in [Authentication](authentication.md).

| Option | Header | Use |
|---|---|---|
| `apiKey` | `X-API-Key` | Scripts and integrations of the workspace's own |
| `connection` | `X-Revoked-Connection` | A [connected tool](tools.md), for what its owner approved |
| `session` | `Authorization: Bearer` | Code acting as a signed-in person; the token is renewed when it expires |
| none | — | Shares, requests and grants reached by slug or token |

```ts
import { Revoked } from '@kiunke.dev/revoked';

const revoked = new Revoked({
  server: 'https://api.example.com',
  apiKey: process.env.REVOKED_API_KEY,
});
```

Collection writes are bound to a workspace, and the server compares the
`workspace` field with the caller's. The SDK fills it in. For a session, it
reads the active workspace from the account. For an API key, it asks
`GET /api/me`. On a server without that endpoint, the workspace id is passed
as `workspace` when the client is created.

## Shares

```ts
const record = await revoked.vault.create({ key: 'shipping_address', label: 'Delivery address', value: 'Musterstraße 12, Berlin' });
const link = await revoked.links.create({ label: 'Delivery address', records: [record.id], maxViews: 3 });

revoked.links.url(link);      // https://api.example.com/s/<slug>
await revoked.links.revoke(link.id);
```

A share's slug is 24 random characters, drawn from a cryptographic random
source, unless one is given. Anything shorter can be guessed.

An API key or a connected tool reaches the vault through `revoked.vault`,
which covers only the sections it was given and lets it change only the
records it wrote. `revoked.records` is the vault as a signed-in person sees
it.

```ts
const entries = await revoked.vault.list();
const phone = await revoked.vault.find('phone');
await revoked.vault.create({ key: 'now_playing', label: 'Now playing', value: 'Track 7', section: sectionId });
```

`section` takes a section's id, which **Copy ID (API)** in the section's
menu puts on the clipboard. Left out, the record goes into the key's first
section.

## Opening a share

```ts
import { createPublicClient } from '@kiunke.dev/revoked/public';

const client = createPublicClient({ server: 'https://api.example.com' });
const preview = await client.links.preview(slug);   // gates only; consumes no view
const share = await client.links.open(slug, { password });
```

`open` consumes one view and is never retried. For a share that requires a
proven identity, the identity's key signs the server's challenge on this
device. The returned `handshakeToken` skips the signature on the next read:

```ts
import { generateIdentityKey } from '@kiunke.dev/revoked/identity';

const key = await generateIdentityKey();
const identity = await revoked.identities.createFromKey(key, { name: 'Billing' });
const share = await client.links.open(slug, { identity: { id: identity.id, key } });
```

The private key is generated with WebCrypto and is not extractable unless
`extractable: true` is passed. Only the public key reaches the server.

Encrypted entries are opened with the key after `#k=` in the share's address,
which never reaches the server:

```ts
import { openSealedShare } from '@kiunke.dev/revoked/sealed';

const { opened } = await openSealedShare(client.links, 'https://api.example.com/s/<slug>#k=<key>');
```

## Requests

```ts
const request = await revoked.requests.create({ label: 'Delivery details', template: templateId });
revoked.requests.appLink(request);          // revoked://r/… for the responder
const answers = await revoked.requests.responses(request.id);
```

Answering a request takes a session on the request's server
(`revoked.public.requests.submit`). The answer becomes a grant in the
responder's own workspace.

## Example: collecting details and following the answer

A shop asks a customer for delivery details, is told the moment they answer,
reads the current values, and hears when the customer withdraws them. The API
key needs **Manage requests**, **View requests**, **View identities** (the
request asks as the workspace's primary identity) and **Manage webhooks**. `PUBLIC_URL` is an address the Revoked server can reach. A server
started with `ALLOW_PRIVATE_CALLBACKS=true` also delivers to `localhost`.

```ts
import { createServer } from 'node:http';
import { Revoked } from '@kiunke.dev/revoked';
import { verifyWebhook } from '@kiunke.dev/revoked/webhooks';

const revoked = new Revoked({ server: process.env.REVOKED_SERVER!, apiKey: process.env.REVOKED_API_KEY! });

const request = await revoked.requests.create({ label: 'Delivery details', template: process.env.TEMPLATE_ID, maxResponses: 1 });
console.log('Link for the customer:', revoked.requests.appLink(request));

const endpoint = await revoked.webhooks.endpoints.create({
  url: `${process.env.PUBLIC_URL}/hooks/revoked`,
  events: ['response.submitted', 'response.changed', 'response.revoked'],
});

createServer(async (req, res) => {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  let event;
  try {
    event = await verifyWebhook({
      body: Buffer.concat(chunks).toString('utf8'),
      signature: req.headers['revoked-signature'] as string | undefined,
      secret: endpoint.secret,
    });
  } catch {
    res.writeHead(400).end();
    return;
  }
  res.writeHead(204).end();

  switch (event.type) {
    case 'response.submitted':
    case 'response.changed': {
      const [answer] = await revoked.requests.responses(request.id);
      console.log(`${answer?.senderName} answered:`, answer?.data);
      break;
    }
    case 'response.revoked':
      console.log('The answer was withdrawn. Its values are no longer readable.');
      break;
  }
}).listen(4000);
```

The answer is a living grant in the customer's own workspace. When they
correct the address in their vault, `response.changed` arrives and
`responses` returns the new value. When they revoke it, the values stop being
readable. No copy is left behind.

## Webhooks

```ts
import { verifyWebhook } from '@kiunke.dev/revoked/webhooks';

const event = await verifyWebhook({
  body: rawBody,                                  // the bytes as received
  signature: request.headers.get('Revoked-Signature'),
  secret: process.env.REVOKED_WEBHOOK_SECRET,
});
switch (event.type) {
  case 'link.revoked':
    console.log(event.data.id, event.data.kind);
    break;
}
```

The signature, its age (300 seconds by default) and both secrets during a
rotation are checked as described in
[Verifying the signature](webhooks.md#verifying-the-signature). Deliveries can
repeat. Duplicates are recognised by `event.id`.

## Connected tools

`@kiunke.dev/revoked/connect` builds `revoked://p`, `revoked://pr` and
`revoked://connect` links, validates them as the app does, and completes the
connection:

```ts
import { connectLink, createPkce, createState, exchangeCode, readAnswer } from '@kiunke.dev/revoked/connect';

const pkce = await createPkce();
const state = createState();
const link = connectLink({
  client: 'https://tool.example',
  name: 'Guestbook',
  answer: { redirect: 'https://tool.example/callback', state, challenge: pkce.challenge },
  section: {},
});
// Back at the return address:
const answer = readAnswer(location.href, state);
const { token } = await exchangeCode({ server: answer.server, code: answer.code!, verifier: pkce.verifier, redirectUri: 'https://tool.example/callback' });
const tool = new Revoked({ server: answer.server, connection: token });
```

`pollForToken` collects a polled answer instead. `checkCode` returns the code
both sides display.

## Trust chain

`@kiunke.dev/revoked/trust` checks the [trust chain](trust-chain.md) on the device
rather than trusting any one server's verdict. A DNS lookup function is
required. The SDK sends no domain name to a resolver it was not given.

```ts
import { verifySharer } from '@kiunke.dev/revoked/trust';
import { promises as dns } from 'node:dns';

const verdict = await verifySharer(preview.sharer, { resolveTxt: (name) => dns.resolveTxt(name) });
// verdict.state: 'verified' | 'dnsMissing' | 'unverified' | 'spoofed' | 'revoked'
```

## Errors

Every failure is a `RevokedError` with the HTTP `status`, the server's stable
`code`, and `fields` for validation errors. Subclasses support `instanceof`
checks: `ValidationError`, `AuthenticationError`, `PermissionError`,
`NotFoundError`, `ConflictError`, `GoneError` (revoked, expired or used up),
`PayloadTooLargeError`, `RateLimitedError` (with `retryAfter`), `ServerError`,
`NetworkError` and `TimeoutError`.

`code` is typed with every code the server sends. A newer server's code still
passes through unchanged. [Error codes](errors.md) lists each one with its
message.

## Lists, filters and retries

```ts
import { f } from '@kiunke.dev/revoked';

for await (const link of revoked.links.iterate({ filter: f`status = ${'active'} && label ~ ${userInput}` })) {
  // every page, in order
}
```

`f` escapes each interpolated value, so input cannot add a clause of its own.
`GET` requests and calls documented as idempotent are retried after a network
failure or a `502`, `503` or `504`. A `429` is retried only when the server
asks for a wait under `retry.maxWaitMs`, which defaults to 10 seconds. A
request that consumes something, such as a view, a nonce or a single-use
download token, is never retried.

## Versions

The SDK is versioned apart from the server and stays in `0.x` while the API
does. A newer server's fields, enum values, error codes and webhook event
types reach the caller untouched. Any route can be called with
`revoked.request(path, options)`, with the client's credential, retries and
error decoding.
