# Vault

The vault holds the workspace's information, and every share points back
to it. A value changed once is shown in its new form by every share of it
immediately.

## Records {#records}

A record is a single piece of information with a label and a value. Its
type determines how the value is displayed and validated:

| Type | Use |
|---|---|
| Text | Free text (the default) |
| Number | A number |
| Link | A web address |
| Yes/no | A yes-or-no answer |
| Date and time | A date with its time |
| File | A document or an image |

Values are limited to 1000 characters. Files have separate limits.

Each record also has a key, derived from its label: `Steuer-ID (privat)`
becomes `steuer_id_privat`. Templates, requests and scripts locate records
by key. A custom key can be set under **Advanced**.

### Hidden records

A record marked **Hidden** has its value masked until revealed. This suits
passwords, tokens and other values that should not be readable on screen.
On a file record, the file name is masked.

### Files

A file record holds one upload. The file can be replaced with a new
version, and the name shown on download can be changed; the name is only a
label. Whether uploads are allowed, and their size limit, is set by the
[server operator](../installation/env.md#files).

### Aliases

An alias makes an existing record available under a second key, for
example when a request asks for `iban` but the record is stored as
`bank_account`. The alias always shows the record's current value, so the
data stays in one place.

### Reminders {#get-reminded}

A record can carry reminders, added from the record itself:

- **On a date**: in a week, a month, a year, or on a chosen day, for
  example for a passport renewal or a contract's notice period.
- **On a change**: the first time this record's value changes, or that of
  another record in the same workspace. For an alias, a change to the
  record it points to counts.

A reminder appears in notifications with its note. It names the record but
never shows its value. Each reminder fires once; to be reminded again, it
is added again from the record. Reminders are private to the member who set
them and are not visible to other members of the workspace.

## Sections {#group-records-into-sections}

A section groups related records, such as "Banking" or "Onboarding pack".
Sections can be renamed, duplicated and shared as one. A shared section
always reflects its current contents: a record added later becomes visible
to everyone with the link.

### Who sees a section {#members}

Records are otherwise seen only by the member who created them. **Visibility**
in a section's menu sets who else sees it:

- **Private**: seen by the owner only.
- **Workspace**: seen by every member who can read the vault, with current
  values. The section then carries a **Members** badge.

For a section visible to the workspace, **Editing** sets whether others may
change it. With **Owner only**, they open its records read-only. With
**Members who manage the vault**, members who see it and hold that
permission can change its records and the section itself. The sheet also
shows how many members see the section and how many may change it.

- Other members see the section below their own, marked **Shared by** its
  owner.
- Only the section's owner can change who sees it, and only from the app: an
  API key or a connected tool cannot change who reads it.
- Only records the owner created are shown. Files, aliases and answers to
  requests are left out for now.
- A share can hold only its creator's own records and sections, so a record
  seen through a colleague's section cannot be passed on through a link.
- Taking the section back to **Private**, or taking away a member's
  permission to read the vault, hides it again at once. Anything already
  read or copied stays with whoever read it.
- [Encrypted records](encryption.md#access) in a visible section open only
  for members whose devices were given the workspace's key.

### Who sees an entry {#entries}

An entry can be made visible on its own, without a section: **Visible to**
when it is created, or **Visibility** on its page later. **Workspace** suits
what the whole company relies on (its address, phone number or managing
director), **Groups** what only some teams need. Every member who can read the
vault then finds it under **Shared entries**, and can put it in their own
shares. A private entry of someone else never appears there, and never goes
into anyone else's share.

### Publishing to the workspace vault {#publishing}

Making an entry or section visible beyond its owner, and changing one that
is, takes the permission **Publish to the workspace vault**. Without it a
member's entries stay their own: **Visible to** offers only **Private**, and a
workspace default that would publish gives way to private for them. Admins
hold the permission; it is granted to others like any other permission, and
none of the invite presets include it. Members who published sections before
the permission existed kept it.

Files stay with their owner for now, as do aliases and answers to requests.

## Creating records from a template {#start-from-a-template}

**New → From a template** creates a complete set of sections and records
in one step, which suits setups that every client or project needs.
Templates also define what a [request](requests.md) asks for. Custom
templates are described in [Templates](templates.md).
