# Backups

Everything that matters lives in one Docker volume: `pb_data`.

| Inside it | Why it matters |
|---|---|
| `server_root.pem` | The root key that signs every identity this server issues, whose fingerprint is [pinned in your DNS](dns.md). **It cannot be regenerated.** Lose it and every identity ever issued stops verifying, everywhere, permanently. Leak it and someone else can mint identities that verify as yours — disclosure cannot be undone. |
| `oidc_subject.key` | The secret each person's identifier at a service is derived from, when services [sign people in with Revoked](../api/sign-in.md). Lose it and every person becomes a stranger to every service they signed in to. Created the first time the provider is used. |
| `oidc_signing.pem` | The key ID tokens are signed with, certified by the root key. Losing it costs nothing lasting: a new one is made and certified when next needed, and services fetch it again. |
| `credential_signing.pem` | The key [attestations](../guide/attestations.md) and their status list are signed with, certified by the root key. Lose it and every credential issued so far stops verifying: a new key is made when next needed, but it did not sign them. Created the first time attestations are used. |
| `data.db` | The database: accounts, vault records, shares, requests, grants, attestations and their revocations, audit trail. |

## Backing up

Snapshot the volume while the container is stopped, or copy out of it live:

```bash
docker compose stop api
docker run --rm -v revoked_pb_data:/pb/pb_data -v "$PWD":/backup alpine \
  tar czf /backup/revoked-backup.tar.gz -C /pb pb_data
docker compose start api
```

(The volume's full name depends on your compose project name — `docker volume
ls` shows it.)

Store the backup like a credential, not like data: it contains the root key.

## Restoring

Recreate the volume from the archive before first boot, then `docker compose
up`. The server loads the existing `server_root.pem`, the fingerprint matches
the DNS record you already published, and every identity verifies again.

The failure mode to avoid: bringing the stack up with an **empty** volume
generates a *fresh* root key. The server runs fine — but its fingerprint no
longer matches your DNS record, and everything it issued before is orphaned.
If that happens and you have the backup, restore it over the fresh volume; the
old fingerprint returns with the file.

A restore returns the database to the moment of the backup. Identities and
attestations revoked after that moment read as standing again, and
attestations issued after it are no longer known. A backup taken after a
revocation is the one to keep.
