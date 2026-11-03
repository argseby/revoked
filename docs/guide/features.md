# Features

**Settings → Features** decides which parts of the app appear in the
navigation. Turning off what a member never uses keeps the app short. The
choice belongs to the account and applies on every device where it signs
in. A change is saved as soon as a box is ticked or cleared.

## Visible features

| Feature | Covers | On for a new account |
|---|---|---|
| **Vault** | Records, files and sections | Always on |
| **Sharing** | Links to records, and who can read what | Yes |
| **Requests** | Asking people for information and reading their answers | Yes |
| **Identities and attestations** | Identities, and what others confirm about the account | Yes |
| **Contacts** | The people the workspace sends to and requests from; see [Contacts](contacts.md) | Yes |
| **Connected tools** | Other apps and services using records, and signing in with Revoked | Yes |
| **Developer** | API keys, webhooks, the AI assistant setup, and technical detail | Yes |

The **Vault** cannot be turned off; every other part depends on it.

## Visibility and permissions

Hiding a feature never removes a permission, and showing one never grants
one. The server enforces each member's
[permissions](workspaces.md#member-permissions) whatever is ticked here.

A feature appears only when it is both turned on and allowed in the
current workspace. A feature the workspace does not allow stays in the
list, unticked and marked **Not allowed here**; a workspace admin can grant
the permission it needs.

A link to a page of a hidden feature still opens. The page states that the
feature is off and offers a button to turn it back on in one step.

## Presets from invites

A new account chooses its features during setup. An account that joins
through an [invite](workspaces.md#invites) starts with the features the
invite selected, under **Initial features**: **Vault only** shows the vault
alone, **Vault and sharing** adds **Sharing**, and **Everything** turns on
every feature. The invite presets the list only for an
account that has not chosen yet. Any later change made here takes
precedence.

## Developer

**Developer** is on by default and is meant for scripting against the API.
It adds **API keys**, **Webhooks** and **AI assistant (MCP)** under
Settings, and shows technical detail elsewhere in the app, such as a share's
slug and the API request behind a form. Nothing needed to decide or act is
hidden while it is off. API keys are described in
[Tools & link proposals](tools.md#api-keys-for-scripts).
