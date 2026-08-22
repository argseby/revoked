# Verifying who sent something

A share or a request arrives with a claim attached: *this came from an identity
issued by `example.com`*. Every field of that claim is attacker-controlled until
you check it. This page is how you check it.

The chain has four links, and all four have to hold.

## 1. DNS says which key speaks for the domain

Read the `_revoked.<domain>` TXT record. It pins the SHA-256 fingerprint of the
domain's root key.

This is the anchor. It is the one step an attacker cannot forge by serving you
a convincing response, because they do not control the victim's DNS.

## 2. The domain serves a key matching that pin

Fetch `GET https://<domain>/api/server` and compare `fingerprint` against the
TXT record. If they disagree, stop — someone is standing between you and the
domain, or the domain is not who it claims.

A key served without a matching DNS pin proves nothing at all: whoever serves
the response also chooses what it says.

## 3. That key signed the identity

The probe gives you the sharer's `fingerprint` and `parentSignature`. Verify the
signature against the root key from step 2. This is what ties an individual
identity to the domain.

An identity with no `parentSignature` predates DNS verification. It is not
forged — it is simply unproven, and should read differently from a mismatch.

## 4. The issuer still stands behind it

This is the step most implementations forget, and the one that matters most.

A certificate is minted for ten years and its `parentSignature` never expires.
Someone removed from a workspace still holds a key that proves exactly what it
proved on their first day. A challenge signature does not help: it proves
possession, which they still have.

Only the issuer's current opinion closes this, and it lives at
`GET /api/identities/{fingerprint}/status`. The answer is signed by the same
root key you already pinned, so it needs no separate trust and a proxy cannot
rewrite it.

!!! warning "`unknown` is not `revoked`"
    A restored backup or a reinstall answers `unknown` about identities that
    were perfectly valid. Treating the two the same turns a routine restore
    into a mass revocation. Report them differently.

Probes staple this answer into the response as `statusAssertion` so you need no
second round trip — but verify its signature rather than trusting the field,
since it arrives over the same channel as everything else you are checking.

## What a verdict should mean

| Outcome | Meaning | What to do |
|---|---|---|
| Verified | All four links hold. | Proceed. |
| Unverified | No DNS record, or no parent signature. | Allow with an explicit warning — this is the default for a server that has not finished DNS setup. |
| Spoofed | DNS pin and served key disagree, or the signature fails. | Block. This is not a misconfiguration. |
| Revoked | Every signature holds, and the issuer has withdrawn the identity. | Block. Nothing was forged; the vouching stopped. |

## A note on failing safe

A check that could not complete is an *unverified* identity, not a verified one
and not an error to swallow. Timeouts, captive portals and unreachable
resolvers must all land on a verdict, or the gate silently disengages exactly
when the network is least trustworthy.
