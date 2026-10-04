# Roadmap: identity and live data

This page describes a planned direction, not existing behavior. Nothing here
is implemented unless a table marks it as existing. The endpoints, event names
and field names below are working names and may change before they ship.

The direction combines two ideas. The first is that services hold a
**reference** to someone's data instead of a copy, as shares and requests
already do inside one server. The second is that a service learns **who** it
is dealing with, and which facts about that person have been confirmed by
someone it trusts, without the data being copied along the way.

## What can and cannot be proven

A signature proves that the holder of a key took part. It does not prove which
human is in front of the screen. Every system built on keys, including
government wallets, works around this the same way:

1. **One check of the person.** A party the service trusts confirms the person
   once, for example from the chip of an ID card, and signs a statement about
   them.
2. **A binding to a key.** That statement names a key held on the person's
   device and unlocked with a biometric or PIN. Each later use proves that the
   key is held by whoever passed the check.

Revoked already provides the second part: identity keys are generated on the
device (ECDSA P-256) and never leave it, and possession is proven through the
challenge handshake. The first part, and the protocols that carry the result to
a service, are what this roadmap adds.

A value in the vault is a different matter. It is written by the owner and
proves only that the owner wrote it. It becomes a confirmed fact only when a
third party signs it, which is what the attestations in step 3 are for.

## Three layers

| Layer | Question answered for the service | Example |
|---|---|---|
| Live data | What is the current value, and may it still be read? | A mailing tool sends to the address as it is today and drops it the moment it is revoked. |
| Sign-in | Is this the same person as last time, and from which server? | A game server recognizes a returning player without its own accounts. |
| Attested facts | Has someone trusted confirmed this about the person? | A shop learns that a buyer is a verified adult, without receiving an ID card scan. |

## Built into the server

Every step is implemented inside the PocketBase application itself: routes on
its router, data in its collections, schema changes as migrations in
`migrations/`, background work in its hooks. No separate service or sidecar is
introduced, so a self-hosted instance stays one container and one data
directory.

Signing reuses what is already in the module graph. JSON Web Signatures are
available through `golang-jwt`, which PocketBase already depends on, and
SD-JWT is a thin layer on top of a JWS (salted disclosures, hashed with
SHA-256). A new dependency is considered only where a specification is too
large to implement by hand, and that decision is made per step.

## Existing foundations

| Piece | Where it lives today |
|---|---|
| Server root key, RSA-2048, fingerprint pinned in `_revoked.<domain>` | `GET /api/server`, signed assertion valid for 24 hours |
| Identities on the device, ECDSA P-256, signed by the root key | Identity certificates, `parentSignature` |
| Signed identity status (`active`, `revoked`, `unknown`) | `GET /api/identities/{fingerprint}/status` |
| Proof of key possession | Challenge handshake on shares and requests |
| Browser sign-in with a passkey, code bound to a PKCE challenge | `GET /passkey`, `POST /api/passkeys/token` |
| OpenID Connect provider (step 2) | `/.well-known/openid-configuration`, `/oidc/authorize`, `/oidc/token`, `/oidc/userinfo`, `/oidc/jwks` |
| Tools identified by their origin, PKCE code exchange | `revoked://connect`, `POST /api/connect/token` |
| Live grants from request answers | `GET /api/requests/{id}/links` |
| Callbacks through a client that refuses redirects and private addresses | Submissions delivered once; grant events retried with backoff |
| Revocation noticed by the requester | In-app notification, a grant event to the request's callback, and a signed event to the requester's server for an answer kept elsewhere |
| Answers kept on the responder's own server (step 1) | `POST /api/requests/remote`, `POST /api/public/requests/{slug}/remote` |
| Bulk grant reads with ETags and `maxAge` (step 1) | `POST /api/grants/resolve` |
| Signed grant events between servers (step 1) | `POST /api/grants/events` |
| Credential key, ECDSA P-256, certified by the root key (step 3) | `GET /.well-known/jwt-vc-issuer` |
| Attestations as SD-JWT credentials, offered and accepted (step 3) | `attestations` collection, `GET /api/attestations/offers/{token}`, `POST …/claim`, `POST /api/credentials/claim` |
| Status list of issued credentials (step 3) | `GET /api/attestations/status` |
| Verification of a presented credential along both chains (step 3) | `POST /api/attestations/verify` |
| Presentation from the app, bound to verifier and nonce (step 3) | `revoked://present` |

## Step overview

| Step | State | Nature of the work |
|---|---|---|
| 1. Live data across servers | Implemented | Revoked's own code, no external specification |
| 2. Sign in with Revoked (OpenID Connect provider) | Implemented | A finished standard on top of the existing passkey flow |
| 3. Attestations by other domains | Implemented | Issued in the format of step 4, anchored through the existing DNS pin |
| 4. OpenID4VCI and OpenID4VP | Buildable now, limited interoperability | The credential format is in place with step 3; the two protocols remain. Acceptance by official verifiers depends on wallet certification |
| 5. eID and EU wallet as a source | Outside the code | Legal access and partnerships |

## Step 1: Live data across servers

### The gap

A request answer becomes a live grant only when the responder has an account
on the **requester's** server: the grant points at a record in a vault on that
same server. A mailing tool on its own instance therefore receives live grants
only from people who signed up there, and typed answers from everyone else.
A revocation is noticed only as an in-app notification, and callbacks fire on
submission alone.

### Planned additions

**Cross-server grants.** A responder signed in on their own server answers a
request from another domain. The grant is created on the responder's server,
as a link that resolves their vault record, and the requester's server stores
its address together with a grant token. The responder keeps seeing, updating
and revoking it in their own app, as with any share. The requester's server
resolves it on read, through the existing safe outbound client.

**Grant events.** The responder's server notifies the requester's server when
a grant changes state:

| Event | Sent when |
|---|---|
| `grant.revoked` | The responder revokes the grant or deletes the record behind it. |
| `grant.changed` | A record the grant resolves changes value, directly or through an alias. |
| `grant.expired` | The grant reaches its expiry or view cap. |

An event carries the grant's id and the new state, never a value; the receiver
reads the current value again if it needs it. Events are signed with the
sending server's root key, so they are verified with the same DNS-anchored
chain as everything else. Deliveries are retried with backoff, unlike today's
callbacks.

Each requester's server passes events on to its own callback URL, so a tool
behind a request learns about changes without polling.

**Detecting changes.** A record change fans out to every active grant that
resolves it, including grants that reach it through an alias. This needs an
index from record to grants, kept current when grants are created or revoked.

**Bulk reading.** A tool reading thousands of grants needs one request per
batch rather than one per grant, ETags per grant, and a cache hint
(`maxAge`) set by the responder's server, so a tool may keep a value briefly
without holding a copy indefinitely.

### As implemented

The step is in place as planned. Where the implementation settled a detail
the plan left open, it is recorded here.

| Part | Implementation |
|---|---|
| Relaying an answer | The responder's app sends the answer to its own server (`POST /api/requests/remote`), which reads the request's probe from the other server, writes the entries and the link, and hands the link's id and a fresh token to the other server (`POST /api/public/requests/{slug}/remote`). If the other server refuses, everything written for the answer is taken back. |
| Accepting it | The requester's server applies every gate a local answer passes, reads the grant once with the token to confirm it resolves, and checks the template against those values. It keeps the grant's address, token and keys (`remoteGrants`), not the values. |
| Proven identities | A request that requires a proven identity accepts one issued by the relaying server: the challenge comes from the requester's server, and the identity's chain and current status are checked against the relaying server's DNS-pinned root key. |
| Reading | `GET /api/requests/{id}/links` lists remote answers next to local ones (`remote: true`, `server`). Answers on the same server are read in batches of up to 100. A value is kept in memory for at most the `maxAge` the responder's server sets (`GRANT_MAX_AGE`, 60 seconds by default) and revalidated with its ETag after that. An answer whose server cannot be asked is marked `unreachable` and shows no values. |
| Events | A batch is signed with the root key at each delivery attempt and names its audience, so it cannot be replayed against another server; it is accepted for five minutes. Events about the same server are sent together. Undelivered batches are retried for about a day and a half. |
| Change detection | `grantRecords` indexes which request-born links read which entry, rewritten whenever a link is saved and emptied once it can no longer be read. A changed entry is announced to every link reading it or one of its aliases. Deleting an entry announces `grant.changed`, or `grant.revoked` when it was the last entry behind the link. |
| Local answers | Answers kept on the requester's own server send the same events to the request's callback, so a tool behind a request sees one behaviour wherever the answer lives. |
| Development | `PEER_OVERRIDES` maps a domain to an address and takes its key from there without the DNS pin, so two instances can exchange grants without public DNS. |

### Limits

A service still needs its own database for its own records, such as orders,
invoices and delivery logs, some of which are subject to retention periods.
What is replaced is the copy of the person's data, not the service's storage.
If a responder's server is unreachable, their grants do not resolve until it
returns; this is stated to the tool rather than hidden behind a stale copy.

## Step 2: Sign in with Revoked

Revoked becomes an OpenID Connect provider, so existing client libraries work
unchanged.

### Mapping onto what exists

| OpenID Connect part | Revoked |
|---|---|
| Authorization endpoint | The browser passkey page, extended by a consent screen for the service |
| Authorization code with PKCE | The one-time code flow already used by `/api/passkeys/token` |
| Client identification | The client's origin, as with connected tools; no prior registration needed for public clients |
| ID token signature | The root key, RS256 (the algorithm every OpenID Connect client supports) |
| Key publication | A new JWKS endpoint, with the key also bound to the DNS pin |
| Discovery | A new `/.well-known/openid-configuration` |

### Claims

| Claim | Content |
|---|---|
| `sub` | An identifier per service: the same person yields a different `sub` at each service, so services cannot match users across each other. |
| `name` | The display name, only when the person agrees. |
| `email`, `email_verified` | Only when agreed. `email_verified` reflects the existing signup confirmation. |
| `revoked_identity` | The identity fingerprint, when the person agrees to reveal it; it is the same at every service by nature. |
| `revoked_links` | Live grants for the data the service asked for, in place of copied values. |

Asking for data is expressed as a `claims` request naming vault keys. Data
requested this way is delivered as grants (step 1); a plain copy is not
offered (see the decisions below).

### Decisions

| Question | Decision |
|---|---|
| Which key signs ID tokens | A separate RS256 key (`oidc_signing.pem`), certified by the root key. The certification names the key by its RFC 7638 thumbprint and is published with it in the JWKS, so the DNS pin anchors every ID token while the root key signs only the certification. Replacing the signing key needs no DNS change. |
| Session lifetime at the provider | None. Every sign-in at a service is confirmed with a passkey, `prompt=none` answers `login_required`, and no refresh tokens are issued. A service keeps its own session after the sign-in. |
| Logout notifications | Not needed while there is no provider session: there is nothing at the provider to end. |
| Copies of values | Not offered. Vault entries are given only as grants (`revoked_links`), delivered at userinfo and never in the ID token. A service that wants a copy reads the grant and stores the value itself, which is its own decision and its own retention duty. |

Still open: how the root key is rotated, given that it is pinned in DNS.
That question belongs to the trust chain as a whole rather than to this step.

### As implemented

| Part | Implementation |
|---|---|
| Discovery and keys | `/.well-known/openid-configuration`, `/oidc/jwks`. The issuer is `https://<domain>`; a server reached at localhost answers as `http://localhost:<port>`, as the passkey page does, and any other Host header falls back to the domain. The issuer is fixed when a sign-in starts. |
| Authorization | `/oidc/authorize` validates the request, then serves a page that runs the passkey sign-in in the browser with a PKCE pair of its own (`/api/passkeys/login/*`), joins the result to the request (`/oidc/authorize/session`), and records the decision (`/oidc/authorize/consent`). Until the client's origin and redirect address check out, errors are shown, never redirected. |
| Tokens | `/oidc/token` (authorization code with PKCE, public clients, no secret) returns an ID token valid for 10 minutes and an access token valid for an hour. `/oidc/userinfo` answers with the granted claims. |
| Subjects | Pairwise: an HMAC of the person and the client origin under `oidc_subject.key`. |
| Shared entries | One link per person and service (`links.signInClient`), read through `POST /api/grants/resolve` with the token from userinfo, and revoked from the app like any link. |
| State | Requests, consent tickets, codes and access tokens are held in memory, like the passkey ceremonies: a restart costs a sign-in in progress. |
| Finding the server | A service starts a sign-in through the app with `revoked://signin` and the server-independent authorization parameters. The app opens the authorization page of the server it is signed into; the answer names that server in `iss` (RFC 9207), and the service discovers and verifies it from there. Without the app, the person names their server. |

## Step 3: Attestations by other domains

An **attestation** is a statement one domain signs about an identity of
another: for example, `verify.example` confirms that identity `X` belongs to a
verified adult with a given name, or `club.example` confirms a current
membership.

### What already fits

The trust chain verifies exactly this shape: DNS pin, served key, signature,
current status. Today it covers only a server's own identities. For
attestations, the issuer is a different domain from the one that issued the
identity, and both chains are checked.

### Design decisions

- **Format.** Attestations are issued as SD-JWT credentials from the start
  (step 4), with the DNS pin as the way to find and check the issuer's key.
  A format of Revoked's own would have to be replaced later.
- **Binding.** The credential names the holder's identity key (`cnf`), so only
  the device holding that key can present it.
- **Status.** The issuer's current opinion is checked through a status
  endpoint like the identity status today, or a status list as defined for
  SD-JWT credentials.
- **Trust.** DNS proves which domain signed, not whether that domain deserves
  trust. Which attesters a service accepts remains the service's policy, and
  is stated in the verification result rather than decided by Revoked.

### Decisions

| Question | Decision |
|---|---|
| Which key signs credentials | A separate ECDSA P-256 key (`credential_signing.pem`), certified by the root key under its own certification type, so a key certified for ID tokens is never accepted for credentials or the other way round. Published as SD-JWT VC issuer metadata. |
| How status is published | A Token Status List, one bit per credential, signed with the credential key. It is the mechanism SD-JWT credentials define, and it is named inside every credential, so a mechanism of Revoked's own would have meant reissuing every credential for step 4. A verifier reads the whole list, so the attester does not learn which credential was checked. |
| What is disclosable | Every claim the attester states, one by one. The issuer, the type, the holder's key, the holder's identity and the status reference are always shown: a verifier needs each of them to check the credential at all. |
| How the holder is named | By the fingerprint and the issuing domain of the identity (`revoked_holder`), next to the key itself (`cnf`). The verifier asks that domain whether the identity still stands, so a withdrawn identity ends the use of every credential bound to it. |
| Who may issue | The operator switches issuing on (`ALLOW_ATTESTATIONS`, off by default), and a member needs the *Issue attestations* permission. Administrators hold it; API keys can carry it. |
| How a credential reaches its holder | As an offer with a one-time link. The subject sees what would be stated, accepts with a proof of an identity key, and the attester checks that identity with the server that issued it before signing. OpenID4VCI replaces the wire format in step 4; the offer, the proof and the check stay. |
| How a credential reaches a verifier | Through `revoked://present`, answered by the app with a presentation posted to the service. It is the interim transport: OpenID4VP replaces it in step 4, and carries the same presentation. |

### As implemented

| Part | Implementation |
|---|---|
| Format | SD-JWT VC (`dc+sd-jwt`, ES256). Claims are salted digests opened by disclosures; a presentation ends in a Key Binding JWT (`kb+jwt`) over the audience, the nonce and the hash of exactly the disclosures presented. The holder's key is the identity key: ES256 for the P-256 keys the app creates, RS256 for RSA identities. |
| Issuer key | `GET /.well-known/jwt-vc-issuer` returns the issuer (`https://<domain>`) and the key with `revoked_certification`. Another server's key is accepted only after its root key was tied to the domain through the DNS pin and certified this key. |
| Offer | Creating an `attestations` record makes an offer and returns its token once (`X-Attestation-Token`). `GET /api/attestations/offers/{token}` shows the attester, the type and the claims while the offer is open. The link is `revoked://a/<host>/<token>`. |
| Acceptance | The app signs the attester's challenge (`/api/challenges/attestation/{token}`) with the identity key and calls its own server (`POST /api/credentials/claim`), which relays to the attester (`POST /api/attestations/offers/{token}/claim`). The attester checks the certificate against its fingerprint, the parent signature against the issuing server's DNS-pinned root key, and that server's current status answer. An offer works for one identity, which may claim it again until the offer's date. |
| Holding | The holder's server checks the returned credential before keeping it — the attester that was asked signed it, with a key tied to its domain, bound to the key and identity that asked — and stores it in `credentials`, readable by its owner alone. No API key reaches it. |
| Status | `GET /api/attestations/status` serves the list (`statuslist+jwt`), cacheable for five minutes. Positions are assigned at random in a list at least twice as long as the number of credentials. Revocation is one-way and is recorded apart from the attestation, so deleting an attestation, its workspace or its issuer's account leaves the credential revoked. |
| Verification | `POST /api/attestations/verify` takes a presentation with the audience and nonce it must be bound to, and answers with a verdict: `verified`, `unverified`, `dnsMissing`, `spoofed`, `revoked`, `expired` or `invalid`, with the attesting domain, the type, the disclosed claims and the holder's standing. Without audience and nonce the verdict is never `verified`. |
| Presentation | `revoked://present` names the service (its origin), the address to post to on that origin, a nonce, and optionally a type, accepted attesters and claims. The app lists the credentials that fit, lets each claim be ticked, signs the key binding on the device, and posts the presentation. |
| App | Offers, held credentials with their standing, the presentation screen, and issuing with revocation under *Settings → Attestations*. |
| Development | As for step 1, `PEER_OVERRIDES` lets two instances verify each other's credentials without public DNS. |

### Limits

Presentations of one credential are linkable: each shows the same key and
the same identity. The standard format offers no remedy short of issuing
many single-use credentials, which is left for later. A revocation reaches a
verifier within the five minutes a status list may be kept. A restored
backup forgets revocations made after it, as it does for identities.

Requests cannot yet require an attestation; a service asks for one
separately, through the presentation link.

## Step 4: OpenID4VCI and OpenID4VP

### Parts

| Part | Standard | Role in Revoked | State |
|---|---|---|---|
| Credential format | SD-JWT VC | Attestations; disclosure of single claims, for example `age_over_18` without the birth date | In place with step 3 |
| Status | Token Status List | Whether a credential still stands | In place with step 3 |
| Issuance | OpenID4VCI | An attester issues a credential to the app | Open; the offer link of step 3 is the interim |
| Presentation | OpenID4VP | A service asks for specific claims; the app presents only those, signed with the identity key | Open; `revoked://present` is the interim |

### Keys

The device identity keys are ECDSA P-256 and fit key binding as they are. The
server root key is RSA-2048, while the common credential profiles require
ES256. Issuing therefore uses a separate ECDSA P-256 key, certified by the root
key and published alongside it, so the DNS pin still anchors it. That key
exists since step 3.

A verifier outside Revoked does not know the DNS pin. For such verifiers the
issuer metadata at `/.well-known/jwt-vc-issuer` is what the standard
prescribes, resting on the domain's TLS certificate; the certification by the
root key is an addition they ignore.

### Interoperability

Within Revoked and with services that accept Revoked as a wallet, this works
fully. Official verifiers under the EU identity framework, such as banks
checking state-issued identity data, expect a certified wallet that proves its
certification. Revoked can present credentials to them technically, but
acceptance depends on certification, which is a matter of regulation rather
than code. Attestations from organizations (employers, clubs, landlords) are
not affected by this.

## Step 5: eID and EU wallet as a source

The ID card is not stored in the vault as an image. A scan proves nothing, as
it is easily altered, and German law restricts copies of the ID card. What
carries weight is the data signed by the card's chip, read through the eID
function, or the identity data held in the state wallet.

Revoked does not compete with the state wallet in proving who someone is.
Instead, an attester (step 3) reads the eID or the wallet once and issues an
attestation bound to the person's Revoked identity. Access to eID data
requires an authorization certificate from the responsible state body, or a
partnership with a provider that already holds one. That is organizational and
legal work, not code.

## Order

| Order | Step | Reason |
|---|---|---|
| 1 | Cross-server grants and grant events | Makes the live-data layer usable beyond one instance; every later step builds on grants. |
| 2 | OpenID Connect provider | Sign-in for services such as games and tools, using the existing passkey flow. |
| 3 | Attestations in SD-JWT format | Confirmed facts, with the DNS anchor as the distinguishing trust model. Implemented. |
| 4 | OpenID4VCI and OpenID4VP | Interoperability with wallets and verifiers outside Revoked. |
| 5 | eID through attesters | Real-world identity, once the earlier steps carry it. |
