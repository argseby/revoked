# Requests

A request is sharing in reverse: a public form at `/r/{slug}` that asks other
people for data. What comes back lands in **Data**, structured the way you
asked for it — and when a responder answers from their own vault, what you
receive is a living grant they can revoke, not a copy they lost control of.

## Creating a request

A request is shaped by a [template](templates.md): the template's fields are
what responders are asked to fill in. The create sheet adds:

**Who can respond**

- **Require a verified identity** — responders must be signed in and prove a
  cryptographic identity before submitting. With it on, you can accept any
  identity or only those issued by your own server.
- **Identifier** — a value you communicate out-of-band (a customer number, a
  case id) that the responder must enter. It ties an anonymous submission to
  someone you already know.
- **Password** — the bluntest gate, shared out-of-band.

**Limits & callback**

- **Max responses** and **expiry** close the request automatically.
- **Allow extra fields** lets responders add ad-hoc fields beyond the
  template.
- A **callback URL** POSTs every submission to your own system — see
  [Callbacks](../api/callbacks.md).

## Responding

A signed-in responder can answer each field either by **linking a record from
their own vault** or by typing a literal value. A linked answer is the
important one: it stays theirs. It resolves their current value at read time,
and they can withdraw it later — the same revocable grant a
[share](sharing.md) is, pointing the other way.

Before anything is submitted, the app verifies the requester's domain. A
spoofed request — one whose cryptographic claim contradicts DNS — is a hard
block; an unverified one needs an explicit confirmation. Submitting again
later updates the same response rather than creating a second one.

## Reading what came back

The **Data** tab collects responses across all requests; each request also
has its own view, as a list or pivoted into a **sheet** — responders as rows,
requested fields as columns.

Each answer shows whether it is a typed value or a living grant, and whether
that grant is still resolving or has been revoked by the responder. Answers
you want to keep can be opened into your vault. Revoking the request itself
stops further submissions.

You are notified when a response arrives, when the request completes (max
responses reached) or expires, and when a callback delivery fails.
