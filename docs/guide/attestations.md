# Attestations

An attestation is a statement someone else confirms about its holder: a
club confirms a membership, an age check confirms an age, an employer
confirms a position. The holder keeps it and decides what to disclose. A
requesting service sees only the selected details and can verify them
without contacting the issuer.

| | Vault record | Attestation |
|---|---|---|
| Written by | The owner | Someone else, about the holder |
| Proves | That the owner wrote it | That a domain stands behind it |
| Reaches a service as | A share | A proof generated on the device |
| Ended by | The owner, by revoking the share | The issuer, by revoking it |

**Attestations** is in the sidebar, or under **More** on a phone. **Held**
lists what others confirmed about the holder, **Issued** what the
workspace confirmed about others, and **Checked** what others presented.

## Accepting an attestation

An attestation arrives as an offer link (`revoked://a/…`) that opens the
app. Before acceptance, the app shows:

- **Issuer**: the domain, with the same check a share or request
  receives. A verifier later refuses an attestation from a domain that does
  not verify, so this result matters.
- **Details**: the kind, and every detail with its value.
- **Identity**: one of the holder's identities. The
  attestation is bound to that identity's key, which stays on the device
  where the identity was created.

**Accept** proves ownership of the identity to the issuer by signing with
its key. Nothing else is sent. The holder's server verifies the returned
attestation and stores it under **Held**.

An offer is valid for one identity. Reopening it with the same identity
before it expires allows **Fetch again** to retrieve the attestation once
more, for example after accidental removal. This requires the identity's
key each time. If the key was lost with a device, a new attestation must be
requested for a new identity.

## Requesting an attestation

**New → Attestation about you** takes the kind, optionally what should be
confirmed, and the identity. **Create link** produces a link for the
issuer. It opens the issuer's form prefilled, and the issuer returns an
offer.

## Held attestations

Each attestation under **Held** shows its kind, its issuer, the identity
holding it, and its status:

| Status | Meaning |
|---|---|
| **Verified** | The signer's key checks out, and both the attestation and the identity are still valid. |
| **Issuer unverified** | The issuing domain has no DNS record, so it cannot be checked. |
| **Unverified** | Something could not be checked, for example because the issuing server is unreachable. |
| **Revoked** | The issuer withdrew it, or the identity it belongs to was revoked. |
| **Expired** | Its end date has passed. |
| **Not genuine** | Its signature does not match the domain it names. |
| **Unreadable** | The app could not read it. |

The detail view shows its contents. **Remove attestation** deletes it from
the holder's server. This does not revoke it: the issuer still stands
behind it.

Revoking the identity it belongs to invalidates the attestation as well.
No verifier accepts one whose holder's identity was withdrawn.

## Presenting an attestation

A service asks to see one with a `revoked://present` link. The app shows
the service's web address, since that is what identifies it, together with
what it asks for: the kind, the issuers it accepts, and the details it
needs.

Matching attestations are offered for selection. Each detail has a
checkbox; those the service asked for start ticked, and any can be
unticked or added. The issuer, the kind and the identity are always
disclosed.

**Show it** generates the proof on the device and sends it. The proof is
signed with the identity's key and bound to this one request, so the
service cannot pass it on and a copy is of no use to anyone else.
**Decline** sends nothing.

## Checking an attestation

**New → See someone's attestation** asks another person to present an
attestation, such as a membership. The kind, the accepted issuers and the
required details are all optional. **Create check** produces a code to
scan with Revoked, and a link as an alternative. It is valid once, for ten
minutes.

The result shows what was presented and its status at the moment it
arrived. Details not disclosed are marked **Withheld**. Checks remain
listed under **Checked**.

## Issuing attestations

A workspace can confirm facts about other people in the name of its
server's domain. This requires:

- attestations enabled by the server operator
  ([`ALLOW_ATTESTATIONS`](../installation/env.md#attestations)), and
- the **Issue attestations** permission. Workspace admins hold it and can
  grant it to others.

**New → Attestation** takes:

- the **Kind**, a single word without spaces, such as `membership`,
- the details, each a name with a text, yes/no or number value
  (**Add detail**),
- optionally, a **Recipient fingerprint**, and
- optionally, the number of days it is **Valid for**.

**Create offer** does not sign anything yet. It produces an offer link for
the person the attestation is about. The link is shown only once and must
be passed on immediately. The attestation reads **Offered** until
accepted, then **Issued**, together with the identity that accepted it.

An attestation's content cannot be changed once it exists. **Revoke**
withdraws it: verifiers learn of it within minutes, and it cannot be
undone. Deleting an issued attestation also revokes it.

A domain is trusted by whoever chooses to trust it. An attestation is worth
what the issuing domain's word is worth to the service reading it.
