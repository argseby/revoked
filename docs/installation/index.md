---
title: Server
---

# Set up a server

You run one Go binary with a built-in database. In production you put it in a
container, with a reverse proxy in front for TLS and one DNS record that people
check your server against.

**You need:**

- A domain or subdomain that points at your machine — say `api.example.com`.
  This becomes `DOMAIN`. Choose it carefully: every identity your server
  issues is signed for it, and other servers check those identities against
  DNS records under it.
- Docker with Compose.
- A reverse proxy that handles TLS. Use the one you already run (Nginx Proxy
  Manager, Caddy, Traefik…) or the bundled nginx profile.

**Install it:**

```bash
git clone https://github.com/argseby/revoked && cd revoked
docker network create proxy-network   # once — or reuse your proxy's network
cp .env.example .env                  # set DOMAIN; see the .env reference
docker compose up -d --build
docker compose logs api               # prints the DNS record to publish
```

The container opens no ports on the host. Your proxy reaches it by name over
the shared network. So nobody can reach the API by raw IP and skip your TLS.
More in [Put a reverse proxy in front](reverse-proxy.md).

**Then, in this order:**

1. [Publish the `_revoked` TXT record](dns.md) the logs printed. It is what
   makes your server's identities checkable.
2. [Point your reverse proxy at the container](reverse-proxy.md) and set the
   trusted-proxy header, so rate limits see real client IPs.
3. [Create accounts](accounts.md). People can't sign themselves up unless you
   allow it.
4. [Back up `pb_data`](backups.md). It holds the one file you can never
   recreate.

Every setting is in the [.env reference](env.md).

Once the server runs, give people [the app](app.md), or send them straight to
the desktop and Android downloads.
