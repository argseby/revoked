# Using the app

Revoked runs on desktop and Android. If you haven't installed it yet,
[start here](../installation/app.md).

The app looks for a server on your own computer first. To use another one,
tap the server on the login screen and enter its address. **Test** checks
that it answers, and **Save** keeps it.

## Get started {#first-start}

Sign in. If you don't have a workspace yet, the app helps you set one up:

- **Create your own.** It's already filled in for you. The workspace is
  called *Personal*, and your name comes from your email address
  (`max.mustermann@…` becomes *Max Mustermann*). Change either one before
  you confirm. People who get your shares and requests will see this name.
- **Join someone else's.** Choose **Use an invite key** and paste the key
  they sent you.

Did you arrive through a link? It might be a tool's
[link proposal](tools.md), a request to connect a tool, or a workspace
invite. The app keeps it while you sign up, and opens it when you're done.
You don't have to click it again.

Your vault, shares, requests, templates and identities all live in a
workspace. See [Workspaces & members](workspaces.md).

## Find your way around

**New** starts anything: a record, a file, a share link, a request, an
attestation. The sidebar takes you to the rest.

| Where | What you do there | Learn more |
|---|---|---|
| **Vault** | Keep your records, files and sections | [Vault](vault.md) |
| **Shares** | Send links to your records, and see how often they were opened | [Sharing](sharing.md) |
| **Requests** | Ask people for information and read their answers. Shares you saved from others wait under **Received**. | [Requests](requests.md), [Read the answers](requests.md#reading-what-came-back) |
| **Attestations** | Keep what others confirm about you, confirm things about others, and check what others show you | [Attestations](attestations.md) |
| **Settings** | Workspaces, members, invites, identities, connected tools, API keys, templates and your domain check | [Workspaces & members](workspaces.md), [Identities & trust](identities.md), [Tools & link proposals](tools.md), [Templates](templates.md) |

## Open a link someone sent you

Shares and requests arrive as `revoked://` links. Click one, and the app
opens right on it. That's on purpose: an app link leaves a scammer no web
page to imitate.

You can also press **Ctrl+V** in the app with a link on your clipboard, or
choose **New → Open or scan a link**. The app checks the sender before it
opens anything.

Two more kinds of link open the app: an offer of an
[attestation](attestations.md) (`revoked://a/…`), and a service asking to
see one (`revoked://present`).

## Catch up on what happened

The bell collects what happened while you were away: new answers, links
that expired or reached their view limit, accepted invites, failed
callbacks, and your [reminders](vault.md#get-reminded).
