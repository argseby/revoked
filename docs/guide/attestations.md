# Attestations

An attestation is something another party confirms about one of your
identities: a club its membership, a verification service an age, an
employer a position. It is signed by that party's domain and held by you. A
service that asks for it is shown only the claims you tick, and can check
them without calling the party that attested.

| | Vault entry | Attestation |
|---|---|---|
| Written by | You | Someone else, about you |
| Proves | That you wrote it | That a domain stands behind it |
| Reaches a service as | A share or a grant | A presentation, made on your device |
| Ended by | You, by revoking the share | Its issuer, by revoking the attestation |

Everything about attestations is under **Settings → Attestations**.

## Receiving one

An attestation arrives as an offer link, `revoked://a/…`, which opens the
app. Before anything is decided the offer shows:

- **Who attests** — the domain, with the same verdict a share or request
  gets. A credential from a domain that does not verify is refused by
  whoever checks it later, so the verdict matters here.
- **What it states** — the type and every claim with its value.
- **Which identity it is issued to** — one of yours. The credential is bound
  to that identity's key, which stays on the device it was created on.

**Accept** proves to the attester that the chosen identity is yours, by
signing its challenge with the identity key. Nothing else is sent. The
credential that comes back is checked by your own server and kept there; it
then appears under **Held**.

An offer works for one identity. Opened again with the same identity before
its date, it returns the credential again, for example after the credential
was removed by mistake. The identity's key is needed each time, so an
attestation bound to an identity whose key was lost with its device is
issued anew, to a new identity.

## What is held

Each held attestation shows its type, the domain that attested it, the
identity holding it, and its standing:

| Standing | Meaning |
|---|---|
| **Verified** | The attester's key verifies, and the attestation and your identity both stand. |
| **Unverified** | Something could not be checked, such as an attester that is unreachable or has no DNS record. |
| **Revoked** | The attester withdrew it, or the identity it is bound to was revoked. |
| **Expired** | It is past its own validity. |

Opening one lists its claims. **Remove** deletes the credential from your
server. That does not revoke it: the attester still stands behind what it
attested.

Revoking the identity an attestation is bound to ends the attestation's use
as well, since nobody accepts a credential whose holder's identity was
withdrawn.

## Showing one

A service asks with a `revoked://present` link. The app then shows who is
asking — its web address, which is what identifies it — and what it asks
for: a type, the attesters it accepts, the claims it needs.

The held attestations that fit are listed, and under the chosen one every
claim has a tick. The claims the service asked for start ticked; any of them
can be withheld, and others added. Who attested, the type and the identity
are always shown.

**Show it** makes the presentation on the device and sends it to the
service. It is signed with the identity key and made for this one request,
so the service cannot pass it on and nobody who copies it can use it.
**Decline** sends nothing.

## Issuing

A workspace can attest things about other people, in the name of the
server's domain. Two things have to be in place:

- the server's operator has switched attestations on
  ([`ALLOW_ATTESTATIONS`](../installation/env.md#attestations)), and
- the member holds the **Issue attestations** permission. Workspace
  administrators hold it and can grant it.

**New** under **Issued** asks for:

- a **type**, written without spaces, such as `membership`,
- the **claims**, each a name with a text, a yes/no or a number,
- optionally one **identity** the offer is for, by fingerprint, and
- optionally a **validity** in days.

Creating it signs nothing yet. It produces an offer link that is shown once
and sent to the person the attestation is about. The attestation reads
*Offered* until they accept it, then *Issued*, together with the identity
that accepted it.

What an attestation states is fixed once it exists. **Revoke** withdraws it:
anyone who verifies the credential is told so within minutes, and it cannot
be undone. Deleting an issued attestation revokes it too.

A domain is believed by those who choose to believe it. An attestation is
worth what the attesting domain's word is worth to the service that reads it.
