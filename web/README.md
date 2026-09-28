# Mietunterlagen provided by Revoked

A small browser client for one job: applying for flats. You keep your
documents in revoked once, black out what a landlord doesn't need, and send
each listing its own link. Every file the landlord opens is stamped
*"Nur für Wohnungsbewerbung Musterstr. 5 · 2026-09-28 · #a3f9c1"*. The link
expires on its own, you can revoke it, and you see when it was opened.

It is static files — Svelte 5 + Vite, ~65 KB of gzipped JavaScript — that talk
to an existing revoked server. pdf.js (for redacting PDFs) is loaded only the
first time someone opens a PDF in the redactor. English and German; the
browser's language picks one, the **DE/EN** button switches. The landlord
needs nothing but the server's normal share page (`/s/{slug}`).

## What it does

| Screen | |
|---|---|
| **Applications** | One card per link: *Opened N×*, expiry, stamp tag, status. Copy link, QR, **Preview** (each file exactly as the landlord gets it, stamped by the server), **Download (.zip)** of all stamped files, +14 days, revoke, delete. **New application** asks for the address, the documents and details to include, and 7/14/30 days, with a stamp preview before the link exists (marked `#preview`). |
| **Documents** | Slots from the built-in *Tenant application* template (ID, proof of income, credit report, rent debt clearance) plus any extra documents. Upload by button or drag-and-drop (onto a slot, or anywhere on the page for several files at once); replace, view, redact, delete. |
| **About you** | The applicant card the landlord sees (name, email, income, move-in date, …), stored as vault records under the template's keys, plus **own fields** of type text, number, date or document (keys prefixed `profile_`). |

New records are filed under the vault section **`mietunterlagen`** (created on
first use), so they appear grouped in the app. Existing records are used where
their key matches and are left where they are. When a save creates a record and
applications are still open, the tool asks whether to add it to them — links
grant explicit records, so nothing reaches a landlord without that yes.

The landlord's page offers **Download all (.zip)** with every file stamped.

### Redaction

An image or a PDF can be redacted **before it is uploaded**: drag black boxes
over the numbers, move or resize them, then *Use redacted copy*. On a PDF,
**Find text to black out** searches the text layer on every page and shows the
matches before covering them (an IBAN, a tax ID, a name). A redacted PDF is
rebuilt from page images, so no text, hidden layer or object survives under a
box — the trade-off is that its text can no longer be selected.

An image becomes a new PNG drawn from the decoded pixels plus opaque black
boxes — no layers, no EXIF or GPS. Either way the exported file is decoded
again and every box checked before it replaces the staged original, and the
original is never sent. A file already on the server can be replaced by a
redacted copy the same way (the unredacted file is deleted from the server).

Browsers with canvas fingerprinting protection (Firefox *resistFingerprinting*,
Brave's strict mode) randomise pixel reads, so the check fails there and the
editor refuses rather than guessing.

Redaction presets (e.g. German ID card) are wired up in
`src/lib/redaction/presets.ts` but ship empty until measured on real card
photos.

### What stays in the app

The web client never holds a private key (see `../web.md`). It can attach your
existing primary identity to a link, but creating an identity — and creating
the account's first workspace, which sets one up — happens in the app. An
account without a workspace sees a screen saying so.

## Develop

```bash
npm install
npm run dev          # http://localhost:5173, proxies /api and /s/ to :3000
```

The sign-in dialog defaults to `https://api.revoked.link`. To use your local
server, choose **Change** and enter `http://localhost:5173` (the proxy); it is
remembered after the first successful sign-in. Point the proxy elsewhere with
`REVOKED_DEV_API=http://127.0.0.1:3100 npm run dev`.

```bash
npm run check        # svelte-check, warnings fail
npm test             # vitest: geometry, verification, link spec, template keys
npm run build        # dist/
```

## Deploy

The image serves `dist/` on port 8080 and writes its settings into
`/config.json` and the Content-Security-Policy at start-up:

```bash
docker compose --profile web up -d    # from the repo root
```

| Variable | Default | |
|---|---|---|
| `REVOKED_SERVER` | `https://api.revoked.link` (compose: `https://$DOMAIN`) | The server the sign-in dialog uses by default. |
| `REVOKED_CUSTOM_SERVERS` | `true` | Users may pick another server under **Change**. The CSP then has to allow any `https:` origin; `false` pins the page to `REVOKED_SERVER` alone. |

Put the container on its own host name behind your reverse proxy (for example
`apply.example.com`). PocketBase allows cross-origin requests by default; if you
restricted `--origins`, add this host.

The link a landlord receives is built from the server's advertised domain
(`GET /api/server`), not from where this client is hosted. A server on
`localhost` or a LAN name produces links nobody outside can open, and the
client says so when it creates one.
