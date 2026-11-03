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
cp .env.example .env                  # set DOMAIN; see the .env reference
docker compose up -d
docker compose logs api               # prints the DNS record to publish
```

Compose pulls the release image, so nothing is built. To build this checkout
instead, run `docker compose up -d --build`.

**Test it before the proxy:**

The API answers on the machine itself, at `http://localhost:3000`, and on no
other address:

```bash
curl http://localhost:3000/healthz
```

The app can use `http://localhost:3000` as its server on that machine, sign-in
included. From another computer, an SSH tunnel brings the same address there:

```bash
ssh -L 3000:127.0.0.1:3000 you@your-server
```

To reach it by the machine's IP instead, set `API_PUBLISH=3000`. That answers
`/healthz` and shows the version, but nobody can sign in: a passkey cannot be
bound to an IP address. Set it back before the server goes public, because a
port open by IP skips the proxy's TLS.

Your proxy reaches the container by name over a shared network. More in
[Put a reverse proxy in front](reverse-proxy.md).

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

## Upgrade {#upgrade}

Every release publishes a new image. The app's settings show **Server update
available** once the server runs an older release than the newest one.

With `REVOKED_IMAGE` left at `:latest`:

```bash
docker compose pull && docker compose up -d
```

With a pinned release, change the tag in `REVOKED_IMAGE` and run
`docker compose up -d`; the new tag is pulled on the way. `pb_data` carries
over, and migrations run when the server starts. [Back it up](backups.md)
first.

## Portainer

Use a **git-backed** stack with the compose path `docker-compose.yml`, and put
the `.env` values in Portainer's *Environment variables* section.

The stack runs the published image, `ghcr.io/argseby/revoked`, which carries
its release; Portainer builds nothing. To pin a release, set `REVOKED_IMAGE`
to the full image reference, such as `ghcr.io/argseby/revoked:v0.36.0`, and
change the tag to upgrade. A tag alone (`latest`, `:v0.36.0`) is not an image
name, and the pull fails with *pull access denied*. Left unset, the stack
runs `:latest`, and an upgrade needs *Re-pull image* enabled on redeploy.
