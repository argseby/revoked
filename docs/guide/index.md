# Using the app

Revoked runs on desktop and Android. Installation is covered in
[Installing the app](../installation/app.md).

By default, the app connects to a server on the local computer. Another
server is selected by tapping the server on the login screen and entering
its address. **Test** checks that the server responds, and **Save** stores
it.

The official server, `https://api.revoked.link`, is available for
evaluation. It is experimental and intended for testing only, with no
guarantees for stored data.

## Common tasks

| Task | Example | Page |
|---|---|---|
| Store information | One address record reused by several services. | [Vault](vault.md#example-a-delivery-address) |
| Give someone access | Separate Wi-Fi links for a visitor and a contractor. | [Sharing](sharing.md#example-separate-links-for-two-recipients) |
| Ask people for information | A shop collects each customer's delivery details. | [Requests](requests.md#example-delivery-details-from-a-customer) |
| Reuse a set of fields | The same address and phone fields in a vault or request. | [Templates](templates.md#example-one-structure-two-uses) |
| Sign in to a website | Corner Shop receives an account ID and an optional address grant. | [Sign-in lab](../labs/sign-in.md) |

The vault stores the original information. Shares let others read selected
information. Requests ask others to provide it. A template supplies field
structure for a vault or request; it does not share anything by itself.

## First start {#first-start}

After sign-in, an account without a workspace is guided through setting
one up:

- **Create your own.** The form is prefilled: the workspace is named
  *Personal*, and the display name is derived from the email address
  (`max.mustermann@…` becomes *Max Mustermann*). Both can be changed
  before pressing **Continue**. Recipients of shares and requests see this
  name.
- **Join someone else's.** **Use an invite key** accepts a key sent by a
  member of that workspace.

Creating a workspace is followed by **Features**, which
selects the visible features: sharing, requests, identities and
attestations, contacts, connected tools. The vault is always present.
Unselected features stay hidden and can be enabled later under
**Settings → Features**.

A link that opened the app before sign-in, such as a tool's
[link proposal](tools.md), a request to connect a tool or a workspace
invite, is kept through sign-up and opened once setup is complete. It does
not need to be opened again.

Vault, shares, requests, templates and identities all belong to a
workspace. See [Workspaces & members](workspaces.md).

## Navigation

**New**, at the top of the sidebar, creates any item: a record, a file, a
share link, a request, an attestation. On a phone it floats in the corner,
and the bottom bar holds four destinations, with the rest under **More**
beside **Settings**. Pages such as **API keys** or **Webhooks** create
their items in place, without a drawer.

Only features enabled under **Settings → Features**, and permitted by the
workspace, are shown. Enabling **Developer** there shows the API request
behind every form. A link to a disabled feature still opens and offers to
enable it.

| Where | Purpose | Details |
|---|---|---|
| **Overview** | Counts, items needing attention, and everything that can read the vault | [Overview](overview.md) |
| **Vault** | Records, files and sections | [Vault](vault.md) |
| **Shares** | Links to records, with view counts, under **Sent**. Shares from others are under **Received**. | [Sharing](sharing.md) |
| **Requests** | Requests for information and their responses, under **Sent**. Requests from others are under **To answer**. | [Requests](requests.md), [Responses](requests.md#reading-what-came-back) |
| **Attestations** | Attestations held, issued to others, and checked | [Attestations](attestations.md) |
| **Contacts** | People and services that records are sent to or requested from | [Contacts](contacts.md) |
| **Notifications** | Events since the last visit, filtered by unread or needing attention | [Notifications](notifications.md) |
| **Settings** | Features, workspaces, members, invites, identities, connected tools, API keys, templates and domain verification | [Workspaces & members](workspaces.md), [Identities & trust](identities.md), [Tools & link proposals](tools.md), [Your AI assistant](assistant.md), [Templates](templates.md), [Appearance](appearance.md), [Features](features.md), [Passkeys](passkeys.md), [End-to-end encryption](encryption.md) |

## Opening a received link

Shares and requests arrive as `revoked://` links, which open the app
directly on the item. This is deliberate: an app link leaves no web page
for a phisher to imitate.

A link on the clipboard can also be opened with **Ctrl+V** in the app, or
through **New → Open or scan a link**. The sender is verified before
anything opens.

Two further kinds of link open the app: an
[attestation](attestations.md) offer (`revoked://a/…`), and a service's
request to see one (`revoked://present`).

## Notifications

**Notifications** lists recent events: new responses, links that expired
or reached their view limit, accepted invites, failed callbacks, and
[reminders](vault.md#get-reminded). It opens from the sidebar or the bell,
and can be narrowed to **Unread** or **Needs attention**.
