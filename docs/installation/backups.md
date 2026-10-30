# Back up your server

Everything that matters lives in one Docker volume: `pb_data`. Back it up.

| Inside it | Why it matters |
|---|---|
| `server_root.pem` | The root key that signs every identity your server issues. Its fingerprint is [in your DNS](dns.md). **You can't recreate it.** Lose it, and every identity you ever issued stops verifying — everywhere, for good. Leak it, and someone else can make identities that verify as yours. You can't undo a leak. |
| `oidc_subject.key` | The secret behind each person's identifier at a service, when services [sign people in with Revoked](../api/sign-in.md). Lose it, and every person becomes a stranger to every service they signed in to. Created the first time the sign-in provider is used. |
| `oidc_signing.pem` | The key that signs ID tokens, certified by the root key. Losing it costs nothing lasting: a new one is made and certified when needed, and services fetch it again. |
| `credential_signing.pem` | The key that signs [attestations](../guide/attestations.md) and their status list, certified by the root key. Lose it, and every credential issued so far stops verifying. A new key is made when needed, but it didn't sign them. Created the first time attestations are used. |
| `data.db` | The database: accounts, vault records, shares, requests, grants, attestations and their revocations, and the audit trail. |

## Make a backup

Stop the container and snapshot the volume, or copy out of it while it runs:

```bash
docker compose stop api
docker run --rm -v revoked_pb_data:/pb/pb_data -v "$PWD":/backup alpine \
  tar czf /backup/revoked-backup.tar.gz -C /pb pb_data
docker compose start api
```

(The volume's full name depends on your compose project name. `docker volume
ls` shows it.)

Keep the backup as safe as a password, not like ordinary data: it contains the
root key.

## Restore a backup

Recreate the volume from the archive before the first boot, then run `docker
compose up`. The server loads the existing `server_root.pem`, the fingerprint
matches the DNS record you published, and every identity verifies again.

Never start the stack with an **empty** volume by mistake. The server then
makes a *fresh* root key. It runs fine, but its fingerprint no longer matches
your DNS record, and everything it issued before is orphaned. If that happens
and you have the backup, restore it over the fresh volume. The old fingerprint
comes back with the file.

A restore puts the database back to the moment of the backup. Identities and
attestations you revoked after that moment count as valid again. Attestations
issued after it are gone. So after you revoke something, take a fresh backup
and keep that one.
