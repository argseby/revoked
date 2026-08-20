# Setting up a server

Revoked is one Go binary around an embedded database. A production setup is
the binary in a container, a reverse proxy terminating TLS in front of it, and
one DNS record that anchors the trust chain.

**You need:**

- A domain (or subdomain) pointing at your machine — say `api.example.com`.
  This becomes `DOMAIN`, and it is load-bearing: identities are signed for it
  and peers verify them against DNS published under it.
- Docker with Compose.
- A reverse proxy that terminates TLS — your existing one (Nginx Proxy
  Manager, Caddy, Traefik…) or the bundled nginx profile.

**The whole install:**

```bash
git clone https://github.com/argseby/revoked && cd revoked
docker network create proxy-network   # once — or reuse your proxy's network
cp .env.example .env                  # set DOMAIN; see the .env reference
docker compose up -d --build
docker compose logs api               # prints the DNS record to publish
```

Nothing is published to the host: the proxy reaches the container by name
over the shared network, so the API cannot be hit by raw IP and nobody can
skip your TLS. Details in [Reverse proxy](reverse-proxy.md).

**Then, in order:**

1. [Publish the `_revoked` TXT record](dns.md) the logs printed — the root of
   the trust chain.
2. [Point your reverse proxy at the container](reverse-proxy.md) and set the
   trusted-proxy header so rate limits see real client IPs.
3. [Create accounts](accounts.md) — self-registration is off by default.
4. [Back up `pb_data`](backups.md) — it holds the one file that can never be
   regenerated.

Every knob along the way is in the [.env reference](env.md).
