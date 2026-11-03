<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="app/assets/icon/revoced-mark-redacted-white-on-black.svg">
    <img src="app/assets/icon/revoced-mark-redacted-black-on-white.svg" alt="Revoked logo" width="96">
  </picture>
  <h1>revoked</h1>

**Access, not copies.**<br>
The client and server infrastructure for exchanging data.

[Website](https://revoked.link) · [Docs](https://docs.revoked.link) · [Install the app](https://github.com/argseby/revoked/releases/latest) · [Developer API](https://docs.revoked.link/api/)

[![License: ELv2](https://img.shields.io/badge/License-Elastic_v2-blue.svg)](https://www.elastic.co/licensing/elastic-license)
[![Status: Experimental](https://img.shields.io/badge/status-experimental-yellow)](#)
[![Windows](https://img.shields.io/badge/Windows-0078D6?logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0wIDBoMTEuNHYxMS40SDB6TTEyLjYgMEgyNHYxMS40SDEyLjZ6TTAgMTIuNmgxMS40VjI0SDB6TTEyLjYgMTIuNkgyNFYyNEgxMi42eiIvPjwvc3ZnPg==)](#)
[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](#)
[![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)](#)

<a href="https://revoked.link/#film"><img src="docs/assets/film-poster.jpg" alt="Access, not copies. Watch the film on revoked.link." width="720"></a>

<sub>Watch the films on [revoked.link](https://revoked.link/#film)</sub>

</div>

## Why a link beats a copy

When someone needs your address, your bank details or a password, you send them
a copy. After that, you can't change it and you can't get it back. When you need
someone else's data, you end up holding a copy of theirs.

With Revoked, the data stays with its owner, in their vault. Whoever shares it or
requests it works with a link.

- **Always up to date.** Change a password in your vault, and everyone you
  shared it with sees the new one. You never send it again.
- **Yours to take back.** Pause or revoke a link, and it stops working the next
  time someone opens it. Not at the next sync.
- **Proof of who sent it.** Shares and requests can carry the sender's identity,
  tied to their domain. When something says it comes from example.com, the app
  checks that it really does.

Run Revoked on your own server, and your data, your keys and your domain all stay
under your control. Just want to try it? Use the official test server,
[below](#try-it). Use the app, or build on the API.

> [!WARNING]
> While this project is in active development, it's more a **proof-of-concept**.
> Feel free to use it for your use-cases, but don't expect production-ready
> support.

## What you can do with it

| | What it does | For example | Learn more |
|---|---|---|---|
| **Sign in** | People sign in to your service with their Revoked account. You keep no passwords, and each service gets its own ID for them. | A shop that reads the delivery address when it ships, and never stores it | [Sign in with Revoked](https://docs.revoked.link/api/sign-in/) |
| **Share** | A share is a link to records in your vault. Add a password, an expiration date, maximum views or a watermark. | Server passwords for a contractor, revoked when the job ends | [Sharing](https://docs.revoked.link/guide/sharing/) |
| **Collect** | A request asks other people for information. When they answer from their vault, you get a link to their data, not a copy. | Tax ID and bank details for payroll that stay current | [Requests](https://docs.revoked.link/guide/requests/) |
| **Prove** | The app checks who sent something against their domain. An attestation is something someone else confirms about you, and you decide which details to show. | An age check that never touches an ID card | [Identities & trust](https://docs.revoked.link/guide/identities/), [Attestations](https://docs.revoked.link/guide/attestations/) |
| **Connect** | A tool can propose links and see their status and views. It never sees what they contain. | An emergency card maker that revokes the link when you delete the card | [Tools & link proposals](https://docs.revoked.link/guide/tools/) |

Also included:

- End-to-end encrypted text records that not even your server can read
- Shares you can open as JSON, CSV, vCard or iCal, or subscribe to over CardDAV
- Requests and answers across Revoked servers
- Workspaces, members, API keys and an audit log

**Do people need an account?** To open a share, no. The link is enough. To answer
a request or sign in with Revoked, yes, along with the app.

## Try it

Follow [Try it in 5 minutes](https://docs.revoked.link/try/), or in short:

1. [Install the app](https://docs.revoked.link/installation/app/).
2. On the login screen, tap the server, enter `https://api.revoked.link`, and
   press **Test** and **Save**.
3. Create an account, add a record to your vault and press **Share**.

`api.revoked.link` is the official server. It's experimental and for testing,
with no guarantees for your data, so keep nothing there you can't lose.

Prefer your own computer? You need Go. Enter `http://localhost:3000` in step 2
instead:

```bash
git clone https://github.com/argseby/revoked && cd revoked
DOMAIN=localhost ALLOW_SIGNUPS=true go run ./cmd/revoked serve --http=127.0.0.1:3000
```

## Run your own server

You run one Go binary with a built-in database, in a container, behind a reverse
proxy that handles TLS. You need a domain and Docker with Compose.

```bash
git clone https://github.com/argseby/revoked && cd revoked
docker network create proxy-network   # once, or reuse your proxy's network
cp .env.example .env                  # set DOMAIN
docker compose up -d --build
docker compose logs api               # prints the DNS record to publish
```

Then publish that DNS record, point your proxy at the container, add people and
set up backups. [Set up a server](https://docs.revoked.link/installation/) walks
you through it.

## Build on it

Everything the app does, this API does. There are no private endpoints. Read the
current value of a link whenever you need it:

```bash
curl -X POST "https://$SERVER/api/grants/resolve" \
  -H "Content-Type: application/json" \
  -d '{"grants":[{"id":"q8w2…","token":"…"}]}'
```

```json
{ "items": [{ "id": "q8w2…", "status": "active",
              "values": { "shipping_address": "Musterstraße 12, 10115 Berlin" },
              "etag": "…", "maxAge": 60 }] }
```

Once it's revoked, the next read returns `"status": "revoked"` and no values.

- [Labs](https://docs.revoked.link/labs/): learn each part by using it, with the
  result you should see at every step
- [How it works](https://docs.revoked.link/how-it-works/), with a diagram of every
  flow
- [Developer API](https://docs.revoked.link/api/), with an
  [OpenAPI file](docs/api/openapi.yaml)
- [Add sign-in to your service](https://docs.revoked.link/api/sign-in/), with a
  [drop-in button](examples/sign-in-button) and a
  [complete example shop](examples/sign-in-demo)
- [Build a tool](https://docs.revoked.link/api/tools/) that people share their
  data with
- [Let your AI assistant help](https://docs.revoked.link/guide/assistant/)
  with an MCP server that suggests shares, requests and attestations for you
  to confirm. It reads your vault only if you allow it
  ([developer details](https://docs.revoked.link/api/mcp/))

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers the repository layout, running it from
source, tests and how releases work. Planned work is on the
[roadmap](https://docs.revoked.link/roadmap/).

## Licence

[Elastic License 2.0](LICENSE). Self-host it, build on it, don't sell it as a
service.
