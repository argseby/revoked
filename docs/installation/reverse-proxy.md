# Put a reverse proxy in front

The API doesn't handle TLS itself. Put a reverse proxy in front of it. The
compose file makes that proxy the *only* way in.

## Connect your proxy to the container

The container opens no ports on the host. An open port would be reachable at
the machine's raw IP, past your proxy's TLS. Instead, your proxy reaches the
container **by name** over a shared Docker network:

```bash
docker network create proxy-network   # once — or reuse your proxy's own network
```

Attach your proxy's container to that network. Then forward to
`revoked-api:3000` (that is `CONTAINER_NAME:API_PORT`) over plain `http`.
Plain is fine here: the traffic never leaves the Docker network.

**Nginx Proxy Manager:** forward hostname `revoked-api`, forward port `3000`,
scheme `http`. Attach the NPM container itself to `proxy-network`, or the name
won't resolve.

## Use one proxy, not two

Point your proxy straight at the API, never at another proxy in front of it.
Each proxy in a row adds to `X-Forwarded-For`, and the server reads the
**rightmost** entry. Behind two proxies, every request seems to come from the
outer proxy. All per-IP [rate limits](env.md#rate-limits) then share one
budget.

## Let rate limits see real IPs

Do this once in the dashboard after first boot: open `/_/` → **Settings →
Application**, set trusted proxy headers to `X-Forwarded-For`, and leave "use
leftmost IP" off. Skip it, and your server sees the proxy's address on every
request. One noisy visitor then uses up everyone's budget.

## No proxy on this host?

```bash
docker compose --profile proxy up -d
```

This adds the bundled nginx on `:80` — the only setup that opens a host port.
For TLS, get a certificate and uncomment the TLS block in
`deploy/nginx/default.conf.template`. The ACME challenge path is already set
up for certbot's webroot mode.

## Lock the dashboard down

`/_/` is the superuser dashboard. Anyone who finds your hostname can reach it.
Add an access list on your proxy: allow your IPs for `/_/`, deny the rest.
On a public install, that's the cheapest real hardening you can do.
