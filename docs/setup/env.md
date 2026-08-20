# .env reference

Copy `.env.example` to `.env` and edit. Compose maps every variable
explicitly, so the same values work as Portainer stack variables — no `.env`
file needed there.

## Required

| Variable | Meaning |
|---|---|
| `DOMAIN` | The public hostname clients reach this server at — the name on the TLS certificate, never an IP or `localhost`. The server **refuses to boot without it**, because it anchors the trust chain: identities are signed for this domain, and peers verify them against the `_revoked.<DOMAIN>` TXT record. A value that does not match reality produces identities every remote verifier rejects. |

## Ports & topology (compose only)

| Variable | Default | Meaning |
|---|---|---|
| `API_PORT` | `3000` | Port the API listens on *inside* the container. Only has to be free in there — nothing is published to the host. |
| `CONTAINER_NAME` | `revoked-api` | The container's name, which is also the hostname your reverse proxy forwards to. |
| `PROXY_NETWORK` | `proxy-network` | External Docker network shared with your reverse proxy. Create it once: `docker network create proxy-network`. |
| `HTTP_PORT` / `HTTPS_PORT` | `80` / `443` | Only used by the bundled nginx (`--profile proxy`) — the one thing that publishes host ports. |

## Registration

| Variable | Default | Meaning |
|---|---|---|
| `ALLOW_SIGNUPS` | `false` | Whether anyone may create their own account over HTTP. Off by default: a fresh server should be one only its operator can add people to. See [Accounts](accounts.md) for how to create users while it is off. |

## Seed accounts

Created on first boot when both halves of a pair are set. Convenient on a
test box; on anything reachable, create the superuser interactively and leave
these blank.

| Variable | Meaning |
|---|---|
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Seed superuser for the `/_/` dashboard. |
| `USER_EMAIL` / `USER_PASSWORD` | Seed regular account. |

## Outbound requests

| Variable | Default | Meaning |
|---|---|---|
| `ALLOW_PRIVATE_CALLBACKS` | `false` | Lets user-supplied [callback URLs](../api/callbacks.md) resolve to loopback and private ranges. On a public host that is a server-side request forgery primitive — enable it only on a LAN-only or development install. Link-local (cloud metadata), multicast and `0.0.0.0` stay blocked regardless. |

## Rate limits

Public-surface budgets, read once at startup — a change needs a restart.
`0` disables a limiter entirely.

| Variable | Default | Budget |
|---|---|---|
| `RATELIMIT_GATE_ATTEMPTS` | `10` | Password/identifier attempts on a share gate, per IP + slug, per 5 minutes. |
| `RATELIMIT_PROBE_REQUESTS` | `120` | Metadata probes and short-link reads, per IP, per minute — the enumeration budget across every slug. |
| `RATELIMIT_CHALLENGE_REQUESTS` | `60` | Handshake nonce issuance, per IP, per minute. |

These budgets are per-IP, which is why the
[trusted-proxy header](reverse-proxy.md#let-rate-limits-see-real-ips) matters:
without it every request appears to come from your proxy and everyone shares
one bucket.

## Storage

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_KEY_PATH` | `pb_data/server_root.pem` | Where the server's root key lives. Compose pins it inside the `pb_data` volume — leave it alone. Everything under `pb_data` is state that [cannot be regenerated](backups.md). |
