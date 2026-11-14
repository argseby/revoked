# @kiunke.dev/n8n-nodes-revoked

[n8n](https://n8n.io) nodes for [Revoked](https://github.com/argseby/revoked):
shares, requests, vault records, templates, contacts, attestations and
webhooks, and a trigger on webhook events. Built on
[`@kiunke.dev/revoked`](../revoked-js).

## Installation

In n8n, **Settings → Community nodes → Install**, with the package name
`@kiunke.dev/n8n-nodes-revoked`. The [n8n
guide](https://docs.n8n.io/integrations/community-nodes/installation/) covers
self-hosted and queue-mode installs.

## Credential

**Revoked API** takes the server's origin and an API key created in the app.
The key's permissions and vault sections are fixed when it is created. A key
never reaches the whole vault: vault operations see only its sections, and
change only records the key wrote itself.

| Used for | Permissions |
|---|---|
| Shares | Manage shares, View shares |
| Requests | Manage requests, View requests, View identities; Read collected data for answers to requests made by others |
| Templates | Manage templates, View templates |
| Vault records | Manage vault or Read vault, with sections |
| Contacts | Manage contacts, View contacts |
| Attestations | Issue attestations, View attestations |
| Identities | View identities |
| Webhooks and the trigger | Manage webhooks; View requests for **Include Answer** |

## Revoked node

| Resource | Operations |
|---|---|
| Share | Create, Delete, Get, Get Many, Pause, Resume, Revoke, Update |
| Request | Close, Create, Delete, Get, Get Answers, Get Many, Pause, Resume |
| Vault Record | Create, Delete, Download File, Get, Get by Key, Get Many, Update |
| Template | Create, Delete, Get, Get Many, Update |
| Contact | Create, Delete, Get, Get Many, Update |
| Attestation | Get, Get Many, Issue, Revoke |
| Identity | Get, Get Many |
| Webhook Endpoint | Create, Delete, Get, Get Many, Rotate Secret, Send Test Event, Update |
| Webhook Delivery | Get, Get Many, Resend |
| Webhook Event | Get Many |

A created share carries `url`, its browser address, and `appLink`. A created
request carries `appLink`, the address to hand to whoever should answer.
Answering takes an account on the request's server, and the answer stays the
responder's grant: they can correct or withdraw it later, and **Get Answers**
always returns the current values.

Each vault read appears in the owner's audit log. Encrypted records are not
listed. A vault record holds a file when **Input Binary Field** names a binary
field of the input item; **Download File** returns it as binary data.

An issued attestation carries `offerLink`, the address the subject opens to
accept it. Issuing signs in the name of the server's domain.

Not available to API keys, and so not in the node: sending to a contact or
asking a contact for data, attestation checks and shares of credentials,
and creating identities (the private key never leaves the owner's device).
Workspace members, invites and groups are left out: they stay in the app.

## Revoked Trigger

The trigger registers a webhook endpoint on the server when the workflow is
activated and removes it when the workflow is deactivated. Every delivery's
signature is checked against the endpoint's secret; an unsigned, foreign or
stale delivery is refused with 401 and does not start the workflow.

- The server must reach the n8n webhook address. A private or loopback
  address is refused unless the server runs with `ALLOW_PRIVATE_CALLBACKS`.
- Deliveries can repeat, and can arrive out of order. The event `id` is the
  same on every delivery of one event; the **Remove Duplicates** node can drop
  repeats by it. Order by `created`.
- Events carry ids, not values. **Include Answer** adds the answer with its
  current values to `response.*` events.

## Development

```bash
npm ci
npm run check && npm test && npm run lint && npm run build
```

### A local n8n and Revoked server

`dev/docker-compose.yml` runs n8n with this package mounted, on
`http://localhost:5678`. Host networking puts n8n and the Revoked server on
the same `localhost`, so each reaches the other.

1. Start a Revoked server that accepts webhooks to private addresses, on
   port 3124 with its data in `dev/pb_data/`:

   ```bash
   cd cmd/revoked && DOMAIN=localhost ALLOW_SIGNUPS=true ALLOW_PRIVATE_CALLBACKS=true \
     go run main.go serve --http=127.0.0.1:3124 --dir=../../packages/n8n-nodes-revoked/dev/pb_data
   ```

2. Build the package and start n8n:

   ```bash
   cd packages/n8n-nodes-revoked && npm run build && docker compose -f dev/docker-compose.yml up -d
   ```

3. In the Revoked app, sign in to `http://localhost:3124`, create a vault
   section, and create an API key with the permissions in the table above and
   that section.
4. In n8n, create the owner account, then a **Revoked API** credential with
   server `http://localhost:3124` and the key.

After a code change, `npm run build && docker compose -f dev/docker-compose.yml restart`.
`N8N_LOG_LEVEL=debug docker compose -f dev/docker-compose.yml up -d` logs
which nodes n8n loaded. `docker compose -f dev/docker-compose.yml down -v`
removes n8n and its data.

## License

MPL-2.0.
