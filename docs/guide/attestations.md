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

## Example: club membership

A club at `club.example.com` confirms two facts about a member:

| Detail | Value |
|---|---|
| `membership_active` | `true` |
| `member_number` | `C-1042` |

The member accepts the offer in the Revoked app, binding it to one of their
identities. A ticket service later asks for `membership_active` from that club.
The member can present that detail while leaving `member_number` undisclosed.
The issuer, the kind of attestation and the holder's identity are still shown.

The ticket service must decide that `club.example.com` is an acceptable
membership issuer. A valid signature proves who confirmed the fact; it does
not make every domain's membership claim acceptable. If the club revokes the
attestation, later checks no longer accept it.

A vault record containing `membership_active=true` is only the owner's own
statement. It does not substitute for the club's confirmation.

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

## Sharing an attestation

A held attestation can also be shown through a link, without waiting for
someone to ask. **Share link** in the attestation's detail view takes:

- the **details** to include, all ticked at first; any can be left out, and
  the issuer, the kind and the identity are always shown, and
- how long the link stays **open**: one day, seven days or thirty days.

**Create link** signs a presentation of the picked details on the device,
with the identity's key, for that one link. The link and its QR code are
shown once and cannot be retrieved later. It opens as a page in any
browser; the Revoked app is not needed to read it.

The page shows the kind, the issuer, the picked details and the status.
The status is checked again every time the page is opened, so a link to an
attestation the issuer revoked, or one that expired, says so.

| | Link | Check |
|---|---|---|
| Started by | The holder | The person who wants to see it |
| Proves | What the issuer attests, signed by its holder | That, and that the person answering holds it right now |
| Can be passed on | Yes, and it still shows the same | No: it is valid once, for ten minutes |

A link proves what the issuer attests. It does not prove that whoever
passes the link on is the holder. Where that matters, such as at a door or
for an age limit, a check is the right tool.

The detail view lists the open links with how often each was opened.
**End link** closes one at once. Removing the attestation ends all of its
links.

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

### Who sees an attestation {#members}

An issued attestation is seen by every member who can view attestations.
**Visibility** in its options, offered to whoever issued it, keeps it to them
instead (**Private**), and sets whether other members who may issue
attestations can revoke it. Owning an attestation is not enough to revoke
it: that always takes the permission to issue, since an attestation speaks
for the server's domain.
