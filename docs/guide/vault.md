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

## Creating records from a template {#start-from-a-template}

**New → From a template** creates a complete set of sections and records
in one step, which suits setups that every client or project needs.
Templates also define what a [request](requests.md) asks for. Custom
templates are described in [Templates](templates.md).
