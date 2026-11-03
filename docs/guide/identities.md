# Identities & trust

An identity lets recipients verify that a share or request really comes
from its sender. It is bound to the server's domain, so a forgery sent in
someone else's name shows up as a forgery.

An identity's private key is generated on the device and never leaves it;
it is stored in the system keychain. The server receives only the public
half, and signs it. The domain's DNS names the server's key. This closes
the chain: the domain vouches for the server, the server vouches for the
identity, and the identity signs what is sent. The
[trust chain](../api/trust-chain.md) has the details.

## Managing identities

The name chosen at setup is the name recipients see. Under
**Settings → Identities**, further identities can be created, one can be
made the default with **Set as primary** (offered first when signing a
share or request), and identities no longer in use can be withdrawn with
**Revoke**.

Revocation cannot be undone. An identity's certificate stays valid for
years, so revocation is what signals that it should no longer be trusted.
Any verifier, on the same server or another, learns of it within the hour.
Links and requests it signed keep working, but no longer show as verified.
Revocation also erases the private key from the device. Revoked identities
remain on record rather than being erased, so their status stays
answerable.

A lost device means a lost private key. There is deliberately no export.

## Sender verification {#check-who-sent-something}

Every incoming share, request or invite is checked for its sender. The
result is always shown with its reason, never as a bare badge:

| Result | Meaning | App behaviour |
|---|---|---|
| **DNS verified** | The domain, the keys, the signature and the identity's status all agree. | Proceeds. |
| **Not verified** | The domain has not published its DNS record, or the identity predates this check. Not proven, but not forged either. | Asks for confirmation before proceeding. |
| **Spoofed** | The claim contradicts what the domain publishes. | Blocks it. This is not a setup mistake. |
| **Revoked** | Everything checks out, but the sender's server has withdrawn the identity. | Blocks it. |

The app queries public DNS services over an encrypted connection,
independent of the local network. If the check cannot complete, the result
is **Not verified**. A failed check never counts as a pass.

## Attestations

An identity establishes origin and nothing else. Facts such as age, a
membership or an occupation are confirmed by others, as
[attestations](attestations.md). Each attestation belongs to one identity;
revoking the identity also invalidates its attestations. Replacing it
instead carries them over.

## Replacing an identity

**Replace** under **Settings → Identities** puts another identity in an
identity's place. The replacement is a new identity, created on the device
with a name chosen in the same step, or another identity that already signs
on this device. The action is offered only where the old identity's key is
on the device, since that key vouches for the replacement.

Every attestation bound to the old identity is then issued again for the
new one. The old identity's key vouches for the new identity and the new
identity's key answers the issuer, so no issuer has to act. Each attestation
keeps its statement and dates. The copy bound to the old identity is
revoked as the new one is issued. A primary identity's replacement becomes
the primary. Once every attestation has moved, the old identity is revoked.

An issuer that cannot be reached leaves its attestation on the old identity,
and the sheet lists it with the reason. **Retry** tries those once more.
**Revoke anyway** revokes the old identity, and the attestations left on it
stop being valid with it; each has to be asked for again from its issuer.
**Not now** leaves the old identity standing with them, and replacing it
later with the identity created the first time moves the rest.

Replacing comes before revoking for a reason: once the old identity is
revoked, its key can no longer vouch for anything, and its attestations can
no longer move. This is also what makes a lost device urgent. Until its
identities are replaced, a copy of their keys could move their attestations
too. Such a move shows as a refusal when the replacement is attempted.

## Leaving a workspace

When a member is removed from a workspace, the identities they used there
are revoked at the same moment. This follows from the chain: a certificate
keeps proving what it proved on the day it was issued, and only revocation
can end it.

## Domain verification

For a self-hosted server, **Settings → Developer → Domain verification**
checks the full chain against its domain and reports which step fails.
Until the [DNS record](../installation/dns.md) is published, everything
sent shows as **Not verified**. Once it is published, earlier shares and
requests show as verified as well.
