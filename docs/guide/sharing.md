# Sharing

A share turns records into a link — `/s/{slug}` — that resolves their
**current** values every time it is read. Nothing is copied: rotate a secret
and every share of it updates; revoke the share and the next read is refused.

## Creating a share

Pick records (or whole [sections](vault.md#sections)) and *Share*. The create
sheet groups its options:

**Access** — the gates, freely combinable:

| Gate | Effect |
|---|---|
| Password | The viewer must enter it before anything resolves. |
| Max views | The share revokes itself after that many reveals. Counting is atomic — concurrent readers cannot slip past the cap together. |
| Expiry | The share flips to `expired` at that moment. |

**Verification** — who is involved:

- **Attach your identity**, so recipients can verify against your domain's
  DNS that the share really came from you. See
  [Identities & trust](identities.md).
- **Require a verified viewer** — the viewer must prove possession of their
  own cryptographic identity in a challenge handshake before the data
  resolves.

Every create sheet also shows a ready-to-run **API preview** of the exact
request it is about to make — the fastest way to learn the
[HTTP API](../api/index.md).

## The share's life

| Status | Meaning |
|---|---|
| `active` | Resolves normally. |
| `paused` | Temporarily refuses — flip back to active any time. |
| `revoked` | Permanently stopped, by you or by hitting the view cap. |
| `expired` | The expiry date passed. |

Pausing is the reversible "hold on"; revoking is final. A share can also be
duplicated — same records, fresh slug, fresh counters.

The badges on a share card tell you at a glance what shape it has: a
password, a handshake requirement, or that it came out of a
[request](requests.md) rather than being authored by hand.

## What the recipient sees

A share travels as a `revoked://` deep link (and as a QR code carrying the
web URL, so a phone camera works without the app installed).

- **In the app**: the link opens directly on the share, with the sender's
  verification verdict shown before anything else.
- **In a browser**: `/s/{slug}` serves a self-contained page — no CDN, no
  analytics. Nothing is fetched until the viewer presses **Load & Show**, so
  merely opening the page never spends a view. The page carries its own trust
  panel that checks the sender's DNS record from the browser, and a hand-off
  button to open the share in the app.

## Feeding other tools

*Web & API access* on a share offers its data in formats existing tools
consume directly, resolving live on every fetch:

| Format | Use |
|---|---|
| CSV | Spreadsheets — including a ready `=IMPORTDATA(…)` formula for Google Sheets. |
| vCard (`.vcf`) | One-off contact import. |
| CardDAV | A live-syncing contacts account: the address book follows the vault. Offered only on shares without a password — CardDAV cannot carry one. |
| iCalendar (`.ics`) / `webcal://` | Calendar import or a live subscription. |
| cURL | A copy-paste command for scripts. |

Responses carry ETags, so a polling consumer sees `304 Not Modified` until a
value actually changes.
