
> [!WARNING]
> Back in 2019 I've participated in a founding competition with this idea, that I now developed in GO and Flutter. It's actively maintained and developed, but more as **Proof-of-Concept**, than a ready to run **SAAS**. Feel free to use it for your use-cases.
<div align="center">
  <h1>revoked</h1>

[![License: ELv2](https://img.shields.io/badge/License-Elastic_v2-blue.svg)](https://www.elastic.co/licensing/elastic-license)
[![Status: Experimental](https://img.shields.io/badge/status-experimental-yellow)](#)
</div>

**Revoked** replaces stale copies of data with a reference, that resolves its current value at read time and stops working the moment you revoke it. While the idea is not new, the following table describes the features my implementation tries to solve.

| Area           | Feature                   | What it does                                                                                                                              |
|----------------|---------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| **Vault**      | Records                   | Key/value entries with a type and a format; hidden values are masked until revealed                                                       |
|                | Sections                  | Named groups of records, shareable as a unit                                                                                              |
|                | Aliases                   | A record can point at another, resolving the parent's current value — how you answer someone's requested key with data you already hold   |
|                | Templates                 | Blueprints that materialise a whole set of sections and records in one go                                                                 |
| **Shares**     | Living grants             | A `/s/{slug}` link that resolves the *current* value on every read — never a copy                                                         |
|                | Instant revocation        | `active` / `paused` / `revoked` / `expired`, flipped unilaterally at any time                                                             |
|                | View caps                 | Enforced by a single guarded `UPDATE`, so concurrent readers can't all pass the same check                                                |
|                | Gates                     | Password, expiry date, required identity, or a cryptographic handshake before anything resolves                                           |
|                | Consumable formats        | JSON, CSV, vCard, iCal and CardDAV, with ETag/304 — the recipient uses their existing address book or spreadsheet, and adopts nothing     |
| **Requests**   | Public collection         | A `/r/{slug}` page that asks others for data, structured by a template                                                                    |
|                | Vault prefill             | A signed-in responder answers from their own vault instead of retyping                                                                    |
|                | Symmetric grants          | An answer becomes the same revocable link primitive — the responder can withdraw it later                                                 |
|                | Trust gate                | Verifies the requester's domain before submission; a spoof is a hard block, anything unverified needs an explicit confirmation            |
|                | Callbacks                 | Webhook on submission, fetched through an SSRF-guarded client that refuses redirects and re-checks the resolved IP                        |
| **Identity**   | On-device keys            | ECDSA P-256 generated locally; the private key never leaves the device                                                                    |
|                | DNS trust anchor          | `_revoked.<domain>` TXT pins the server's root key; identities are signed by it and verified over DNS-over-HTTPS with a fallback resolver |
|                | Verdicts                  | Verified / DNS missing / unverified / spoofed — with the *reason* shown, never a bare badge                                               |
|                | Handshake                 | Challenge–nonce–signature, proving possession of a key before gated data resolves                                                         |
| **Access**     | Workspaces                | Members, invites with per-permission grants, single-use and email-pinned options, escalation and last-admin guards                        |
|                | One permission vocabulary | The same catalogue governs people and API keys, served from `GET /api/permissions` so the client can't drift                              |
|                | API keys                  | Scoped, expiring, shown once and stored only as a hash                                                                                    |
| **Operations** | Self-hosted               | Docker stack under your own domain; registration off by default                                                                           |
|                | Rate limits               | Sliding windows on password gates, probes and challenges                                                                                  |
|                | Audit log                 | Server-side record of what was accessed and changed                                                                                       |

## What's in here

| Path | |
|---|---|
| `cmd/`, `util/`, `migrations/`, `tests/` | The Go API, built on [PocketBase](https://pocketbase.io) |
| `app/` | The Flutter client (Android, iOS, macOS, Linux) |
| `deploy/`, `Dockerfile`, `docker-compose.yml` | Running it on a server |

## Development

The Go toolchain lives wherever you keep it; the app needs Flutter.

```bash
cp .env.example .env                            # DOMAIN is required
go run ./cmd/revoked serve --http="0.0.0.0:3000"
```

Run it from the repository root: `.env`, `pb_data/` and the server root key are
all resolved against the working directory, so they only agree if it is the
same one every time.

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after any store change
flutter run
```

| Task | Command |
|---|---|
| Build / vet | `go build ./...` · `go vet ./...` |
| Test | `go test ./... -count=1 -p 1 -timeout 10m` |
| Format | `gofmt -w .` · `cd app && dart format .` |
| App checks | `cd app && flutter analyze && flutter test` |

The Go suite boots a real PocketBase on `127.0.0.1:5559` and drives it over
HTTP. It needs no external services, but it does bind a port — hence `-p 1`.

## Running it on a server

```bash
docker network create proxy-network   # once, or reuse your reverse proxy's own
cp .env.example .env                  # set DOMAIN to the hostname it answers on
docker compose up -d --build
docker compose logs api               # prints the DNS record to publish
```

Nothing is published to the host. A published port is reachable at the
machine's IP and skips whatever TLS your proxy terminates; the proxy reaches
the container by name over the shared network instead, so `API_PORT` only has
to be free *inside* the container. In Nginx Proxy Manager that is forward
hostname `revoked-api`, port `3000`, scheme `http`, with the proxy's own
container attached to `proxy-network`.

Point the proxy at the API directly rather than at another proxy in front of
it. Two proxies in a row each append to `X-Forwarded-For`, and PocketBase reads
the rightmost entry, so the API would see the outer proxy's address on every
request and the per-IP rate limits would share a single bucket across everyone.

No reverse proxy on this host? `docker compose --profile proxy up -d` adds a
bundled nginx on `:80`, the only thing that publishes a port. TLS is a
commented block in `deploy/nginx/default.conf.template`, with the ACME
challenge path already wired up.

### Portainer

Use a **git-backed** stack, not the web editor — `build: .` needs the
repository as its build context. Compose path `docker-compose.yml`, and put the
`.env` values in Portainer's *Environment variables* section.

## After the first boot

**Publish the DNS record** the logs print. Until `_revoked.<your-domain>`
resolves, peers refuse to trust identities this server issues — that record is
the root of the whole trust chain, and a client that cannot verify it says so
rather than trusting silently.

**Set the trusted proxy header.** In the dashboard at `/_/`, under *Settings →
Application*, set trusted proxy headers to `X-Forwarded-For` and leave "use
leftmost IP" off. Without it every request looks like it came from your proxy,
so the password-gate, probe and challenge rate limits share one bucket.

**Consider restricting `/_/`.** It is the superuser dashboard and it is
reachable by anyone who finds the hostname. An access list on your proxy is the
cheapest fix.

## Accounts

Self-service registration is off unless `ALLOW_SIGNUPS=true`. With it off the
app's sign-up screen reports that the server is invite-only, and accounts are
created by whoever runs it:

```bash
docker compose exec api /pb/revoked user upsert someone@example.com 'a-long-password'
```

The same command resets an existing account's password. The dashboard and the
`USER_EMAIL`/`USER_PASSWORD` seed pair also work; neither goes through the
refusal, which applies to HTTP registrations only.

## Backups

The `pb_data` volume holds `server_root.pem` — the CA key that signs every
identity certificate this server issues. Losing it means every identity it ever
issued stops verifying, and there is no way to regenerate it. Back it up, and
keep it to itself: it is the one file whose disclosure cannot be undone.

## Contributing

[Conventional Commits](https://www.conventionalcommits.org); the release
workflow derives the version bump from them.

| Prefix | Bump |
|---|---|
| `fix:` | patch |
| `feat:` | minor |
| `breaking:` | major |
| `chore:` / `docs:` | none |

Work on `dev` or `type/short-description` branches and open a PR into `dev`.
`main` is protected and triggers releases.

## Licence

[Elastic License 2.0](LICENSE). Self-host it, build on it, don't sell it as a
service.
