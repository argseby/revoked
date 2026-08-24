# Using the app

One Flutter client for desktop and Android —
[installation covered here](../installation/app.md). It talks to
`http://127.0.0.1:3000` by default — a server on the same machine. To use
any other server, open **server settings** on the login screen and enter its
address — it is tested and persisted before anything else happens.

## First start

Sign in, and if your account has no workspace yet, onboarding offers two
doors:

- **Create a workspace.** You name yourself for your signing identity here —
  that name is what recipients of your shares and requests will see.
- **Join one** by pasting an invite key someone sent you.

Everything you do lives in a workspace: the vault, shares, requests,
templates and identities are all scoped to it. See
[Workspaces & members](workspaces.md).

## Around the app

| Area | What it holds | Details |
|---|---|---|
| **Vault** | Your records and sections — the data everything else points at | [Vault](vault.md) |
| **Shares** | Links you issued, with their gates and view counts | [Sharing](sharing.md) |
| **Requests** | Forms you published to collect data from others | [Requests](requests.md) |
| **Data** | What people submitted, as a list or a spreadsheet | [Requests](requests.md#reading-what-came-back) |
| **Templates** | Blueprints for requests and for whole vault setups | [Templates](templates.md) |
| **Settings** | Identities, workspace members, API keys, domain verification | [Identities & trust](identities.md) |

## Opening links

Shares and requests travel as `revoked://` deep links — deliberately, so
there is no web page for a phisher to imitate. With the scheme registered,
clicking one opens the app directly on that share or request. Inside the app,
**Ctrl+V** with a link on the clipboard opens it too, and the *Open a link*
dialog can verify the sender against DNS before you open anything.

A notification bell in the shell collects what happened while you were away:
responses arriving, links expiring or hitting their view cap, invites being
accepted, callbacks failing.
