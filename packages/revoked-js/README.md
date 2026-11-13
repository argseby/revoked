# @kiunke.dev/revoked

A TypeScript client for the [Revoked](https://github.com/argseby/revoked) API:
shares, requests, vault records, identities, attestations, webhooks and
connected tools. It runs on Node 20 or later, Deno, Bun, edge runtimes and
browsers, and needs only `fetch` and WebCrypto. It has no runtime
dependencies.

```bash
npm install @kiunke.dev/revoked
```

```ts
import { Revoked } from '@kiunke.dev/revoked';

const revoked = new Revoked({ server: 'https://api.example.com', apiKey: process.env.REVOKED_API_KEY });

const link = await revoked.links.create({ label: 'Delivery address', records: [recordId], maxViews: 3 });
console.log(revoked.links.url(link));
```

| Import | Contents |
|---|---|
| `@kiunke.dev/revoked` | The `Revoked` client, errors, filters and types |
| `@kiunke.dev/revoked/public` | Shares, requests and grants reached by slug or token, without a credential |
| `@kiunke.dev/revoked/connect` | Proposal and connect links, PKCE, the check code, code exchange and polling |
| `@kiunke.dev/revoked/webhooks` | `verifyWebhook` and the typed event union |
| `@kiunke.dev/revoked/identity` | Local P-256 identity keys and challenge signatures |
| `@kiunke.dev/revoked/trust` | DNS pin, server assertion, root signature and identity status checks |
| `@kiunke.dev/revoked/sealed` | Opening end-to-end encrypted shares with the key from their address |

Guide: [docs/api/sdk.md](https://github.com/argseby/revoked/blob/main/docs/api/sdk.md).

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
