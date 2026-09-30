# Accounts

People sign in with a **passkey** — a key their device keeps and unlocks with a
fingerprint, face or PIN. There are no passwords: nothing to reuse, leak or
phish. A passkey is bound to the address it was made at, so signing in happens
on this server's own page, `/passkey`, which the app opens in the browser and
which sends the person back signed in.

That page has to be reached at the server's real address over HTTPS (your
`DOMAIN`). On a development machine it is `http://localhost:<port>` — not
`127.0.0.1`, which no passkey can be bound to.

Self-service registration is **off by default**. A server nobody configured
should be one only its operator can add people to — with `ALLOW_SIGNUPS=false`
the sign-in page reports that the server is invite-only, and the registration
endpoint refuses.

## Creating users

The operator creates accounts from the machine:

```bash
docker compose exec api /pb/revoked user upsert someone@example.com
```

It creates the account if needed and prints a **one-time link**, good for 24
hours. Send it to the person: they open it on the device they will use, save a
passkey, and sign in from the app. It writes directly through the application
layer, so it is not subject to the signup refusal.

Two other paths:

- the `USER_EMAIL` [seed](env.md#seed-accounts): the account is created on
  boot, and as long as it has no passkey every start logs a fresh link;
- the superuser dashboard at `/_/` (users collection) — followed by
  `user upsert` for the link, since an account made there has no way in yet.

## Lost devices

Someone who lost every device holding a passkey cannot sign in, and nothing
they know can let them back in — that is the point. Run `user upsert` for
their address again and send them the new link. Their old passkeys keep
working until removed under **Settings → Account → Passkeys**.

The way to never need this: a passkey on more than one device. **Settings →
Account → Passkeys** adds one on the device at hand, or copies a fifteen-minute
link to open on another. Many password managers and platforms also sync a
passkey across a person's devices on their own.

## Upgrading from passwords

Accounts made before passkeys keep everything they own, but their password no
longer signs in. Run `user upsert` once per address and send out the links.

## The superuser

The `/_/` dashboard account is separate from app accounts and still signs in
with a password. Create it on first visit to `/_/`, via the printed install
link in the logs, or with the `ADMIN_EMAIL`/`ADMIN_PASSWORD` seed pair. It
manages collections and settings — it is not a login for the app itself.

## Opening registration

Set `ALLOW_SIGNUPS=true` and restart. Anyone who can reach the server can then
create an account with an email address and a passkey. Inviting members into an
*existing* workspace is a separate, in-app flow (workspace invites) and works
regardless of this flag.

## First login

On first login a user lands in onboarding: create a workspace (naming
themselves for their signing identity — that name is what recipients of their
shares and requests see) or join one by pasting an invite key.
