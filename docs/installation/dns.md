# Publish your DNS record

Publish one TXT record, and anyone can check that what your server issues
really comes from you. This is the most important step after installing.

## Find your record

Your server creates its **root key** on first boot (or loads it) and prints
the record you need. Read it from the logs:

```bash
docker compose logs api
```

Look for a line naming `_revoked.<your-domain>`, with a value like

```
v=revoked1; k=sha256/1421ab…64 hex characters…
```

The hex string is the SHA-256 fingerprint of your server's root public key.
Only you can publish records in your DNS zone, so the record proves the key
is yours. Any client on any server can then follow the chain: DNS names the
key, the key signed the identity, the identity signed the request. A phisher
can put your domain in a request. They can't put a record in your DNS.

## Publish it

Put `_revoked.` in front of your **exact** `DOMAIN`. With
`DOMAIN=api.example.com`, the record is `_revoked.api.example.com`.

Most registrars add the zone for you. So in the host field, type the name
*without* the zone:

| DOMAIN | Record name | Host field at the registrar |
|---|---|---|
| `example.com` | `_revoked.example.com` | `_revoked` |
| `api.example.com` | `_revoked.api.example.com` | `_revoked.api` |

In Namecheap: **Advanced DNS → Add new record → TXT Record**. Host as above,
value the full `v=revoked1; k=sha256/…` string, TTL automatic.

## Check that it worked

DNS changes take a few minutes. Your registrar's dashboard may show the record
before the world can see it. Check from outside:

```bash
dig TXT _revoked.api.example.com +short
```

You should see the `v=revoked1; k=sha256/…` value in quotes. You can also
check from the app: **Settings → Developer → Domain verification** runs the
whole chain against public DNS-over-HTTPS resolvers. If a step fails, it tells
you which one.

## Before the record is live

Your server works without the record. But every identity it issues shows as
**unverified, in red**, on any client that checks. That is on purpose: a
client that can't check says so instead of trusting blindly. Once you publish
the record, the same identities verify. You don't need to do anything else.

## Keep the key that matches

The fingerprint comes from `server_root.pem` in the `pb_data` volume. A fresh
volume means a fresh key. Your published record then no longer matches, and
every identity issued before stops verifying. That is why
[backups](backups.md) matter more than anything else on the machine. Restore
the volume and the old fingerprint comes back — and with it, your old record
is valid again.
