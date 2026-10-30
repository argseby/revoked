# Attestations

An attestation is something someone else confirms about you. A club
confirms your membership, an age check confirms your age, an employer
confirms your job. You keep it, and you decide what to show. A service that
asks sees only the details you tick. It can check them without contacting
whoever confirmed them.

| | Vault record | Attestation |
|---|---|---|
| Written by | You | Someone else, about you |
| Proves | That you wrote it | That a domain stands behind it |
| Reaches a service as | A share | Proof made on your device |
| Ended by | You, by revoking the share | Whoever confirmed it, by revoking it |

Open **Attestations** in the sidebar. **Held** is what others confirmed
about you, **Issued** is what you confirmed about others, and **Checked**
is what others showed you.

## Accept an attestation

An attestation arrives as an offer link (`revoked://a/…`) that opens the
app. Before you decide, it shows:

- **Who confirms it**: the domain, with the same check a share or request
  gets. Whoever checks your attestation later will refuse one from a domain
  that doesn't verify, so pay attention here.
- **What it confirms**: the kind, and every detail with its value.
- **Which identity gets it**: one of yours. The attestation is tied to that
  identity's key, which stays on the device where you created it.

**Accept** proves to the other side that the identity is yours, by signing
with its key. Nothing else is sent. Your own server checks the attestation
that comes back and keeps it. You'll find it under **Held**.

An offer works for one identity. Open it again with the same identity
before it runs out, and **Fetch again** gets you the attestation once
more, for example after you removed it by mistake. That needs the
identity's key each time. If the key was lost with a device, ask for a new
attestation for a new identity.

## Ask someone to confirm something

Choose **New → Attestation about you**. Say what kind it is, and what they
should confirm if you like, then pick your identity. **Create link** gives
you a link to send to whoever confirms it. It opens their form already
filled in, and they send you back an offer.

## What you hold

Each attestation under **Held** shows its kind, who confirmed it, which
identity holds it, and its status:

| Status | What it means |
|---|---|
| **Verified** | Its signer's key checks out, and both the attestation and your identity still stand. |
| **Issuer unverified** | The confirming domain has no DNS record, so it can't be checked. |
| **Unverified** | Something couldn't be checked, for example because the confirming server can't be reached. |
| **Revoked** | Whoever confirmed it withdrew it, or the identity it belongs to was revoked. |
| **Expired** | It's past its end date. |
| **Not genuine** | Its signature doesn't match the domain it names. |
| **Unreadable** | The app couldn't read it. |

Open one to see its details. **Remove attestation** deletes it from your
server. That doesn't revoke it: whoever confirmed it still stands behind
it.

Revoke the identity it belongs to, and the attestation stops working too.
Nobody accepts one whose holder's identity was withdrawn.

## Show an attestation

A service asks to see one with a `revoked://present` link. The app shows
who is asking by their web address, because that's what identifies them.
It also shows what they want: the kind, whose confirmation they accept,
and the details they need.

Pick from the attestations that fit. Each detail has a tick box. The ones
the service asked for start ticked. You can untick any of them, or tick
more. Who confirmed it, its kind and your identity are always shown.

**Show it** makes the proof on your device and sends it. It's signed with
your identity's key and made for this one request. The service can't pass
it on, and nobody who copies it can use it. **Decline** sends nothing.

## Check someone else's attestation

Want to see an attestation someone else holds, such as a membership?
Choose **New → See someone's attestation**. Say what kind you want, whose
confirmation you accept, and which details you need. All three are
optional. **Create check** gives you a code for them to scan with Revoked,
and a link you can send instead. It works once, for ten minutes.

When they answer, you see what they showed and how it stood the moment it
arrived. Details they chose not to show are marked **Withheld**. Your
checks stay listed under **Checked**.

## Confirm something about someone

Your workspace can confirm things about other people, in the name of your
server's domain. You need two things:

- whoever runs the server has switched attestations on
  ([`ALLOW_ATTESTATIONS`](../installation/env.md#attestations)), and
- you have the **Issue attestations** permission. Workspace admins have it
  and can give it to others.

Choose **New → Attestation** and fill in:

- the **Kind**, one word without spaces, such as `membership`,
- the details, each a name with a text, a yes/no or a number
  (**Add detail**),
- optionally, **Only for this identity**, by its fingerprint, and
- optionally, how many days it's **Valid for**.

**Create offer** doesn't sign anything yet. It gives you an offer link to
send to the person it's about. The link is shown only once, so pass it on
right away. The attestation reads **Offered** until they accept, then
**Issued**, together with the identity that accepted it.

What an attestation confirms can't be changed once it exists. **Revoke**
withdraws it: anyone who checks it is told within minutes, and it can't be
undone. Deleting an issued attestation revokes it too.

A domain is trusted by whoever chooses to trust it. An attestation is
worth what the confirming domain's word is worth to the service that
reads it.
