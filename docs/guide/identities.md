# Identities & trust

An identity lets recipients verify that a share or request really comes
from its sender. It is bound to the server's domain, so a forgery sent in
someone else's name shows up as a forgery.

An identity's private key is generated on the device and stored in the
system keychain. The server receives only the public half, and signs it.
The domain's DNS names the server's key. This closes the chain: the domain
vouches for the server, the server vouches for the identity, and the
identity signs what is sent. The [trust chain](../api/trust-chain.md) has
the details.

With [end-to-end encryption](encryption.md) on, the private key also
travels — encrypted, so the server cannot read it — to the other devices
on the account's device list, and the recovery key restores it. The same
identity then signs from every trusted device, and the attestations bound
to it stay usable when a device is lost. Without encryption, the key never
leaves the device that made it, and each device needs an identity of its
own.

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
Revocation also erases the private key, from this device and from the
encrypted copy the other devices read. Revoked identities remain on record
rather than being erased, so their status stays answerable.

Removing a device from the device list stops it from reading anything new,
but a key it already held stays in its memory. A device that was lost or
stolen while unlocked therefore calls for revoking the identities it could
sign with, the same way the vault's guidance asks for secrets it knew to
be changed.

Without end-to-end encryption, a lost device means a lost private key.
There is deliberately no export outside the encrypted device list.

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
revoking the identity also invalidates its attestations.

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
