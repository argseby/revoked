# .env reference

Copy `.env.example` to `.env` and edit it. Compose passes every variable on
by name, so you can set the same values as Portainer stack variables instead —
no `.env` file needed there.

## Required

| Variable | Meaning |
|---|---|
| `DOMAIN` | The public hostname people reach your server at — the name on the TLS certificate. Never an IP or `localhost`. The server **won't start without it**. Every identity is signed for this domain, and other servers check it against the `_revoked.<DOMAIN>` TXT record. Get it wrong and every remote server rejects your identities. |

## Ports & topology (compose only)

| Variable | Default | Meaning |
|---|---|---|
| `API_PORT` | `3000` | The port the API listens on *inside* the container, and the one your reverse proxy forwards to. |
| `API_PUBLISH` | `127.0.0.1:3000` | Where the API is published on the host. The default answers on that machine only, at `http://localhost:3000`. A bare port such as `3000` opens it on every interface, reachable by the machine's IP: `/healthz` and the version answer, but nobody can sign in, because a passkey cannot be bound to an IP address. Never leave it open on a public host: it skips the proxy's TLS. |
| `CONTAINER_NAME` | `revoked-api` | The container's name. Your reverse proxy forwards to this hostname. |
| `PROXY_NETWORK` | `proxy-network` | The Docker network you share with your reverse proxy. Compose creates it when it doesn't exist; name the proxy's own network to join that one. |
| `HTTP_PORT` / `HTTPS_PORT` | `80` / `443` | Only for the bundled nginx (`--profile proxy`). |
| `REVOKED_IMAGE` | `ghcr.io/argseby/revoked:latest` | The server image to run, as a full image reference: a tag alone such as `latest` fails to pull. Pin a release, such as `ghcr.io/argseby/revoked:v0.36.0`: a new tag is pulled on the next `up`, while `:latest` only moves when the image is pulled again. `docker compose up -d --build` builds the checkout under this name instead. |

## Registration

| Variable | Default | Meaning |
|---|---|---|
| `ALLOW_SIGNUPS` | `false` | Lets anyone create their own account over HTTP. Off by default, so only you can add people to a fresh server. See [Add people](accounts.md) for how to add them while it's off. |
| `SIGNUP_VERIFY_EMAIL` | `false` | Makes a new account confirm its address with a 6-digit code mailed to it. Without it, anyone can sign up with any address. Needs the [mail server](#mail) below — the server won't start with this on and no `SMTP_HOST`/`SMTP_SENDER_ADDRESS`. Accounts you create yourself aren't affected. |
| `APP_STORE_URL` | — | Your app's App Store page (https). The `/app` page, where a computer's QR code leads, offers it to iPhones. Unset, the page only offers to open the app. |
| `PLAY_STORE_URL` | — | The same for Google Play, offered to Android phones. |

## Attestations

| Variable | Default | Meaning |
|---|---|---|
| `ALLOW_ATTESTATIONS` | `false` | Lets this server issue [attestations](../guide/attestations.md): statements about other people's identities, signed in the name of `DOMAIN`. Off by default. Turn it on only if you're happy for this server to vouch for people in your domain's name. Even then, a workspace member needs the *Issue attestations* permission. Holding and checking credentials works either way. |

## Blocked domains

| Variable | Default | Meaning |
|---|---|---|
| `BLOCKED_DOMAINS_FILE` | — | Path to a file listing domains that impersonate your server, in the format of the repository's [`blocked-domains.txt`](https://github.com/argseby/revoked/blob/main/blocked-domains.txt). Served at `GET /api/blocked-domains`. The app won't switch to a server named in your file or in the project's own list. Your file can add entries, not remove the project's, and `revoked.link` can never be blocked. The file is read on every request, so edits apply without a restart. In Docker, mount the file into the container and give its path there. |

## Mail

The mail server that sends signup confirmation codes and, if you turn it on,
the link when someone shares something with a person who has no account
here. These values replace
whatever the `/_/` dashboard has stored, on every start. Leave `SMTP_HOST`
unset to keep the dashboard's settings.

| Variable | Default | Meaning |
|---|---|---|
| `SMTP_HOST` | — | The mail server's host name. |
| `SMTP_PORT` | `587` (`465` with `SMTP_TLS`) | Its port. |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | — | Credentials, if the mail server needs them. |
| `SMTP_TLS` | `false` | `true` for implicit TLS (usually port 465). Off means STARTTLS when the mail server offers it (usually 587). |
| `SMTP_AUTH_METHOD` | `PLAIN` | `PLAIN` or `LOGIN`. |
| `SMTP_SENDER_ADDRESS` | — | The From address, e.g. `no-reply@example.com`. |
| `SMTP_SENDER_NAME` | `Revoked` | The From name. |

### Emailing a share or a request

Off unless you turn it on. This is the one thing a person using your server
can do that makes it contact somebody who has no account on it, so you decide
which addresses it may reach at all.

| Variable | Default | Meaning |
|---|---|---|
| `GRANT_EMAIL_RECIPIENTS` | `off` | Who may be emailed a link. `off` emails nobody and the sender gets the link to pass on themselves. `same-domain` emails addresses in your own `DOMAIN`. `trusted` emails addresses whose domain publishes a Revoked server you can verify — which proves the domain, never that the mailbox exists or who reads it. `all` emails anyone. An unrecognised value reads as `off`. The server won't start with this set to anything but `off` and no `SMTP_HOST`/`SMTP_SENDER_ADDRESS`. |

A request emailed this way needs the recipient to make an account before they
can answer, so it is only sent while `ALLOW_SIGNUPS` is on. The email never
carries what was shared — only what it is called and a link.

## Seed accounts

Created on first boot. Handy on a test box. On anything reachable, leave
these blank and create the superuser yourself.

| Variable | Meaning |
|---|---|
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | A superuser for the `/_/` dashboard. |
| `USER_EMAIL` | A regular account. It has no password: until it has a passkey, every start logs a one-time link to add one. See [Add people](accounts.md). |

## Outbound requests

| Variable | Default | Meaning |
|---|---|---|
| `ALLOW_PRIVATE_CALLBACKS` | `false` | Lets user-supplied [callback](../api/callbacks.md) and [webhook](../api/webhooks.md) URLs point at loopback and private ranges. On a public host that lets users make your server call into private networks (server-side request forgery). Turn it on only for a LAN-only or development install. Link-local (cloud metadata), multicast and `0.0.0.0` stay blocked regardless. |
| `PEER_OVERRIDES` | empty | Other Revoked servers to reach at a fixed address instead of `https://<domain>`, as `a.example=http://127.0.0.1:8091,b.example=http://127.0.0.1:8092`. Your server takes a listed server's root key from that address without checking DNS, so you're vouching for every entry. Use it for two development instances or a closed network. Keep it empty on a public host. Loopback and private addresses also need `ALLOW_PRIVATE_CALLBACKS`. |

## Grants between servers

| Variable | Default | Meaning |
|---|---|---|
| `GRANT_MAX_AGE` | `60` | How many seconds another server may keep a value it read from one of your grants before asking again. `0` asks it to keep nothing. If the other server misses a revocation event, the revocation still reaches it within this window. |

## Files

Limits for file records, in megabytes. Unset or `-1` means unlimited. `0`
turns file uploads off. The server reads these from the environment on each
request: a change needs a restart, never a migration.

| Variable | Default | Meaning |
|---|---|---|
| `FILE_MAX_SIZE` | `-1` | The largest single upload you accept. |
| `FILE_MAX_STORAGE` | `-1` | Total file storage per workspace. |

Clients see the per-file limit at `GET /api/server` as `limits.maxFileSize`.
So the app can turn down a file that's too big before uploading it.

## Rate limits

Limits on the public endpoints. The server reads them once at startup, so a
change needs a restart. `0` turns a limiter off.

| Variable | Default | Budget |
|---|---|---|
| `RATELIMIT_GATE_ATTEMPTS` | `10` | Password/identifier attempts on a share gate, per IP + slug, per 5 minutes. |
| `RATELIMIT_PROBE_REQUESTS` | `120` | Metadata probes, short-link and CardDAV reads and link unlocks, per IP, per minute. This is the budget for guessing slugs, shared across every slug. `/api/server`, `/api/certificate/{id}` and the OpenID Connect sign-in page each get their own budget of this size. |
| `RATELIMIT_CHALLENGE_REQUESTS` | `60` | Handshake nonces issued, per IP, per minute. |
| `RATELIMIT_PASSKEY_REQUESTS` | `60` | Passkey sign-in and registration steps, per IP, per minute. One sign-in takes three. |
| `RATELIMIT_SIGNUP_EMAILS` | `10` | Signup confirmation codes mailed, per IP, per hour. Each address also gets at most one code a minute and five an hour, whoever asks. |
| `RATELIMIT_GRANT_REQUESTS` | `300` | Calls between servers — grant reads, grant events and accepted answers — and calls to the OpenID Connect token and userinfo endpoints, per IP, per minute. Also answers to requests on other servers, per account. One read carries up to 100 grants. |
| `RATELIMIT_SUBMISSIONS` | `60` | Answers to requests, per account, per hour. Each answer notifies the request's owner and may call their callback URL. |
| `RATELIMIT_WEBHOOK_SENDS` | `30` | Webhook tests and resends, per caller, per minute. Each one is a request to an address the caller chose. |
| `RATELIMIT_GRANT_EMAILS` | `5` | Links emailed to one address, per hour, whoever sends them. This is the only cap protecting someone who isn't using your server, so it is counted in the database rather than in memory: it holds even if you run more than one instance. |
| `RATELIMIT_WORKSPACE_EMAILS` | `30` | Links emailed by one workspace, per hour. Guards your own sending quota and reputation, which the per-account cap does not once a workspace invites members. In memory, so more than one instance multiplies it. |

PocketBase's own sign-in endpoints are limited too, by its built-in rate
limiter, which a migration turns on: five superuser sign-ins per IP per five
minutes, two per three seconds for other accounts, and two password-reset or
one-time-code mails per ten minutes. Change them in the dashboard under
*Settings → Application → Rate limiting*.

All these limits count per IP. So set the
[trusted-proxy header](reverse-proxy.md#let-rate-limits-see-real-ips).
Without it, every request seems to come from your proxy, and everyone shares
one budget.

## Capacity

| Variable | Default | Meaning |
|---|---|---|
| `MAX_CONNECTIONS` | `2048` | How many callers your server talks to at once. Past this a new caller waits for a free slot, and gives up if none comes. Every request in flight holds some memory, so without a ceiling enough callers at once will exhaust it and the machine will stop the server outright; this keeps it answering the callers it already took. `0` removes the ceiling. |

If you put your server behind a reverse proxy, cap connections there too — the
proxy meets the flood first.

## Storage

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_KEY_PATH` | `pb_data/server_root.pem` | Where your server's root key lives. Compose keeps it inside the `pb_data` volume — leave it there. Everything under `pb_data` is state you [can't recreate](backups.md). |
| `TEMPLATES_DIR` | `templates/` next to `pb_data` | A folder for your own [built-in templates](operations.md#the-template-catalogue), synced on every restart. |
