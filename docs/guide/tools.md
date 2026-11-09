# Tools & link proposals

Some tools need data from the vault: an emergency-card generator, an
application form, a third-party service. With a **link proposal**, the tool
names the records it needs, and the owner creates the share on their own
server. The tool only ever names keys, never values, and has no access to
the vault unless reading is explicitly allowed.

A [request](requests.md) works in the opposite direction: the party that
wants the data sends a form, and the owner fills it in.

| | Request | Link proposal |
|---|---|---|
| Who starts it | The party that wants the data | A tool, on behalf of the data owner |
| Where the data ends up | In the requester's workspace, with that request's responses | In a share in the owner's workspace, under **Shares** |
| What the other side keeps | The responses: typed, or linked to the responder's vault so they can be revoked | At most the link, and only once it is handed over |

[Notfallkarte](notfallkarte.md) is a complete example: a web page that
turns a proposal into a wallet-sized emergency card.

Tools built on Revoked are listed in [Works with Revoked](works-with.md), a
tab in the app. A listed tool's address carries a **Listed** chip on its
proposals, and a request beyond its listing is pointed out.

## Reviewing a proposal

A proposal opens the app on **Link proposal from …**. The name after
*from* is the tool's self-declared name and is only a claim. The tool's
web address is shown beside it; that is what actually identifies it.

The review lists every record the share would include, located in the
vault by the keys the tool named. Missing records can be filled in
directly. A proposal can name a [template](templates.md) for its keys,
which gives each one a label and an input. Entered values are saved to the
vault like any other record.

Nothing is created until **Continue** is pressed. **Decline** returns to
the tool without sharing anything.

A proposal can also set the share's options: an expiry in days, a
watermark text, or the rental-application type. The share is created with
exactly those. If any part of a proposal is malformed, the whole proposal
is refused (*This link doesn't work*); the app never guesses the tool's
intent.

## Proposed requests, attestations and checks

Besides shares, a tool can propose:

- a **request**, to collect responses from others with one of the
  workspace's templates. The app opens **New request** with the template,
  the title and the end date filled in.
- an **attestation**, to confirm something about someone in the domain's
  name. The app opens **Issue an attestation** with the kind and
  the details to fill in. Every value is set by the owner.
- a **check**, to ask someone to present an attestation. The app opens
  **See someone's attestation** with the requested criteria.

Each form shows **Proposed by …** at the top, with the tool's web address
beside its self-declared name. Nothing happens until the form is saved.

A connected tool can then follow what was saved: whether a request is
still open and how many responses it has, whether an attestation was
accepted, and the result of a check, including what the person chose to
disclose. It never sees the responses to a request or the values in an
attestation.

### Suggested visibility {#visibility}

A proposed share, request or attestation can suggest who in the workspace
sees it, **Private** or **Workspace**. The suggestion pre-fills the choice on
the proposal, marked as suggested by the tool, and the owner confirms or
changes it. What a tool creates directly, without a proposal, is always
private until the owner changes it.

## Connecting a tool

A confirmed proposal tells the tool nothing further on its own. For that,
the tool is connected with **Connect**: as a step before the review, or
separately, for example from the tool's settings. A connected tool can see
the status of the links it proposed (active, paused, revoked or expired)
and how often they were opened. It can follow the requests, attestations
and checks it proposed the same way. It never sees their contents or
anything else in the vault, unless it is given a section or allowed to
read the vault.

All further access is controlled by switches, per tool. The reason the
tool gave for asking is shown beneath the switches:

| Switch | Effect |
|---|---|
| **Vault section** | The tool receives a vault section named after it, for storing its data. With **Read**, it sees only what is placed there. With **Manage**, it can also add records, and change or delete the ones it added. It cannot see the rest of the vault. |
| **Manage shares** | The tool shares the contents of its section without per-share confirmation. Every share is visible in the app and can be stopped. |
| **Manage requests** | The tool sends requests in the owner's name without per-request confirmation. Available only when confirmed on this device, never with a code. |
| **Revoke its links** | The tool can revoke the links and requests it proposed, for example when a printed card is discarded. A notification is sent as for any other revocation. |
| **Receive links** | When a proposed link is created, the tool receives it directly instead of it being copied over. Links with files or hidden values are always handed over manually. |
| **Read vault** | Available only when the tool asks for it, and off by default. The tool can read record values, except encrypted records, and cannot change anything. What it has read cannot be taken back. [Your AI assistant](assistant.md#let-it-read-your-vault) describes the trade-offs. |

Switches marked **Sensitive** allow actions that cannot be reversed:
handing out links, requesting data in the owner's name, or reading the
whole vault. They are intended only for tools trusted with that.

### Confirming on another device

To answer a tool, the app reopens the tool's page in the default browser,
which may differ from the browser where the flow began. A tool that
already knows the server can avoid this by collecting the answer itself.
It then shows a short code such as `83C-047` on its page, and the app
shows the same code before anything is connected. The connection should
proceed only if both match. The original tab then continues, even when
confirmation happened on a phone.

For a tool already connected in one browser, **Allow this browser** admits
another one, with the same permissions and nothing more.

## Tool sections

A tool that stores data, such as a packing list or a game save, can keep
it in the vault instead of on its own servers. **Vault section** stays on
when connecting, and the app shows the name of the section the tool will
receive:

- Everything the tool saves there belongs to the vault owner and appears
  in the vault, marked **Added by** and the tool's name.
- The tool can change only what it added. Records the owner places in its
  section remain the owner's, and the tool can only read them.
- The section stays in the vault after the tool is disconnected. Turning
  **Vault section** off later removes the tool's access; turning it on
  again restores the same section.

Placing a record in a section a tool can read gives the tool read access
to it. The app asks first and names the tool; **Add to section** confirms.
Removing the record from the section withdraws the access.

Further sections are granted under **Settings → Connected tools**. In
**Vault sections**, each section has a switch: on grants read access, off
removes it. The section stays in the vault either way. The tool's own
section is listed first, marked **Its own**.

## API keys for scripts

Scripts, such as one that keeps a record up to date, authenticate with an
**API key** instead. Keys are managed under
**Settings → Developer → API keys**. A key starts from a preset under
**New API key**, such as **Keep records current**; its permissions
are then ticked and, for vault access, the **Sections** are
selected. The key reaches only those sections. A key is shown once at
creation and cannot be retrieved later. Revoking it in the same list
disables it.

## Managing connected tools

**Settings → Connected tools** lists every tool by name and a short ID,
the first six characters of its full **ID**. Two tools of the same name, such
as two AI assistants, are told apart by this ID. In the vault, a section
header carries a chip for each tool behind it: a plug for the tool that
keeps the section, marked "off" while its access is switched off, and an eye
for a tool that may read it. Hovering over a chip shows the tool's name and
access; selecting it opens the tool's page. Tools name
themselves when they connect, so a name alone does not identify one. A tool's page shows the full ID and **Connected by**, the
account that connected it. The list also shows each tool's connection date,
last use, connection expiry, and everything it proposed: links, requests,
attestations and checks. Its permissions and sections can be changed
there, and each of its links opened or revoked. **Read your vault** appears
only while enabled and can be turned off there; turning it on again
requires the tool to ask when it connects. A request, attestation or check
opens where it lives in the app.

### Pausing a tool

Turning off **Active** suspends the tool: it can do nothing, its links stop
opening, and its requests stop accepting responses. Turning it back on
restores everything as before. Links paused manually stay paused.

### Disconnecting a tool

**Disconnect** cuts the tool off immediately. Its links and requests remain
with the owner and keep working, unless **Revoke its links too** is also
ticked, which closes its requests as well. Issued attestations are not
affected.

A connection lasts **90 days** from its last confirmation in the app. Only
confirming it there again renews it; a tool cannot keep itself alive.
Every tool action (connecting, reading, revoking, disconnecting) is
recorded in the audit log under the tool's web address.

## Sign-in services

Services signed in to with Revoked, such as a game or a shop, are listed
under **Settings → Connected tools**, in **Signed-in services**.
Each service shows the first and last sign-in, what it learned about the
account, and any shared entries.

To stop a service reading an entry, open its link under
**Shared entries** and choose **Revoke**. The service can no longer read
it.

### Pausing a service

**Pause** blocks signing in to that service with Revoked, and blocks the
service from reading entries. **Activate** reverses this, and the service
recognises the account as before.

### Disconnecting a service

**Disconnect** stops the service from reading entries. Signing in there
again requires a new approval in the app.

### New service ID

Ticking **Get a new ID** on disconnect makes the service treat any later
sign-in as a new user. After disconnecting, the same button is available on
the service's page.

This cannot be reversed: the previous account at the service, and anything
saved in it such as game progress, cannot be recovered. **Pause** is the
reversible alternative.

On a later sign-in, the app shows what the service asks for, with nothing
preselected. An email address, a name or an identity can still reveal the
person behind the account, so these are best shared only where that is
acceptable.

## Names per service

When a service asks for a name, the name it receives is chosen per
service: a game name in one place, a legal name in another. The top of
**Your name** shows what the service will see.

Selecting one of the identities or vault entries uses it. A new name for
that service alone is entered in **New name**. Turning off the switch
shares no name; sign-in still works.

When a vault entry is used, changes to the entry can reach the service;
some services update it only at the next sign-in. The choice is remembered
and can be changed at the next sign-in. Either way, the service keeps the
same ID unless a new one is requested.

## Entries a service reads

A service can ask for something from the vault, such as a game asking for
a player name. The app shows what the service will see, and the value
comes from one of the following:

- one of the suggested entries,
- **Browse vault**, to open a section and pick an entry, or
  **Search vault**, to search every section,
- **New value**, which saves a new entry and shares it,
- nothing, by turning off the switch. Sign-in still works.

Picking an entry with a different key adds an alias to the vault for next
time.

Entries come from the current workspace. With several workspaces, tapping
the workspace name on the same screen switches it. New entries are saved
there, and the app stays in that workspace afterwards.

Anything added for a service goes into its own vault section, named after
the service, such as **Sign-in · showdown.example**, so it remains visible
what a service caused to be added. **Open service** in the section's menu
opens the service. Existing entries stay where they are.

## Signing out of a service

The service maintains its own session, so signing out happens there.
**Pause** and **Disconnect** do not end that session. The service may also
have retained what it learned, such as an email address; only the service
can delete that.
