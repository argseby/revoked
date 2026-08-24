# Identities & trust

An identity is how a share or request proves where it came from. The keypair
is generated **on your device** and the private key never leaves it — it
lives in the system keychain, and the server only ever sees the public half,
signed by your server's root key. That root key's fingerprint is published in
your server's DNS, which closes the chain: DNS names the key, the key signed
the identity, the identity signed what you received.

## Your identities

You name your first identity during onboarding — that name is what recipients
see. Under **Settings** you can create more, mark one as **primary** (the
default offered when a share or request wants an identity attached), and
revoke ones you no longer stand behind.

Revocation is one-way. The certificate itself is long-lived, so revocation is
what tells verifiers to stop honouring it — deleting the row instead would
leave them guessing, which is why identities are tombstoned, never erased.
Losing the device loses the private key too; there is no export, by design.

## Reading a verdict

Whenever a share, request or invite arrives, the app verifies its identity
claim and shows a verdict — always with the reason, never a bare badge:

| Verdict | Meaning | The app… |
|---|---|---|
| **Verified** | DNS, key, signature and current status all agree. | Proceeds. |
| **Unverified** | No DNS record published, or an identity predating verification. Unproven, not forged. | Asks for explicit confirmation. |
| **Spoofed** | The cryptographic claim contradicts DNS. | Blocks. This is not a misconfiguration. |
| **Revoked** | Everything checks out, but the issuer withdrew the identity. | Blocks. |

The check runs against public DNS-over-HTTPS resolvers, so it does not trust
the network you happen to be on. A check that cannot complete counts as
unverified — the gate fails safe instead of silently disengaging.

## When you leave a workspace

Being removed from a workspace revokes the identities you used in it, in the
same transaction. That is the point of the whole chain: the certificate still
proves what it proved on day one, so only the issuer's *current* opinion —
revocation — can end its story.

## Checking your own domain

Self-hosting? **Settings → Developer → Domain verification** runs the full
chain against your own server and names exactly which step fails, if one
does. Until the [DNS record](../installation/dns.md) is published, everything you
issue shows as unverified — publishing it fixes that retroactively.
