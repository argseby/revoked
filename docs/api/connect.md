# Ways to connect

Everything outside the app reaches a server through one of a handful of
doors. They differ in **who holds the credential**. They don't differ in how
access is described: every key and every connected tool holds

- **permissions**, from the one catalogue at `GET /api/permissions`, and
- a **reach** into the vault: none, the sections chosen for it, or — only for
  an AI assistant the owner runs on their own machine — the whole vault.

Reach is checked on every request, at [`/api/vault`](reference/vault.md).
Taking a record out of a section takes it out of reach on the next request.
Encrypted records are out of every reach: the server can't read them.

## Selection examples

- A scheduled job updates a record in the operator's own workspace: an
  **API key**, with `vault:write` and a chosen section.
- A website lets visitors sign in: **Sign in with Revoked**. The website
  identifies each account by the verified issuer and subject, then creates
  its own session.
- An emergency-card service asks each person for selected medical details:
  a **tool proposal and connection**, approved separately by each owner.
- A CRM needs notifications when responses arrive: a **webhook**, followed by
  an authenticated read of the response. A per-request callback is another
  option when its different payload and delivery behavior are appropriate.
- A script reads a share it was given: the **share URL**, with any required
  password or identity check. A workspace API key is not needed merely to
  open a public share.

[Authentication](authentication.md#first-api-call) shows a first API-key call.
[Sign in with Revoked](sign-in.md#working-example) provides a runnable website.
[Building a tool](tools.md#a-minimal-tool) provides a complete proposal example.

## At a glance

| Door | Credential | Who holds it | Permissions | Vault reach | Read more |
|---|---|---|---|---|---|
| The app | Session (`Authorization: Bearer`) | A person, after a passkey | Their membership | Whole vault | [Authentication](authentication.md#signing-in) |
| API key | `X-API-Key` | The workspace's own scripts | Any from the catalogue, fixed at creation | The sections chosen for it | [Authentication](authentication.md#api-keys) |
| Connected tool | `X-Revoked-Connection` | Someone else's service, approved by the owner | `shares:read`, `shares:manage`, `requests:manage`, `attestations:issue`, `vault:read`, `vault:write` | Its own section, and any the owner adds | [Building a tool](tools.md) |
| AI assistant (`revoked-mcp`) | A connection | The owner, on their own machine | As a tool | As a tool, or the whole vault after the owner allows it | [MCP server](mcp.md) |
| Sign in with Revoked | OpenID Connect tokens | A service people sign in to | The claims the person picks | What the person shares at sign-in | [Sign in with Revoked](sign-in.md) |
| Request callback | None: the server posts to you | The requester | — | The answers to that request | [Callbacks](callbacks.md) |
| Share link | The slug | Whoever was given it | Read that share | What the share holds | [Shares](reference/shares.md) |
| Attestations | None to verify | Anyone | — | — | [Attestations](attestations.md) |

## What each one can't do

| Door | Never |
|---|---|
| API key | Read or write outside its sections; manage passkeys or the account; answer a request (that needs a person, who keeps the answer). |
| Connected tool | Anything not on the list above: members, templates, contacts and settings stay with people and keys. Change a record it didn't write. Reach the whole vault, or create a request in the owner's name, through a link someone could have sent the owner: a token collected by polling does neither. |
| AI assistant | The same as a tool. The whole vault only through the answer sent back to the owner's own machine. |
| Sign in with Revoked | Read the vault beyond what the person shared. |
| Share link | List other shares. Every slug stands alone. |

## A tool's own section

A tool that asks for it gets a section of the owner's vault, named after it,
when the owner connects it. It can keep records and files there, read them
back, and share them where it holds `shares:manage`:

```bash
curl -X POST "$SERVER/api/vault" -H "X-Revoked-Connection: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key":"packing_list","label":"Packing list","value":"tent, stove"}'
```

Everything it writes is the owner's: it shows in their vault marked with the
tool's name, and it stays when the tool is disconnected. The tool may change
only what it wrote. A record the owner adds to the section is theirs, and
read-only to the tool. What a tool keeps counts against
`CONNECTION_STORAGE_MB` (100 by default).
