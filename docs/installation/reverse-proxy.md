# Reverse proxy

The API terminates no TLS itself. A reverse proxy in front of it does — and
the compose file is arranged so that the proxy is the *only* way in.

## The topology

Nothing is published to the host. A published port would be reachable at the
machine's raw IP, skipping the TLS your proxy terminates; instead the proxy
reaches the container **by name** over a shared Docker network:

```bash
docker network create proxy-network   # once — or reuse your proxy's own network
```

Attach your proxy's container to that network, then forward to
`revoked-api:3000` (that is `CONTAINER_NAME:API_PORT`) over plain `http` —
plain is correct here, the hop never leaves the Docker network.

**Nginx Proxy Manager:** forward hostname `revoked-api`, forward port `3000`,
scheme `http`. The NPM container itself must be attached to `proxy-network`,
or the name will not resolve.

## One proxy, not two

Point the proxy at the API directly, never at another proxy in front of it.
Each proxy in a row appends to `X-Forwarded-For`, and the server reads the
**rightmost** entry — so behind two proxies every request appears to come from
the outer proxy, and all per-IP [rate limits](env.md#rate-limits) collapse
into a single shared bucket.

## Let rate limits see real IPs

One dashboard step after first boot: open `/_/` → **Settings → Application**,
set trusted proxy headers to `X-Forwarded-For`, leave "use leftmost IP" off.
Without it the server sees your proxy's address on every request, and one
noisy visitor exhausts everyone's budget.

## No proxy on this host?

```bash
docker compose --profile proxy up -d
```

adds the bundled nginx on `:80` — the only configuration that publishes a host
port. TLS is a commented block in `deploy/nginx/default.conf.template` with
the ACME challenge path already wired for certbot's webroot mode.

## Lock the dashboard down

`/_/` is the superuser dashboard, and it is reachable by anyone who finds
your hostname. An access list on the proxy (allow your IPs, deny the rest for
`/_/`) is the cheapest meaningful hardening on a public install.
