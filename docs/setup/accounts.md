# Accounts

Self-service registration is **off by default**. A server nobody configured
should be one only its operator can add people to — with `ALLOW_SIGNUPS=false`
the app's sign-up screen reports that the server is invite-only, and the HTTP
registration endpoint refuses.

## Creating users

The operator creates accounts from the machine:

```bash
docker compose exec api /pb/revoked user upsert someone@example.com 'a-long-password'
```

The same command **resets the password** of an existing account — handy for
lockouts. It writes directly through the application layer, so it is not
subject to the signup refusal (which applies to HTTP registrations only).

Two other paths that also bypass the refusal:

- the superuser dashboard at `/_/` (users collection), and
- the `USER_EMAIL`/`USER_PASSWORD` [seed pair](env.md#seed-accounts) on first
  boot.

## The superuser

The `/_/` dashboard account is separate from app accounts. Create it on first
visit to `/_/`, via the printed install link in the logs, or with the
`ADMIN_EMAIL`/`ADMIN_PASSWORD` seed pair. It manages collections and settings —
it is not a login for the app itself.

## Opening registration

Set `ALLOW_SIGNUPS=true` and restart. Anyone who can reach the server can then
create an account; each new account is provisioned with its own workspace at
signup. Inviting members into an *existing* workspace is a separate,
in-app flow (workspace invites) and works regardless of this flag.

## First login

On first login a user lands in onboarding: create a workspace (naming
themselves for their signing identity — that name is what recipients of their
shares and requests see) or join one by pasting an invite key.
