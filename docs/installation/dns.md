# DNS setup

One TXT record turns your server from "some host on the internet" into a
verifiable sender. Publishing it is the single most important post-install
step.

## What the record is

At boot, the server generates (or loads) its **root key** and prints the
record to publish:

```bash
docker compose logs api
```

You are looking for a line naming `_revoked.<your-domain>` with a value like

```
v=revoked1; k=sha256/1421ab…64 hex characters…
```

That hex string is the SHA-256 fingerprint of your server's root public key.
Publishing it under a name only *you* control is what lets any client on any
server verify the chain: DNS names the key → the key signed the identity →
the identity signed the request. A phisher can claim your domain in a request;
they cannot publish records in your DNS zone.

## Publishing it

The record goes at `_revoked.` prepended to your **exact** `DOMAIN`. If
`DOMAIN=api.example.com`, the record is `_revoked.api.example.com`.

Most registrars auto-append the zone, so in the host field you type the part
*without* the zone:

| DOMAIN | Record name | Host field at the registrar |
|---|---|---|
| `example.com` | `_revoked.example.com` | `_revoked` |
| `api.example.com` | `_revoked.api.example.com` | `_revoked.api` |

In Namecheap: **Advanced DNS → Add new record → TXT Record**, host as above,
value the full `v=revoked1; k=sha256/…` string, TTL automatic.

## Verifying it took

DNS changes are not instant — a few minutes is normal, and your registrar's
own dashboard can lag behind what it has actually published. Check from the
outside:

```bash
dig TXT _revoked.api.example.com +short
```

You should see the `v=revoked1; k=sha256/…` value quoted back. The app checks
the same thing end-to-end: **Settings → Developer → Domain verification** runs
the full chain against public DNS-over-HTTPS resolvers and tells you exactly
which step failed if one did.

## Until it resolves

The server works without the record — but every identity it issues shows as
**unverified, in red**, on any client that checks. That is deliberate: a
client that cannot verify says so rather than trusting silently. Publish the
record and the same identities verify with no further action.

## If the key ever changes

The fingerprint is derived from `server_root.pem` in the `pb_data` volume. A
fresh volume means a fresh key, which means the published record no longer
matches and every previously issued identity stops verifying — this is why
[backups](backups.md) matter more than anything else on the machine. Restoring
the volume restores the fingerprint; only then does the old record become
valid again.
