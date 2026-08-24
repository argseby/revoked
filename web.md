# Web version — build plan

A browser build of the Flutter client, served by the same server that runs the
API, at `web.<your-domain>`. Not written yet; this is the plan.

Read this with [CLAUDE.md](CLAUDE.md) (the standing rules) and
[ARCHITECTURE.md](ARCHITECTURE.md) (how the system is built).

---

## What it is for

Deciding this first changes everything downstream, because there are two
different products hiding behind "web version":

1. **Recipients read a share without installing anything.** Already shipped —
   `GET /s/{slug}` renders a read-only page. No login, no Flutter, nothing to
   build.
2. **Members use their workspace from any machine.** Needs a login, and that is
   where all the risk and all the work is.

This document is about (2).

---

## The one real limitation

Everything else follows from it, so it is worth stating precisely.

Your data already lives on the server. If someone breaks into it, they have
your data — bad, but bounded.

Your identity key is different. It never leaves your device, which is what
stops an attacker who owns the server from **signing as you** — from minting
new shares and requests that other people would see as provably from you. The
key is what keeps a break-in from spreading to everyone you deal with.

The app can hold that line: it was installed once, it holds the key locally,
and the server cannot change its code. A browser cannot: the server ships fresh
JavaScript on every visit, so any code that touches the key is code the server
just handed you. The key's only job is to protect you from your own server, and
in a browser the server is holding the key.

**So: no key on the web. No signing on the web.**

### What that actually costs

Less than it sounds. The private key is used in exactly two places in the whole
client:

| Where | What it does |
|---|---|
| `identities_store.dart` | Generates a keypair when you create an identity |
| `handshake_service.dart` | Signs a challenge when *opening* a handshake-gated link |

Creating a **signed share does not touch the key**. `createShare(identityId:…)`
sets a relation; the identity's certificate was signed by the server's root key
when the identity was created, and the reader verifies that chain
independently.

So the web build keeps the whole core product, provenance included.

### The framing for users

> Set up your identity once in the app. After that, work from anywhere.

Familiar from hardware keys and authenticator apps: one-time setup on a trusted
device, everyday use anywhere. Not a crippled web version — a normal split.

---

## What works, what does not

**Works:** vault records and sections, files (upload and download), shares
(including **signed** ones), requests, workspaces, members and invites, API
keys, audit log, settings, viewing an ungated link from any server.

**Does not:**

| Blocked | Why |
|---|---|
| Creating an identity | Generates a private key |
| Importing an existing key | Same |
| Opening a handshake-gated link | Answering the challenge needs a signature |
| Handling `revoked://` links | Browsers do not own custom schemes — offer the link, do not consume it |

Note the *consequences* are consequences, not separate rules. Explain the key
once; the rest follows.

### DNS verification: keep it, label it

Keep the DNS check on the web. Checking a **third party's** domain from your own
server's code is not circular — the verifier and the verified are independent —
and it is genuinely useful when you open someone else's link.

What it cannot do is defend you against *your own* server lying to you. So a
green check in the browser means less than a green check in the app. Say so in
the UI; do not remove the feature.

(This is distinct from the public share page at `/s/{slug}`, where the DNS check
*is* circular — that page is served by the sender's server to a recipient who
has no relationship with it. That page already says "open in the app for full
verification". Keep that wording.)

---

## Required steps

### 1. Enable the platform

```bash
cd app && flutter create --platforms=web .
```

There is no `app/web/` directory today. Review the generated `index.html` and
`manifest.json` rather than shipping the defaults.

### 2. Remove `dart:io` from the shared path

`dart:io` does not compile for web. Five files import it, and every use is
trivial — four are only `Platform.isX` for platform detection, two also use
`File()`:

- `core/widgets/qr_sheet.dart` — `Platform.isAndroid/isIOS`
- `core/widgets/share_sheet.dart` — `Platform.isAndroid/isIOS`
- `core/files/file_saver.dart` — `Platform.isAndroid/isIOS`, `File()`
- `features/shell/view/link_search_sheet.dart` — `Platform.isAndroid/isIOS`
- `features/vault/view/record_create_sheet.dart` — desktop checks, `File()`

Put one shim in `core/platform/` exposing `isMobile` / `isDesktop` /
`canDropFiles`, with a conditional import (`dart:io` vs a web stub), and route
all five through it. One place to be wrong instead of five.

`file_saver.dart` needs a web branch that triggers a browser download rather
than writing a `File`.

There are currently **zero unguarded `Platform.is*` calls** — everything is
already behind `kIsWeb`. Keep it that way; a guard test would be cheap.

### 3. Audit the plugins

| Package | Web | Note |
|---|---|---|
| `pointycastle` | ✅ | Pure Dart, no change |
| `file_picker` | ✅ | Returns bytes, which is what the upload path wants |
| `mobile_scanner` | ⚠️ | Works, needs HTTPS + camera permission |
| `share_plus` | ⚠️ | Falls back to the Web Share API; verify, else copy-to-clipboard |
| `app_links` | ❌ | Custom schemes are meaningless in a browser — exclude |
| `flutter_secure_storage` | ⚠️ | **Decide deliberately.** Its web backend is browser storage, which is not a keychain |

### 4. Session storage

`flutter_secure_storage` on web is not a keychain. A session token in browser
storage on a shared machine is a real exposure.

Decide: short-lived session, no "remember me", and prefer `sessionStorage`
semantics so closing the tab ends it. Since the key never lives here, the token
is the only credential to protect — worth getting right.

### 5. The capability gate

One place that answers "is this allowed here", so restrictions are enforced in
code rather than by remembering to hide buttons:

```dart
// core/platform/capabilities.dart
abstract final class Caps {
  static bool get canSign => !kIsWeb;
  static bool get canCreateIdentity => !kIsWeb;
  static bool get canOpenGatedLinks => !kIsWeb;
}
```

Every blocked action checks `Caps`, and shows the *reason* plus a link to the
app — never a dead or missing button. A guard test asserting that no signing
path is reachable without a `Caps` check would keep this honest.

### 6. Serving

Embed the build in the Go binary. One artifact, one image, nothing to keep in
sync:

```go
//go:embed all:webdist
var webAssets embed.FS
```

PocketBase already provides `apis.Static(fsys, indexFallback)` — use it with
`indexFallback: true` so client-side routes resolve.

**Serve it on a separate origin** (`web.<domain>`), not a path on the API
origin. The public share page renders attacker-controlled values on the API
origin; same-origin, an XSS there would reach the app's session. Different
origins keeps that isolated.

Cost of that choice: the API needs CORS for the web origin, and `web.<domain>`
needs its own TLS certificate.

### 7. CSP

The app origin needs its own policy — the page CSP in `publicPage.go` is for the
share page and does not apply. Flutter web needs `wasm-unsafe-eval`. Allow the
API origin and the two DoH resolvers in `connect-src`; nothing else.

### 8. Build and deploy

- **Dockerfile**: add a Flutter stage that runs `flutter build web --release`
  before the Go build, and copy `build/web` in so `go:embed` picks it up.
  Remember `dart run build_runner build` first — `.g.dart` is gitignored.
- **compose**: gate on env so operators who do not want a web surface do not
  get one. `WEB_ENABLED=false` by default, plus `WEB_DOMAIN`.
- **CI**: add the web build to the existing app-build workflow.

### 9. Docs

A page under `docs/app/` covering the setup, the limitation, and how to point
DNS at `web.<domain>`.

---

## What will not happen

Stated plainly so nobody is surprised later:

- **No identity is ever created in a browser.** No keypair generation, no key
  import, no "just this once".
- **Nothing is signed in a browser.** No challenge responses, no handshake, no
  identity-proven submissions.
- **Handshake-gated links stay app-only**, both shares and requests.
- **The web build does not become the primary download.** The app stays the
  recommended client; the web version is for when you are not on your machine.
- **`revoked://` links are offered, never handled** — a browser cannot own the
  scheme.
- **The public share page does not change.** It stays login-free, read-only,
  input-free, and claim-on-reveal.

---

## Open decisions

1. **Is it opt-in for operators?** Recommendation: yes, default off. Not every
   operator wants a login form on the public internet.
2. **Session lifetime on web** — see step 4.
3. **API keys on web?** Allow, probably: a copy-once credential is no more
   exposed here than anywhere else. Judgment call.
4. **Web-only users produce unsigned shares.** Someone who never opens the app
   never creates an identity, so their shares show the red "Not signed" state to
   recipients. Make identity setup part of onboarding, and have the web app say
   so plainly rather than silently producing weaker shares.

---

## Risks worth naming

**A login form is the most clonable artifact in the product.** CLAUDE.md notes
that deep links are custom-scheme "deliberately: there is no web page for a
phisher to imitate". A predictable `web.<domain>` login page hands phishers
exactly that template. The read-only share page is safe because it collects
nothing; a credential form is categorically different. This does not block the
work, but it is the argument for keeping it opt-in, and for keeping the app the
prominent path.

**The web build widens the XSS blast radius.** In the app, a rendering bug is
contained. In a browser, an XSS on the app origin reaches the session token.
Separate origins and a strict CSP are the mitigations; neither is optional.

---

## Later, not now

**WebCrypto non-extractable keys.** A key JavaScript can use but never read out
would close most of the exfiltration gap — though not the "server-supplied code
signs something while you are on the page" gap. It would mean moving the web
build off pointycastle. A real upgrade path, not a v1 concern.
