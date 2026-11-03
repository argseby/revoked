# Overview

**Overview** is the first screen after sign-in. It shows what needs a
decision and everything that can currently read the vault: people through
links, connected tools and API keys.

## Figures

Four counts sit at the top, in one row on a wide window and two by two on a
phone:

| Figure | Counts |
|---|---|
| **Active links** | Links that currently open |
| **People with access** | Recipients holding at least one active or paused link |
| **Connected tools** | Tools whose connection has not expired |
| **API keys** | All API keys of the workspace |

A recipient is a link's label. Two links labelled "Property manager" count
as one person. Labels are what the sender typed, not verified identities.

## Attention cards {#attention-cards}

Below the figures, a card appears for each kind of item that needs a look.
A card is shown only while its count is above zero, and tapping it opens the
list it counts.

| Card | Shown when | Opens |
|---|---|---|
| **New answers** | Responses to requests have not been read yet (only with requests enabled) | **Requests** |
| **Ends soon** | An active link expires within three days, or has used the last fifth of its view limit | The link itself, or **Shares** for several |
| **Paused** | Links are paused and unavailable until reactivated | **Shares** |
| **Webhooks failing** | Deliveries to a webhook are not getting through | **Webhooks** |
| **Keys expiring** | An API key expires within the next seven days | **API keys** |

With a single link ending soon, the card names it and gives the reason, such
as "Expires in 2 days" or "9 of 10 views used". See
[Share status](sharing.md#share-status) and [Webhooks](../api/webhooks.md).

## Who can read the vault

Four groups list each route into the vault. A group longer than five rows
shows the first five and a row that expands the rest.

| Group | Each row shows | Tapping opens |
|---|---|---|
| **People** | The recipient, their link, record and section counts, and a status | The link, or **Shares** narrowed to that recipient when they hold several |
| **Connected tools** | The tool, its reach (**Whole vault**, a number of sections, or no vault access) and when it was last used | The tool's page |
| **API keys** | The key, its reach, when it was last used and its expiry date | **API keys** |
| **Shared records** | The record and how many active links show it | The record |

**People** is always present and reads "No recipients" when nothing is
shared; **All** beside it opens **Shares**. The other three groups appear
only when they have entries. A connected tool with access to the whole
vault carries a **Whole vault** badge, and a paused tool a **Paused** badge.

A record shown through a section or an alias counts as shown. Aliases are
listed under the record they point to. See
[Tools & link proposals](tools.md#managing-connected-tools) and
[API keys for scripts](tools.md#api-keys-for-scripts).

## First run {#first-run}

A workspace with no records, no links, no connected tools and no API keys
shows **Welcome** in place of the overview, with three steps under
**Setup**:

| Step | Action |
|---|---|
| **Create account** | Marked as done |
| **Add a record** | Opens the drawer for a new record |
| **Share and revoke** | Starts a one-minute tour with real data |

The overview replaces this screen as soon as any of the four exists. See
[Vault](vault.md) and [Sharing](sharing.md).
