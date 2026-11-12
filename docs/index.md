# Revoked

Access, not copies. Share what you have, request what you need, sign people
in and check who's asking. The data stays with its owner, who can end access
any time.

## Example: one address, several recipients

An address record contains `Musterstraße 12, Berlin`. A delivery service and a
club each receive a separate share of it. After a move, the owner changes the
record to `Hauptstraße 3, Köln`; both recipients read the new address through
their existing links. Revoking the club's share leaves the delivery service's
share working.

This controls future access. An address already copied into another system or
a document already downloaded cannot be recalled. Integrations read current
values again after the permitted cache period ends.

The same pattern also works in reverse: a [request](guide/requests.md) asks
someone else to share their information. [Sign in with Revoked](api/sign-in.md)
authenticates an account and can optionally ask for selected information at
the same time.

## Why a link beats a copy

- **Always up to date.** Change a password in your vault, and everyone you
  shared it with sees the new one. You never send it again.
- **Yours to take back.** Pause or revoke a link, and it stops working the
  next time someone opens it. Not at the next sync.
- **Proof of who sent it.** Shares and requests can carry the sender's
  identity, tied to their domain. When something says it comes from
  example.com, the app checks that it really does.

## Where to go

| You want to | Start at |
|---|---|
| See it working in 5 minutes | [Try it](try/index.md) |
| Learn each part by using it | [Labs](labs/index.md) |
| Understand how the parts fit together | [How it works](how-it-works/index.md) |
| Run your own server, or install the app | [Installation](installation/index.md) |
| Keep a vault, share secrets, collect data | [Guide](guide/index.md) |
| Write scripts or connect your own systems | [Developer API](api/index.md) |
| Let a tool ask for your data without ever holding it, such as an emergency card | [Tools & link proposals](guide/tools.md), [Notfallkarte](guide/notfallkarte.md) |

Run Revoked on your own server, and your data, your keys and your domain
all stay under your control. The app connects to whichever server you
choose.

Just want to try it? Use the official server, `api.revoked.link`. It's
experimental and for testing, with no guarantees for your data.
