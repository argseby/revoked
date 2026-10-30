
> [!WARNING]
> While this project is in active development, it's more a **proof-of-concept**. Feel free to use it for your use-cases, but don't expect production-ready support.
<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="app/assets/icon/revoced-mark-redacted-white-on-black.svg">
    <img src="app/assets/icon/revoced-mark-redacted-black-on-white.svg" alt="Revoked logo" width="96">
  </picture>
  <h1>revoked</h1>

[![License: ELv2](https://img.shields.io/badge/License-Elastic_v2-blue.svg)](https://www.elastic.co/licensing/elastic-license)
[![Status: Experimental](https://img.shields.io/badge/status-experimental-yellow)](#)
[![Windows](https://img.shields.io/badge/Windows-0078D6?logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0wIDBoMTEuNHYxMS40SDB6TTEyLjYgMEgyNHYxMS40SDEyLjZ6TTAgMTIuNmgxMS40VjI0SDB6TTEyLjYgMTIuNkgyNFYyNEgxMi42eiIvPjwvc3ZnPg==)](#)
[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](#)
[![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)](#)



</div>

Stop sending copies of your data. With Revoked you send a link instead: it always shows the current value, and it stops working the moment you revoke it. You run it yourself, under your own domain. People hold a link, never your data, so what they see is always up to date and stays under your control. Shares and requests work the same way. Each one is signed by an identity tied to your domain's DNS, so both sides can check who is really asking before anyone answers.

| Area           | Feature                   | What it does                                                                                                                              |
|----------------|---------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| **Vault**      | Records                   | Key/value entries with a type and a format; hidden values stay masked until you reveal them                                               |
|                | Sections                  | Named groups of records you can share as one                                                                                              |
|                | Aliases                   | Point a record at another and it shows that one's current value — answer a request with data you already hold                             |
|                | Templates                 | Create a whole set of sections and records in one go                                                                                      |
| **Shares**     | Living grants             | A `/s/{slug}` link that resolves the *current* value on every read — never a copy                                                         |
|                | Instant revocation        | `active` / `paused` / `revoked` / `expired` — change it yourself, any time, without asking anyone                                         |
|                | View caps                 | Enforced by a single guarded `UPDATE`, so concurrent readers can't all pass the same check                                                |
|                | Gates                     | Ask for a password, an expiry date, a known identity, or a cryptographic handshake before anything is shown                               |
|                | Consumable formats        | JSON, CSV, vCard, iCal and CardDAV, with ETag/304 — recipients use the address book or spreadsheet they already have                      |
| **Requests**   | Public collection         | A `/r/{slug}` page that asks others for data, laid out by a template                                                                      |
|                | Vault prefill             | Signed-in responders answer from their own vault instead of retyping                                                                      |
|                | Symmetric grants          | An answer becomes the same revocable link — the responder can withdraw it later                                                           |
|                | Trust gate                | Checks the requester's domain before anyone answers; a spoof is blocked, anything unverified needs an explicit confirmation               |
|                | Callbacks                 | A webhook on each answer, sent through an SSRF-guarded client that refuses redirects and re-checks the resolved IP                        |
| **Identity**   | On-device keys            | ECDSA P-256 generated locally; the private key never leaves the device                                                                    |
|                | DNS trust anchor          | `_revoked.<domain>` TXT pins the server's root key; identities are signed by it and verified over DNS-over-HTTPS with a fallback resolver |
|                | Verdicts                  | Verified / DNS missing / unverified / spoofed — with the *reason* shown, never a bare badge                                               |
|                | Handshake                 | Challenge–nonce–signature: prove you hold the key before gated data is shown                                                              |
| **Access**     | Workspaces                | Members, invites with per-permission grants, single-use and email-pinned options, escalation and last-admin guards                        |
|                | One permission vocabulary | The same catalogue governs people and API keys, served from `GET /api/permissions` so the client can't drift                              |
|                | API keys                  | Scoped, expiring, shown once and stored only as a hash                                                                                    |
| **Operations** | Self-hosted               | Docker stack under your own domain; registration off by default                                                                           |
|                | Rate limits               | Sliding windows on password gates, probes and challenges                                                                                  |
|                | Audit log                 | See what was accessed and changed, on the server                                                                                          |

## What's in here

| Path | |
|---|---|
| `cmd/`, `util/`, `migrations/`, `tests/` | The Go API, built on [PocketBase](https://pocketbase.io) |
| `app/` | The Flutter client (Android, iOS, macOS, Linux, Windows) |
| `deploy/`, `Dockerfile`, `docker-compose.yml` | Running it on a server |
| `app/packaging/` | Desktop scheme registration and install helpers |

## Development

You need Go for the server and Flutter for the app.

```bash
cp .env.example .env                            # DOMAIN is required
go run ./cmd/revoked serve --http="0.0.0.0:3000"
```

Always run it from the repository root. The server looks for `.env`,
`pb_data/` and its root key in the current directory, so a different
directory means a different server.

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

The Go tests start a real PocketBase on `127.0.0.1:5559` and talk to it over
HTTP. They need no outside services, but they do use that port — so run them
with `-p 1`.

## Running it on a server

```bash
docker network create proxy-network   # once, or reuse your reverse proxy's own
cp .env.example .env                  # set DOMAIN to the hostname it answers on
docker compose up -d --build
docker compose logs api               # prints the DNS record to publish
```

The container opens no ports on the host. An open port would be reachable at
the machine's IP, past your proxy's TLS. Your proxy reaches the container by
name over the shared network instead, so `API_PORT` only has to be free
*inside* the container. In Nginx Proxy Manager: forward hostname
`revoked-api`, port `3000`, scheme `http`, and attach the proxy's own
container to `proxy-network`.

Point your proxy straight at the API, never at another proxy in front of it.
Each proxy in a row adds to `X-Forwarded-For`, and PocketBase reads the
rightmost entry. Behind two proxies, the API sees the outer proxy's address on
every request, and everyone shares one per-IP rate limit.

No reverse proxy on this host? `docker compose --profile proxy up -d` adds a
bundled nginx on `:80` — the only thing that opens a port. For TLS, get a
certificate and uncomment the TLS block in
`deploy/nginx/default.conf.template`. The ACME challenge path is already set
up.

### Portainer

Use a **git-backed** stack, not the web editor: `build: .` needs the
repository to build from. Set the compose path to `docker-compose.yml`, and
put the `.env` values in Portainer's *Environment variables* section.

Pin the stack's repository reference to a release tag (`refs/tags/v0.22.0`)
and set `REVOKED_VERSION` to the same tag. Portainer's checkout has no `.git`,
so without it the server can't tell its release and reports `dev`.

## Downloads

Each release builds Linux, Windows and Android apps and attaches them
(`.github/workflows/desktop.yml`). Flutter can't cross-compile for the
desktop, so each one builds on its own runner.

Android won't install an unsigned APK, so every build gets signed. Put your
keystore in the repository secrets (`ANDROID_KEYSTORE_BASE64`,
`ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`) and CI
signs with it. Without them, CI uses a fresh debug key on every run. That APK
installs, but it can't update an earlier install. The forced reinstall wipes
the identities' private keys, which never left the device and can't be
recreated. That's why the file is named `-testing-only`. None of this involves
the Play Store.

Create the keystore once and keep the file safe. If you lose it, no future
build can update an installed app:

```bash
keytool -genkey -v -keystore revoked-release.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias revoked
base64 -w0 revoked-release.jks   # paste into ANDROID_KEYSTORE_BASE64
```

On Linux and Windows, you have one manual step after extracting: register the
`revoked://` link scheme. Until you do, every `revoked://` link does nothing
at all:

```sh
./packaging/install.sh                      # Linux: installs to ~/.local and registers the scheme
```

On Windows, run an installer, or edit the paths in
`packaging/register-scheme.reg` to match where you extracted it and apply it.
See `app/packaging/README.md`.

Linux needs `libsecret` (GNOME Keyring or KWallet). Without it the app runs,
but it can't store an identity's private key. Windows builds are unsigned
unless a certificate is set up, so SmartScreen warns on first run.

## After the first boot

**Publish the DNS record** the logs print. Until `_revoked.<your-domain>`
resolves, other servers won't trust the identities your server issues. Every
check starts from that record. A client that can't check it says so instead
of trusting blindly.

**Set the trusted proxy header.** In the dashboard at `/_/`, under *Settings →
Application*, set trusted proxy headers to `X-Forwarded-For` and leave "use
leftmost IP" off. Without it, every request seems to come from your proxy, so
everyone shares one password-gate, probe and challenge rate limit.

**Lock down `/_/`.** It's the superuser dashboard, and anyone who finds your
hostname can reach it. An access list on your proxy is the cheapest fix.

## Accounts

People sign in with a passkey. There are no passwords. People can't sign
themselves up unless you set `ALLOW_SIGNUPS=true`. Until then, the sign-in
page says the server is invite-only, and you create accounts yourself:

```bash
docker compose exec api /pb/revoked user upsert someone@example.com
```

It prints a one-time link, good for 24 hours. Send it to the person; they
open it and save a passkey on their device. If someone loses every device with
their passkey, run the same command to let them back in. The `USER_EMAIL` seed
works too, and logs the link on start.

## Backups

Back up the `pb_data` volume, and keep the backup private. It holds
`server_root.pem`, the CA key that signs every identity certificate your
server issues. Lose it, and every identity you ever issued stops verifying —
you can't recreate it. Leak it, and you can't undo that.

## Contributing

Write [Conventional Commits](https://www.conventionalcommits.org) as
`type(scope): message`. The **type** sets the version. The scope is a free
label (`app`, `api`, `docs`, `site`, …) and never does.

| Type | Version bump | Lands in the changelog as |
|---|---|---|
| `breaking:` (or `breaking!:`) | major (minor while still 0.x) | ⚠️ Breaking Changes |
| `feat:` | minor | ✨ Features |
| `fix:` | patch | 🐛 Bug Fixes |
| `docs:` `chore:` `ci:` `refactor:` `test:` `style:` `perf:` | **none — no release** | not listed |

If none of the commits pushed to `main` is a `fix`/`feat`/`breaking`, there's
no tag and no release.

**What runs when:**

- **Every PR and push** (`main`/`dev`): CI — Go build + tests, Flutter
  analyze + tests.
- **Merge to `main` with a `fix`/`feat`/`breaking` commit**: the release
  workflow tags, writes the changelog, creates the GitHub release, then
  builds the Linux, Windows and Android apps and attaches them to it.
- **Merge to `main` touching only `docs/`**: the docs site redeploys to
  Pages; no version, no release, no desktop builds.

Work on `dev` or a `type/short-description` branch and open a PR into `dev`.
`main` is protected and triggers releases.

## Licence

[Elastic License 2.0](LICENSE). Self-host it, build on it, don't sell it as a
service.
