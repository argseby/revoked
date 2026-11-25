# Counterparty flows in the browser — design

**Status: phases 1–4 built 2026-11-25, except attestations in the browser
(§4.8).** Phases are in §8 and open questions in §10. Where this document and the code disagree, the code is
right and this document is out of date.

"Counterparty" means anyone who acts on something an owner sent: answering a
request, opening a share, approving a connection or a sign-in for a service.
"Owner" means the person whose vault holds the data.

---

## 1. Summary

Every flow needs the installed app today. That includes the people who never
chose revoked: the parent answering a club's request, or the organizer opening a
protected share. One person who won't install an app leaves a flow incomplete.
This is the most frequent criticism of the product.

This design moves every counterparty flow into the browser, on the server's own
origin, and keeps the app as the stronger, optional path. It is not a rewrite.
The browser calls the same endpoints the app calls, the account requirement
stays, and the owner's vault stays in the app.

| Decision | Choice | Why |
|---|---|---|
| Who gets the browser | Counterparties: responders, share recipients, people approving a connection or a sign-in | They never chose revoked, so an install requirement stops them. Owners did choose it |
| Owner vault in the browser | No, not in this design | It would put full owner rights and identity keys in code the operator serves (§3.2) for the smallest gain |
| Answers without an account | No. Invariant 12 stays | A grant the responder cannot manage is a frozen snapshot. The browser makes the account cheap instead |
| Account | Created inside the flow: email and a passkey on the same page | One system prompt instead of an install. Passkey sign-up already runs in the browser (`GET /passkey`) |
| Browser session | One passkey ceremony per flow. The token stays in page memory and is never stored | A stored token in a browser is the easiest thing in this design to steal |
| Approving a connection or sign-in | A user-verified passkey assertion bound to that approval (§4.5) | A sign-in approval needs an identity-key signature, which a browser cannot make in phases 1–3. A connection needs only the session today (§10.3) |
| Trust check | The page shows the domain and never shows "verified" | A page served by the server being checked cannot vouch for that server (§3.1) |
| Sealed values, identity proofs, attestations | Later, through keys derived from the passkey (phase 4) | They need a private key, and the PRF extension does not work with every authenticator |
| Where the pages live | On the API's own origin | WebAuthn binds a passkey to `RPOrigins`, which is the server's origin |
| Flutter web | No | It would mean replacing secure storage, the `dart:io` paths and `local_auth`, and the result is the owner app in a browser |
| The app | Remains. It is offered as the stronger path, never required of a counterparty | It checks the server independently, and it is the only client that holds sealed keys at full strength |

---

## 2. Goals and non-goals

**Goals**

1. A counterparty can complete each flow in §4 in a browser, with no install.
2. Invariants 8, 12 and 13 hold unchanged.
3. The browser and the app share one endpoint per action, so nothing is enforced
   only by one client.
4. No new credential type. The browser holds an ordinary `users` session for
   the length of one flow.
5. A counterparty can update, pause and revoke what they gave without the app
   (§4.3). Without that, the browser path would produce frozen snapshots.

**Non-goals**

- The owner's vault, sections, templates, members or settings in a browser.
- Anonymous or guest submissions.
- Making the browser as strong as the app. The difference is stated in the
  product (§6), not hidden.
- Universal links or App Links. A self-hosted domain cannot vouch for one app
  binary, so the `revoked://` scheme stays the way into the app.

---

## 3. What the browser costs and gains

### 3.1 The trust verdict is self-reported

The app checks a server's DNS pin, root key and identity status on its own
before a person types anything (`DomainVerificationService`). In a browser, the
page doing that check is served by the server being checked. A phishing server
serves a page that says whatever it likes. A green tick on a browser page is
therefore worth nothing against exactly the attacker the product is sold on
catching.

Consequences:

- A browser page never shows a trust verdict as "verified". It shows the domain
  as the address bar shows it, and the requester's name as the server reports it.
- The share page does not follow this yet: it checks the DNS pin from page
  script and shows "`<domain>` verified". That line has to change to match.
- The share page already has a pin that is remembered per browser ("trusted in
  this browser", `revoked_trusted_domains` in `localStorage`). The request page
  uses the same pin. A changed pin for a domain this browser remembered is shown
  as a warning, because that check does not depend on the current page's honesty
  about the past.
- The app link stays on every page, described as the path that checks the
  server first.

### 3.2 The operator serves the code

A browser runs whatever script the server sends on each load. For unsealed
records this costs nothing new, because the server already holds those values
in plaintext. It matters for anything a private key protects: sealed values,
identity signatures and attestation proofs.

The passkey page already accepts this cost once. `passkeyPage.go` reads the PRF
output (E2EE.md §6.8) in page script before handing it to the app. A dishonest
operator could change that script today. Phase 4 extends the same trust to
identity keys, and must be labelled the same way as E2EE.md labels the browser
share page.

### 3.3 What the browser gains

- **Passkeys cannot be phished.** A lookalike domain gets no assertion for the
  real server's credential, so a copied page collects nothing it can use. This
  covers most of what "no web page for a phisher to imitate" protected.
- **One tab from start to finish.** The app returns through the system browser,
  which has to be the browser the flow started in (sign-in.md, *Approving in the
  app*). A browser flow ends in the tab it started in.
- **The request survives sign-in.** TODO APP-26 (the sign-in gate loses the
  request) goes away, since sign-in happens on the request page itself.

### 3.4 Session handling

- The page creates a PKCE pair, runs the passkey ceremony and redeems the code
  at `POST /api/passkeys/token`, exactly as the app does. The token lives in a
  variable for the page's lifetime. It is never written to `localStorage`,
  `sessionStorage` or a cookie.
- Pages use the existing `pageCSP` approach: no third-party origin, inline script
  only under the page's nonce.
- An account with an authenticator app answers `two_factor_required`. The page
  finishes at `POST /api/passkeys/token/2fa`, as the app does.

---

## 4. Flows

### 4.1 Signing in or creating an account inside a flow

Endpoints in use today, unchanged:

```text
POST /api/passkeys/login/begin      {challenge}
POST /api/passkeys/login/finish     {session, credential}  -> {code}
POST /api/passkeys/register/email   {email}                (SIGNUP_VERIFY_EMAIL only)
POST /api/passkeys/register/verify  {email, code}          -> {proof}
POST /api/passkeys/register/begin   {email, proof?, challenge}
POST /api/passkeys/register/finish  {session, credential}  -> {code}
POST /api/passkeys/token            {code, verifier}       -> session
```

The ceremony code lives in `passkeyCeremony.go`, which `passkeyPage.go` and
the flow pages include, so there is one implementation of it. Signup makes no
workspace: the app's first run asks for one. The request page does the same
before answering (a workspace named "Personal", made active), since an answer
from an account without one holds no records of its own.

### 4.2 Answering a request

There is no browser page for a request today: `/r/{slug}` exists only as
`revoked://r/…`. The new page is `GET /r/{slug}` with `Accept: text/html`.

1. The page probes `GET /api/public/requests/{slug}` (public; it now also
   reports `expiresAt`) and shows the requester, the domain, the template's
   fields and the expiry.
2. A signed-out reader signs in or creates an account in place (§4.1).
3. Once signed in, the page fills fields from the responder's own vault where
   keys match, using the session. A filled field is shown as coming from the
   vault, and that answer is a mapping to the record (a living grant). A field
   typed in becomes a new record in the responder's vault, which the server
   already creates when it materializes an answer.
4. Submission is `POST /api/public/requests/{slug}` with the session. The gate
   order stays as it is (account, then password, then identifier).
5. The page ends on what was given, with links to §4.3.

A request with `requireHandshake` (with or without `identityScope`) or a
required file field cannot be answered in phases 1–3. Requests have no sealed
flag; a sealed vault record is never offered as a prefill. The page states that the app is required and offers the
app link. Phase 4 lifts this.

### 4.3 Managing answers

Invariant 12 only holds if the responder can actually manage the answer. A new
page, `GET /answers`, signs in (§4.1) and lists the links the responder's
workspace holds that answer requests. Each one shows the requester, what it
grants, its status and its expiry, with **Pause**, **Revoke** and editing of
the values it grants. It uses the existing collection endpoints and rules. No
new access path is added.

The page at the end of §4.2 links to it, and so does every notification about
an answer.

### 4.4 Password-protected shares

Today `/s/{slug}` in a browser refuses a password-protected link and points to
the app (`gate.password`). The page instead shows a password field and posts
to `POST /api/public/links/{slug}`, the endpoint the app uses, with its existing
rate limit. A wrong password is answered as today, and the field stays for
another try. The page never opens a password-protected share by itself, even
for a remembered domain.

This gives up the old rule that the share page collects nothing. Passkeys
(§3.3) do not cover it: a share password typed into a lookalike page is
captured. What remains is the address bar, the remembered pin (§3.1) and the
app link beside the field.

Shares that require a verified identity (`requireHandshake`) and sealed shares
stay with the app until phase 4.

### 4.5 Approval proof

Approving a sign-in in the app needs an identity-key signature over the ticket
(`verifyOIDCApproval`), so a session token alone approves nothing. A browser
holds no identity key in phases 1–3. It proves approval with a passkey
assertion instead:

```text
POST /api/approvals/begin   {purpose, ticket}       -> WebAuthn request options
POST /api/approvals/finish  {session, credential}   -> {approval}
```

- The challenge is `SHA-256("revoked-approval-v1" ‖ purpose ‖ ticket ‖ nonce)`.
  `purpose` is `connect` or `signin`. The prefix and the purpose keep the
  assertion from being reused as a sign-in or as the other kind of approval,
  for the same reason invariant 11 prefixes the status payload.
- `userVerification` is `required`. An assertion without the UV flag is refused.
- The credential must belong to the signed-in user. `approval` is valid once,
  for that ticket only, for two minutes.
- `/oidc/authorize/consent` accepts `approval` as an alternative to
  `identityId` and `signature`. Nothing else accepts it. A `connect`
  approval can be made but nothing checks one: `/api/connections/authorize`
  takes the session alone from both clients until §10.3 is decided, so the
  connect page asks for no second passkey.

The approval registry joins the in-process registries listed under CLAUDE.md
*Gotchas*.

### 4.6 Approving a connection

`revoked://connect?…` gets an `https://<server>/connect?…` equivalent with the
same parameters and the same validation (tools.md §1; `parseConnectLink`
mirrors the app's `ConnectRequest.fromQuery`). A link with `poll` is accepted,
and the page answers through `redirect` anyway. The page shows what the
app's connect screen shows: the tool's origin, name, permissions, reach and
reasons. It signs in (§4.1), takes an approval (§4.5) and posts to
`POST /api/connections/authorize`. It then sends the same tab to `redirect`
with `state`, `status`, `server` and `code`.

Unchanged rules: the whole vault and `requests:manage` only through the return
address, never with `poll`. In a browser the return address is the same tab,
so the reason for that rule still applies.

A tool that does not know the person's server shows a field for the server
address next to its "Open the app" button. The tool remembers the address for
that person.

### 4.7 Approving Sign in with Revoked

`GET /oidc/authorize` renders the browser consent page: the service, the
account, the scopes, the name and any vault entries asked for, as the app
shows them. Approval uses §4.5, so the person is asked for a passkey twice:
once to sign in, once to approve. The page no longer opens the app by itself
(§6.1); its **Open in the Revoked app** button carries the same
`revoked://signin` link. Entries that do not exist yet cannot be created
from the browser page.

`revoked_identity` stands for a key on the person's device, so it is shown as
unavailable in the browser and the server leaves it out of any approval made
by passkey, whether or not the account has an identity. Services handle that already, because a person can decline any scope
except `openid`.

The `revoked://signin` button, which works without knowing the server, keeps
working for people with the app. A service adds the same server-address field
as in §4.6 for people without it.

### 4.8 Phase 4: keys derived from the passkey

A passkey with the PRF extension gives the same 32 bytes on every device it is
synced to. The page asks for the PRF output of the input
`revoked-passkey-identity-prf-v1`, separate from the one the sealed keys use
(`revoked-sealed-prf-v1`, E2EE.md §6.8), so the identity never shares a secret
with them. HKDF-SHA256 (empty salt, info `revoked-passkey-identity-v1`)
expands it to 48 bytes, which are reduced into [1, n−1] for the P-256 private
key. Its public key is registered as an identity of kind `passkey`, certified
like any other; the first identity of an account is made its primary one. The
private key is computed for each visit, held as a non-extractable WebCrypto
key, and never stored or uploaded, so invariant 8 holds in its wording. Its
strength is that of the page that computes it (§3.2).

The script is `passkeyIdentity.go`. `TestPasskeyIdentityMatchesTheReference`
runs it under Node against a Go derivation of the same key and checks the
page's signatures with the server's own verifier. The browser computes the
public key by importing a PKCS#8 key without its public half. That works in
Chromium and Node; Firefox and Safari are untested, and where the import
fails the page says the browser cannot derive an identity.

A PRF output is per passkey, so two passkeys that are not synced give two
identities. The sign-in assertion carries the PRF request when the flow will
sign, so the person is asked once; a passkey that was just created asks again,
since creation returns no PRF output on most platforms.

What it unlocks, in the browser:

- Requests that require a verified identity, on `/r/{slug}`.
- Shares that require one, on `/s/{slug}/identity`, linked from the share page.
  The handshake token is not kept. This needed a server fix: a link handshake
  made once demanded its token and refused a fresh signature, which also
  locked out an app that lost its token. It now accepts a fresh signature, as
  the request gate already did.
- The `revoked_identity` claim: the consent page signs
  `revoked-oidc-consent:<ticket>` with the passkey identity, as the app does.
  The claim names the account's primary identity, as it does for the app.

Not unlocked:

- Accepting and presenting attestations. They are a separate set of screens
  with their own server flow, and are not built for the browser.
- Sealed links needed nothing here: the share page already opens them from
  the `#k=` fragment.

PRF support differs between authenticators and platforms. Where the extension
returns nothing, these flows keep pointing to the app.

---

## 5. Server changes

| Change | Phase |
|---|---|
| Shared passkey ceremony script, included by every flow page | 1 |
| `GET /r/{slug}` HTML page (§4.2) | 1 |
| `GET /answers` page (§4.3) | 1 |
| Password field on `/s/{slug}` (§4.4) | 2 |
| `POST /api/approvals/begin`, `/finish`, and the in-process approval registry (§4.5) | 3 |
| `approval` accepted by `/api/connections/authorize` and `/oidc/authorize/consent` | 3 |
| `GET /connect` page (§4.6), browser consent on `/oidc/authorize` (§4.7) | 3 |
| Identity of kind `passkey`, derivation and registration (§4.8) | 4 |

No schema change is needed for phases 1–3. Every page is server-rendered like
`/s/{slug}` and `/passkey`, which keeps it on the API's origin with its existing
CSP.

---

## 6. App and copy

### 6.1 Handing over to the app

- The share and request sheets copy the `https://` link by default. The
  `revoked://` link stays available under the same menu.
- An `https://` link always opens the browser first, whether or not the app is
  installed. The server answers with the page for that link.
- The page carries an **Open in app** control that points to the matching
  `revoked://` link, as `/s/{slug}` does today. With the app installed, the
  system asks to open it, and the app shows its own screen for the same link
  after its own server check. Without the app, the flow continues on the page.
- The page never switches to the app on its own. A page cannot detect an
  installed app, and a `revoked://` link without one leads to an error in some
  browsers ("address invalid" in Safari) and to nothing in others.
- Universal Links and App Links stay out of scope (§2). They require each
  domain to vouch for one app binary, which a self-hosted server cannot do for
  every build.
- A person may choose **Always open in app** on a page. The choice is
  remembered in that browser's `localStorage`, per server domain, and later
  pages for that domain open the `revoked://` link directly. It can be undone
  on any page, like the remembered pin (§3.1).
- An account is the same in both. The app creates its passkey on the server's
  own `/passkey` page, so the passkey belongs to the server's origin and works
  on every browser page of that server. What is answered in the browser shows
  in the app's vault, and the other way round.

### 6.2 Buttons on a service

A service that offers Sign in with Revoked or a connection shows two controls:

| Control | Opens | For |
|---|---|---|
| **Open the app** | `revoked://signin` or `revoked://connect`, as today | People with the app. The app knows its server |
| **Continue in browser** | A field for the server address, then `https://<server>/oidc/authorize` or `https://<server>/connect` (§4.6, §4.7) | People without the app |

The service remembers the server address for that person, so the field is
asked once.

### 6.3 Copy

- No browser page uses the words "verified" or "trusted" for the current server.
  The one exception is the remembered pin (§3.1), which describes a fact about
  this browser.
- All copy follows CLAUDE.md *Copy*, and new strings exist in English and German
  like the share page.

---

## 7. Rules and invariants affected

| Rule | Change |
|---|---|
| CLAUDE.md: "Deep links are custom-scheme only (`revoked://`), deliberately: there is no web page for a phisher to imitate." | Replaced when phase 1 lands. The `https://` page is the default way in, passkeys protect the credential, and the page never reports a trust verdict (§3.1) |
| CLAUDE.md, Web: "No private key ever reaches the web client" | Unchanged until phase 4, then narrowed to: no stored private key, only one derived per ceremony from a passkey |
| Invariants 8, 12, 13 | Unchanged |
| New: a browser session token is never persisted | Proposed invariant, with a test that greps the page sources for storage calls holding it |
| New: an approval proof is bound to one ticket and one purpose under a domain-separated prefix | Proposed invariant, with a test that replays an approval across purposes and tickets |

---

## 8. Phases

1. **Answering requests in the browser,** with the account made inside the flow,
   and the `/answers` page. Covers parents in the club scenario.
2. **Password-protected shares in the browser.** Covers the organizer for
   password-protected links.
3. **Approving connections and sign-ins in the browser.** Covers services built
   on revoked without asking their users for an install.
4. **Keys derived from the passkey.** Identity-gated shares and requests,
   attestations, the `revoked_identity` claim, sealed links.

Each phase ships on its own. Phases 1 and 2 bring the most benefit for the
least risk.

---

## 9. The club scenario after each phase

| Step | Party | After phase |
|---|---|---|
| Season request answered | Parents | 1 |
| Answers updated or withdrawn mid-season | Parents | 1 |
| Club creates the request and reads answers | Club (API key, webhooks) | Already possible |
| Weekend links opened, password-protected | Organizer | 2 |
| Weekend links opened, identity-protected | Organizer | 4 |
| Core connected to a club or coach | Club, coach | 3 |
| Coach presents credentials | Coach | 4 |
| Links and check results stored, webhooks | Core | Already possible |

The weekend emergency-contact link has a gap no phase here closes: nothing lets
the club pass parents' answers on as a new, time-limited link. That is a
separate design.

---

## 10. Open decisions

1. **Server-rendered pages or the Svelte web client.** This design picks
   server-rendered pages, because they share the origin and CSP of `/s/{slug}`.
   The Svelte client would work too, provided it is served from the API's
   origin.
2. **One ceremony per flow, or a browser session that lasts.** A lasting session
   makes `/answers` more convenient and needs a cookie with its own CSRF
   protection. This design starts without one.
3. **Requiring an approval proof in the app for connections.** The app approves
   a connection with its session alone. Making it send §4.5 or an identity
   signature as well would give both clients the same rule.
4. **Email for responders.** An operator may want accounts made in a request
   flow without an email address, recovered only by passkey. That is a signup
   policy change and not part of this design.
5. **How a service finds the server without the app.** A server-address field is
   the minimum. A lookup from the email domain is possible later.
