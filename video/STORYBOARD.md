# Storyboard — "How revoked works"

1920×1080, 30 fps, 2 min 25 s. Paper background `#FAF9F6`, ink `#16151F`,
indigo `#3D35B5` for everything that is a link or an action, green / amber / red
only for status. Cast: **Mia** (looking for a flat), a **landlord**, an
**employer**, a **tax advisor**.

Each claim is taken from the repo; the source is in brackets.

| # | Scene | On screen | Source |
|---|---|---|---|
| 1 | Intro (5 s) | The four-bar mark draws in, wordmark, "Share a reference, not a copy." | `docs/assets/brand`, `docs/index.md` |
| 2 | The problem (10 s) | Mia emails a payslip PDF; copies multiply at the landlord and can't be called back. | `docs/index.md` ("replaces stale copies") |
| 3 | Cast (7 s) | Mia in the middle, the three others around Mia. | — |
| 4 | Vault (13 s) | Mia's vault card: sections *Rental* and *Tax*, records `full_name`, `phone`, `iban` (hidden), `payslip.pdf` (file), `tax_id`. "Your vault lives on your server." | `docs/guide/vault.md` |
| 5 | Share (16 s) | Mia shares the *Rental* section. A link chip `/s/k7Qx…` travels to the landlord — not the data. The landlord opens it; a dotted "live read" line goes back into the vault. Badge row: password · view limit · expiry. "The slug is the key — long and unguessable." | `docs/guide/sharing.md`, CLAUDE.md inv. 2 |
| 6 | Live value (11.5 s) | Mia replaces `payslip.pdf` (September → October). The landlord's view flips to October on the next read. "No republish step." | `docs/guide/sharing.md`, `docs/guide/vault.md` |
| 7 | Revoke (15 s) | Two links from the same vault: landlord and tax advisor. Mia revokes the landlord's: pill goes active → revoked, the read line breaks, the landlord sees "This link was revoked". The tax advisor's link keeps resolving. Footer: Pause = reversible, Revoke = final. | `docs/guide/sharing.md` (life table), `routes/publicLinks.go` (410) |
| 8 | Request (24 s) | Employer sends a request form `/r/onboarding` (fields `tax_id`, `iban`). Mia's app checks the employer's domain first (verified via DNS). Mia signs in — an account is required, no anonymous answers. Mia answers from the vault; the answer is a link created **in Mia's workspace**; the employer reads through it live; Mia can update or revoke it. | `docs/guide/requests.md`, CLAUDE.md inv. 12, `routes/publicRequests.go` |
| 9 | Attestation (27 s) | Employer offers an attestation `employment` (claims `employed`, `permanent_contract`, `position`) to Mia's identity. Mia accepts by signing a challenge with the identity key — the key stays on the phone. Later the landlord's letting portal asks for `employed`; Mia ticks two claims and withholds `position`; the presentation is signed on Mia's device; the portal verifies against the employer's domain. The employer can revoke; verifiers learn within minutes. | `docs/guide/attestations.md`, `docs/api/attestations.md`, CLAUDE.md inv. 8 |
| 10 | The whole picture (15 s) | Mia + vault in the middle. Landlord: revoked share (grey). Tax advisor: active share. Employer: request answer (link in Mia's workspace) and attestation (to Mia's identity). Four-line legend. | all of the above |
| 11 | Outro (6 s) | Mark + "Self-hosted. Your domain, your keys, your data." | `docs/index.md` (no hosted instance) |

What the video deliberately does not claim: no anonymous answers, no copies held
by the recipient, no central authority, no private key on the server.
