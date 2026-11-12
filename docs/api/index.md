# API

Everything the app does, this API does — it is the same surface, with no
private endpoints held back. Operators run it under their own domain, so there
is no shared base URL: substitute your own host throughout. To try it, use the
official server, `https://api.revoked.link`. It is experimental and for testing,
with no guarantees for your data.

## Three common integrations

| Goal | Concrete example | First implementation |
|---|---|---|
| Automate an existing workspace | A scheduled job updates a `now_playing` record. | An [API key](authentication.md#first-api-call) with vault permissions and access to a chosen section. |
| Build a service for other vault owners | An emergency-card tool asks its user to share selected medical details. | A [proposal and connection](tools.md#example-a-guest-registration-tool) approved in that user's app. |
| Add account sign-in to a website | A shop signs a customer in and optionally asks for a delivery address. | The [Sign in with Revoked demo](sign-in.md#working-example), then the start, callback and wait routes. |

These credentials serve different purposes. A shop's sign-in token does not
open the customer's vault. An API key for one workspace does not authenticate
users of a website. A connection gives a tool the access its owner approved.

## Terms used in the examples

| Term | Meaning | Example |
|---|---|---|
| Server | A Revoked installation with its own domain and accounts. | `https://api.example.com` |
| Workspace | The container for records, shares, requests and members. | A company's workspace |
| Record | One stored value or file. | Key `shipping_address`, value `Musterstraße 12, Berlin` |
| Section | A group of records; also used to limit a key's vault access. | A `Delivery` section |
| Share | A link through which selected records can be read. | A delivery-address link sent to a shop |
| Request | A form asking other people for information. | A delivery-details request |
| Grant | Permission to read selected current values until access ends. | An approved address returned as a grant at sign-in |

Example domains such as `api.example.com` are placeholders. `$SERVER` in shell
examples is the Revoked server's origin, including `https://`, without a trailing
slash. Credentials and IDs must come from that same server.

## Where to start

| If you want to | Read |
|---|---|
| See every way in, side by side | [Ways to connect](connect.md) |
| Call the API from a script | [Authentication](authentication.md), then the [reference](reference/index.md) |
| Read or write vault data | [Records](reference/records.md) as a person, [Vault](reference/vault.md) as a key or tool |
| Consume a share someone sent you | [Shares](reference/shares.md) |
| Collect data from other people | [Requests](reference/requests.md), then [Callbacks](callbacks.md) |
| Hear about changes the moment they happen | [Webhooks](webhooks.md) |
| Build a tool that people share their data with | [Building a tool](tools.md) |
| Let an AI assistant organise your shares without seeing them | [MCP server](mcp.md) |
| Let people sign in to your service with their Revoked account | [Sign in with Revoked](sign-in.md) |
| Check something a third party confirmed about a person, or confirm such things yourself | [Attestations](attestations.md) |
| Verify who a share or request came from | [Trust chain](trust-chain.md) |
| Generate a client | [`openapi.yaml`](openapi.yaml) |

## Three things that will surprise you

**Grants are living, not snapshots.** A share resolves the record's *current*
value each time it is read. Rotating a secret updates every share pointing at
it, with no republish step — and revoking one takes effect on the next read,
not the next sync. This is the whole point of the product, and it means you
should not cache a resolve result any longer than you would cache the secret
itself.

**Public endpoints are protected by slug entropy alone.** Anything under
`/api/public` or `/s` is reachable by whoever holds the slug. Slugs are
unguessable by construction and never derived from anything user-visible, and
there is deliberately no endpoint that lists them. Treat a slug as the
credential it is.

**`/s/{slug}` content-negotiates.** A request whose `Accept` header prefers
`text/html` — which is to say, a browser — gets the share's viewer page, not
data. Scripts should ask for a concrete format (`.json`, `.csv`, `.vcf`,
`.ics`) or send an API-shaped `Accept` header, and can pass a gate password
as `?password=`.

## Error handling

Failures come back in one envelope:

```json
{ "code": "link_password_required", "message": "This link requires a password.", "status": 401 }
```

Key off `code`, never off `message` — the prose may be reworded, the code will
not. Authorization failures name what was missing rather than returning a bare
denial, so a 403 tells you which scope or grant you lack.

Error messages may echo values you sent, but never server-held state. That is
deliberate: an error outlives the credential that produced it and ends up in
logs, tickets and screenshots read by people who hold no key.

[Encrypted links and saved keys](encrypted-links.md) describes the client-side
formats, saved-share protection and explicit tool hand-over.
