# @kiunke.dev/revoked

A TypeScript client for the [Revoked](https://github.com/argseby/revoked) API:
shares, requests, vault records, identities, attestations, webhooks and
connected tools. It runs on Node 20 or later, Deno, Bun, edge runtimes and
browsers, and needs only `fetch` and WebCrypto. It has no runtime
dependencies.

```bash
npm install @kiunke.dev/revoked
```

## A first script

An API key with **Manage vault** for one section and **Manage shares**:

```js
import { Revoked } from '@kiunke.dev/revoked';

const revoked = new Revoked({ server: 'https://api.example.com', apiKey: process.env.REVOKED_API_KEY });

const record = await revoked.vault.create({ key: 'wifi_password', label: 'Wi-Fi password', value: 'correct-horse' });
const link = await revoked.links.create({ label: 'Wi-Fi for guests', records: [record.id], maxViews: 5 });
console.log(revoked.links.url(link));
```

```bash
node --env-file=.env share.mjs
```

Changing the record changes what the share shows on its next read.
`revoked.links.revoke(link.id)` ends it.

## Collecting details and following the answer

A request asks someone for data. The answer stays theirs, as a living grant
they can correct or withdraw. A webhook reports each change:

```ts
import { createServer } from 'node:http';
import { Revoked } from '@kiunke.dev/revoked';
import { verifyWebhook } from '@kiunke.dev/revoked/webhooks';

const revoked = new Revoked({ server: process.env.REVOKED_SERVER!, apiKey: process.env.REVOKED_API_KEY! });

const request = await revoked.requests.create({ label: 'Delivery details', maxResponses: 1 });
console.log('Link for the customer:', revoked.requests.appLink(request));

const endpoint = await revoked.webhooks.endpoints.create({
  url: `${process.env.PUBLIC_URL}/hooks/revoked`,
  events: ['response.submitted', 'response.changed', 'response.revoked'],
});

createServer(async (req, res) => {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const event = await verifyWebhook({
    body: Buffer.concat(chunks).toString('utf8'),
    signature: req.headers['revoked-signature'] as string | undefined,
    secret: endpoint.secret,
  }).catch(() => undefined);
  res.writeHead(event ? 204 : 400).end();

  if (event?.type === 'response.submitted' || event?.type === 'response.changed') {
    const [answer] = await revoked.requests.responses(request.id);
    console.log(`${answer?.senderName} answered:`, answer?.data);
  }
  if (event?.type === 'response.revoked') console.log('The answer was withdrawn.');
}).listen(4000);
```

The key needs **Manage requests**, **View requests**, **View identities** and
**Manage webhooks**. The [guide](https://docs.revoked.link/api/sdk/) covers
the rest: opening shares with a proven identity, encrypted shares, connected
tools, the trust chain, errors and pagination.

## Entry points

| Import | Contents |
|---|---|
| `@kiunke.dev/revoked` | The `Revoked` client, errors, filters and types |
| `@kiunke.dev/revoked/public` | Shares, requests and grants reached by slug or token, without a credential |
| `@kiunke.dev/revoked/connect` | Proposal and connect links, PKCE, the check code, code exchange and polling |
| `@kiunke.dev/revoked/webhooks` | `verifyWebhook` and the typed event union |
| `@kiunke.dev/revoked/identity` | Local P-256 identity keys and challenge signatures |
| `@kiunke.dev/revoked/trust` | DNS pin, server assertion, root signature and identity status checks |
| `@kiunke.dev/revoked/sealed` | Opening end-to-end encrypted shares with the key from their address |

`coverage.json` maps every operation in the server's OpenAPI document to the
method that calls it, or names why it is left out. Writing end-to-end
encrypted records is left out until the protocol has had its cryptographic
review.

## Development

```bash
npm ci
npm run check && npm test && npm run build && npm run lint:package
```

`src/generated/` is written by `go run ./cmd/gen-sdk` from the repository
root, and a Go test fails while it is stale. The integration suite in
`test/integration/` runs against a real server from the Go test
`TestJavaScriptSDK` (`go test ./tests/ -run TestJavaScriptSDK`). Its tests
use the frozen vectors in `app/test/fixtures/`, which are never regenerated.

Releases are cut from `main` by `.github/workflows/sdk-js-release.yml`. The
version follows the Conventional Commits that touched this directory, and
each release is tagged `sdk-js-v<version>`.

## License

GPL-3.0-only.
