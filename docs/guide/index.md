# Using the app

One Flutter client for desktop and Android —
[installation covered here](../installation/app.md). It talks to
`http://127.0.0.1:3000` by default — a server on the same machine. To use
any other server, open **server settings** on the login screen and enter its
address — it is tested and persisted before anything else happens.

## First start

Sign in, and if your account has no workspace yet, onboarding sets one up:

- **Create a workspace** is where it starts, already filled in: the workspace
  is called *Personal*, and your name is read from your email address
  (`max.mustermann@…` becomes *Max Mustermann*). Change either before you
  confirm — your name is what recipients of your shares and requests will
  see, on your signing identity.
- **Join one instead** by pasting an invite key someone sent you.

If you came from a link — a tool's [link proposal](tools.md), a request to
connect a tool, or a workspace invite — the app holds on to it while you sign
up and set up, and opens it afterwards. You do not have to go back and click
it again.

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
| **Connected tools** | Tools that proposed links, and what each of them may do | [Tools & link proposals](tools.md) |
| **Attestations** | What others confirmed about your identities, and what your workspace confirmed about others | [Attestations](attestations.md) |
| **Settings** | Identities, workspace members, API keys, domain verification | [Identities & trust](identities.md) |

## Opening links

Shares and requests travel as `revoked://` deep links — deliberately, so
there is no web page for a phisher to imitate. With the scheme registered,
clicking one opens the app directly on that share or request. Inside the app,
**Ctrl+V** with a link on the clipboard opens it too, and the *Open a link*
dialog can verify the sender against DNS before you open anything.

Two further links open the app: `revoked://a/…` offers an
[attestation](attestations.md), and `revoked://present` is a service asking
to be shown one.

A notification bell in the shell collects what happened while you were away:
responses arriving, links expiring or hitting their view cap, invites being
accepted, callbacks failing.
