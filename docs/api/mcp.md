# MCP server

`revoked-mcp` lets an AI assistant organise shares, requests and
attestations for the owner of a vault over the
[Model Context Protocol](https://modelcontextprotocol.io). It is a
[connected tool](tools.md) that runs on the owner's machine, and it can do
exactly what a tool can: propose, follow what became of a proposal, and end
it. It never reads a value.

That limit is deliberate. Whatever an MCP tool returns lands in the model's
context, and from there with the model provider, so a secret that reached it
could not be taken back by revoking anything. The assistant therefore names
things — record keys, a template, claim names — and the owner fills in the
values and saves in their app. Even a link the owner hands over to the
connection is not passed on: `list_shares` drops its `url`. A request's
answers and an attestation's values never reach the connection at all.

The one exception is a check. Its point is to tell the asker what the other
person showed, so `list_checks` returns the verdict with the claims they
chose to disclose.

## Who can use it

Anyone can run `revoked-mcp` against any server, and on its own it gets
nothing. It never signs in. Everything it can read or end goes through a
connection, and a connection exists only once a signed-in user of that
server approves it in the app (`POST /api/connections/authorize` requires a
`users` session). Proposals make no server call at all: a `revoked://` link
does nothing until an account holder opens it and saves.

So the account holder decides, and the risk is the usual one for a tool
that collects its answer by polling: someone could send them a connect link
for an assistant they don't run. Two things don't protect against that:

- **The check code** ties the app's request to the page or process that
  asked. It says nothing about who is behind it, so whoever sent the link
  can just tell the victim the code.
- **The client origin.** The app shows the tool's host, and for
  `revoked-mcp` that is `localhost`, which any program on any machine can
  claim. The server hands a polled answer only to a request whose `Origin`
  matches, but outside a browser that header is whatever the caller sends;
  `revoked-mcp` sets it itself.

What such a connection gets is still bounded: the status of what was
proposed through it, the verdicts of its checks, and — only if the owner
ticked **End what it proposed** — ending those. Never a value, never the
vault. Approve an assistant only if you started it yourself.

## Running it

Build it from this repository and point it at the owner's server:

```bash
go build -o revoked-mcp ./cmd/revoked-mcp
```

```json
{
  "mcpServers": {
    "revoked": {
      "command": "/path/to/revoked-mcp",
      "env": { "REVOKED_SERVER": "https://api.revoked.link" }
    }
  }
}
```

| Flag | Environment | Default | Meaning |
|---|---|---|---|
| `-server` | `REVOKED_SERVER` | — (required) | The owner's server origin, as the owner entered it. |
| `-name` | `REVOKED_MCP_NAME` | `AI assistant` | The name shown in the app, up to 40 characters. |
| `-client` | `REVOKED_MCP_CLIENT` | `http://localhost:47303` | The origin the assistant connects as. Its own port keeps it apart from a tool developed on `localhost`. |
| `-state` | `REVOKED_MCP_STATE` | `<user config dir>/revoked/mcp-connection.json` | Where the connection token is kept, mode `0600`. |
| `-no-open` | | off | Return `revoked://` links without opening them. |

By default the server opens each `revoked://` link with the desktop's handler
(`xdg-open`, `open`, `rundll32`), which passes it to the installed app. The
link is returned either way, for the owner to open on another device.

## Tools

| Tool | Does |
|---|---|
| `connect` | Builds a `revoked://connect` link with `poll` set to the server, and returns it with the check code. The owner approves in the app only if the app shows the same code. Asks for `allowRevoke`; it never asks to receive links. |
| `connection_status` | While a connect is pending, polls `POST /api/connect/token` once (with `Origin` set to the client origin) and stores the token on success. Once connected, reports the connection's name, expiry, `allowRevoke` and how many shares, requests, attestations and checks it follows. |
| `propose_share` | Builds a `revoked://p` link from `label`, `keys`, and optionally `template`, `days` and `ref`, checked against the [proposal rules](tools.md#1-the-proposal). `from` and `client` are filled in, so the share joins the connection. |
| `list_shares` | `GET /api/connection`: each share's `id`, `ref`, `label`, `status`, `viewCount`, `maxViews`, `expiresAt`, `created` and `handedOver` — never its `url`. |
| `revoke_share` | `POST /api/connection/links/{id}/revoke`. |
| `propose_request` | Builds a `revoked://pr` link from `template`, and optionally `label`, `days` and `ref`. |
| `list_requests` | Each request's `id`, `ref`, `label`, `status`, `responseCount`, `maxResponses`, `expiresAt` and `created`. |
| `close_request` | `POST /api/connection/requests/{id}/close`. |
| `propose_attestation` | Builds a `revoked://attest` link from `type`, `for` (the subject's fingerprint, for example a holder from `list_checks`), and optionally `claims` and `ref`. Needs attesting switched on for the owner's server. |
| `list_attestations` | Each attestation's `id`, `ref`, `type`, `label`, `status` and subject — never its claims. |
| `revoke_attestation` | `POST /api/connection/attestations/{id}/revoke`. Final. |
| `propose_check` | Builds a `revoked://check` link from optional `type`, `issuers`, `claims` and `ref`. |
| `list_checks` | Each check's `id`, `ref`, `type`, `status`, and once answered its `verdict`: `state`, `issuer`, `type`, the disclosed `claims`, `withheld`, `status` and `holder`. |
| `disconnect` | `DELETE /api/connection`, then forgets the token. Everything it proposed stays the owner's. |

The three tools that end something are refused unless the owner allowed it
when connecting. Everything proposed, and every list, is described with its
link format in [Building a tool](tools.md#requests-attestations-and-checks).

A pending connect lives in memory for ten minutes; restarting the server
abandons it. A `401` from the server forgets the token, since only the owner
can connect the assistant again. A `403` with `connection_paused` keeps it.
