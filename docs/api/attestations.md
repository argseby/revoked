# Attestations

An attestation is a statement one domain signs about an identity, usually an
identity issued by another domain: `verify.example` confirms that an identity
belongs to an adult, `club.example` confirms a membership. The person the
statement is about holds it as a credential and shows it to a service when
asked, claim by claim.

Three parties take part, and each of them can be a different Revoked server
or none at all.

| Party | Role | What it runs |
|---|---|---|
| Attester | Signs the statement in the name of its domain. | A Revoked server with attestations switched on. |
| Holder | Keeps the credential and presents it. | The Revoked app, signed in to the holder's own server. |
| Verifier | Asks for an attestation and checks what is presented. | Any service. A Revoked server can do the checking for it. |

The endpoint reference is under [Attestations](reference/attestations.md).
The user-facing side is described in the
[guide](../guide/attestations.md).

## What a credential holds

A credential is an SD-JWT VC (RFC 9901 with the SD-JWT VC profile), signed
with ES256. The format is the standard one, so that a credential issued today
is not reissued when wallets and verifiers outside Revoked are added. What is
specific to Revoked is how the issuer's key is found and checked: through the
DNS pin, as for every other signature.

| Claim | Content | Disclosure |
|---|---|---|
| `iss` | `https://<attester domain>` | Always |
| `vct` | The type the attester chose, such as `membership`. | Always |
| `iat`, `exp` | Issue date, and expiry where one was set. | Always |
| `cnf.jwk` | The holder's identity key. Only its holder can present the credential. | Always |
| `revoked_holder` | The identity the statement is about: its fingerprint and the domain that issued it. | Always |
| `status` | The credential's position in the attester's status list. | Always |
| Everything the attester states | One claim per name, with a text, number or true/false value. | Chosen by the holder, claim by claim |

A claim the holder withholds is present only as a salted digest. The verifier
learns that the credential holds more, not what.

## Issuing

Issuing is off unless the operator sets `ALLOW_ATTESTATIONS=true`: an
attestation speaks for the server's domain, and on a server several people
share that is the operator's decision. Within a workspace, issuing needs the
**Issue attestations** permission, which workspace administrators hold and
can grant, and which an API key can carry.

An attestation is created as an offer, through the collection API:

```bash
curl -i "https://verify.example/api/collections/attestations/records" \
  -H "X-API-Key: $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "workspace": "<workspace id>",
    "type": "verified_adult",
    "label": "Age check, order 4711",
    "claims": { "age_over_18": true },
    "expiresAt": "2027-10-01 00:00:00.000Z"
  }'
```

| Field | Meaning |
|---|---|
| `type` | Required. Up to 255 characters without spaces: a short key or a URI. |
| `claims` | A flat set of named values. Names are letters, digits and underscores; values are text, numbers or true/false. Names the credential format sets itself, such as `iss` or `exp`, are refused. |
| `label` | A name for the attester's own list. It is shown to the subject, and is not part of the credential. |
| `expiresAt` | When the credential stops being valid. Left out, it is valid until revoked. |
| `offerExpiresAt` | Until when the offer can be accepted. Fourteen days when left out. |
| `subjectFingerprint` | Makes the offer for one identity only, named by its fingerprint — for example the identity a request was answered with. |

The response carries the offer's one-time token in the `X-Attestation-Token`
header. Only its hash is stored, so the token is shown this once. It is sent
to the subject as a link, which names the server the offer lives on:

```text
revoked://a/verify.example/<token>
```

Nothing is signed at this point. The link opens the subject's app, which
shows the attesting domain, the type and every claim. On acceptance the
subject's identity key signs a challenge from the attester's server, the
attester checks the identity with the server that issued it, and the
credential is issued, bound to that key. The attestation then reads `active`
and names its subject (`subjectFingerprint`, `subjectDomain`, `subjectName`).
The credential is handed over once and not kept by the attester.

An offer works for one identity. That identity may accept it again until the
offer's date and receives the same statement again, so an answer lost on the
way or a credential removed by mistake costs nothing. The identity's key is
needed each time.

What an attestation states cannot be changed after it was created. It is
revoked, and a new one is issued:

```bash
curl -X PATCH "https://verify.example/api/collections/attestations/records/<id>" \
  -H "X-API-Key: $TOKEN" -H "Content-Type: application/json" \
  -d '{ "status": "revoked" }'
```

Revocation is published through the attester's status list and cannot be
undone. A deleted attestation is revoked as well, as is every attestation of
a deleted workspace: a credential is never left standing with nobody able to
withdraw it.

## Asking a person for an attestation

A service asks through the person's app, with a link the app answers
directly:

```text
revoked://present?client_id=https%3A%2F%2Fshop.example
  &response_uri=https%3A%2F%2Fshop.example%2Fpresent%2Fcallback
  &nonce=<random>&state=<random>
  &type=verified_adult&issuers=verify.example&claims=age_over_18
```

| Parameter | Required | Meaning |
|---|---|---|
| `client_id` | yes | The service's origin, as for a connected tool. It is the audience of the presentation. |
| `response_uri` | yes | Where the presentation is posted; on `client_id`'s origin. |
| `nonce` | yes | A fresh value per request, 8–256 characters of `[A-Za-z0-9._~-]`. The presentation commits to it. |
| `state` | | The service's own value, returned unchanged. |
| `type` | | The kind of attestation asked for. Left out, any is offered. |
| `issuers` | | Comma-separated attester domains the service accepts. Left out, the holder may offer a credential from any attester. |
| `claims` | | Comma-separated claims the service needs. They start ticked; the holder decides. |

The app shows who is asking and for what, lists the held credentials that
fit, and lets the person tick the claims to disclose. A link that is
malformed in any part is refused as a whole.

On agreement the app posts to `response_uri`:

```json
{ "presentation": "<issuer JWT>~<disclosure>~<key binding JWT>", "state": "…" }
```

The presentation is made on the person's device and signed with the identity
key. Its key binding names `client_id` as audience and carries the `nonce`,
so it is of no use to any other service or for any other request. The
service may answer with `{ "redirect_uri": "…" }` to continue in the
browser; an address outside its own origin is not followed. A declined
request sends nothing.

This link is Revoked's own, and it is the interim way to ask. The standard
presentation protocol, OpenID4VP, is step 4 of the
[roadmap](../roadmap.md); the credential and the presentation it carries are
already the standard ones.

## Verifying

A presentation is verified by any Revoked server the service relies on —
usually its own:

```bash
curl "https://shop-revoked.example/api/attestations/verify" \
  -H "Content-Type: application/json" \
  -d '{ "presentation": "…", "audience": "https://shop.example", "nonce": "<the nonce sent>" }'
```

Two chains are checked, as described under
[Trust chain](trust-chain.md#verifying-an-attestation). The attester's: DNS
pin, root key, certified credential key, signature, status list. The
holder's: the key binding made with the key the credential names, and the
current word of the server that issued the holder's identity.

```json
{
  "state": "verified",
  "reason": "verify.example attests this, its key is tied to the domain through DNS, …",
  "issuer": "verify.example",
  "issuerState": "verified",
  "type": "verified_adult",
  "claims": { "age_over_18": true },
  "withheld": 0,
  "status": "valid",
  "holder": { "fingerprint": "3fa2…", "domain": "home.example", "state": "verified", "status": "active" },
  "keyBound": true
}
```

| `state` | Meaning |
|---|---|
| `verified` | Both chains hold, and the holder presented it for this audience and nonce. |
| `unverified` | A check could not be completed: a server was unreachable, the status list does not reach the credential, or no audience and nonce were given. |
| `dnsMissing` | The attester publishes no `_revoked` TXT record, so no key can be tied to its domain. |
| `spoofed` | The credential is not signed by a key the attester's DNS-pinned root key certified. |
| `revoked` | The credential is genuine, and the attester revoked it or the holder's identity was withdrawn. |
| `expired` | The credential is genuine and past its own validity. |
| `invalid` | Not a readable credential, or the key binding does not verify. |

Only `verified` should be acted on. Claims are reported only when the
attester's signature verified.

### Which attesters are believed

The verdict states who attested. It does not decide whether that domain
deserves to be believed: DNS proves which domain signed, nothing more. A
service therefore compares `issuer` with the domains it accepts for the
statement in question, and `type` with the type it asked for, before it
relies on a claim. Anyone can run a server and attest anything about
themselves.

`audience` and `nonce` are what tell the holder from someone holding a copy
of the credential. Without them no key binding is checked and the verdict is
never `verified`.

## Limits

- **Presentations are linkable.** Every presentation of a credential shows
  the same holder key and the same identity. Services that compare notes can
  tell that the same person presented to both, unlike with the pairwise
  subjects of [sign-in](sign-in.md).
- **Revocation takes minutes.** A status list may be kept for five minutes,
  so a revocation reaches a verifier within that time.
- **A restored backup forgets later revocations.** As with identities, the
  status list is part of the database. Revocations made after the backup are
  lost with a restore of it.
- **The verifier contacts the holder's server.** The identity's status is
  asked for at the domain that issued it, which thereby learns that a check
  took place and from which address. The attester learns nothing: its status
  list is read as a whole.
