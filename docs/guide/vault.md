# Vault

The vault holds **records**: key/value entries everything else points at.
A share never copies a record — it references it, so editing the value here
changes what every share of it resolves to, immediately.

## Records

A record is a key, a value, a label, a **type** and a **format**.

| Type | The value is |
|---|---|
| `text` | Free text (the default) |
| `number` | A number |
| `url` | A link |
| `boolean` | Yes/no |
| `datetime` | A date and time |
| `file` | An uploaded file |

The type drives how the app renders and validates the value; under the hood
everything but a file is stored as text, capped at 1000 characters.

The format is `default` or **`hidden`** — a hidden value is masked on screen
until you reveal it. Use it for passwords, tokens, anything you don't want
readable over your shoulder. For file records, hiding masks the file name.

### Files

A file record stores one upload. You can replace the file in place and rename
what a downloader sees — the name is a label, never a path. Whether uploads
are allowed and how large they may be is the
[operator's choice](../installation/env.md#files).

### Aliases

A record can point at another record instead of holding its own value, and it
resolves the parent's *current* value at read time. This is how you answer
someone's requested key with data you already hold: the alias carries the key
they asked for, the value stays in one place.

### Reminders

A record can remind you about itself. Open it and add a reminder:

- **On a date** — in a week, a month, a year, or on a day you pick. Good for
  a passport that needs renewing or a contract to cancel.
- **When something changes** — the first time this record's value changes,
  or another record's in the same workspace. For an alias, a change to the
  record it points at counts.

When it fires, the reminder lands in your notifications, with your note. It
names the record but never shows its value. A reminder fires once; arm it again
from the record to be told next time too. Reminders are yours alone — other
members of the workspace do not see them.

## Sections

A section is a named group of records — "Banking", "Onboarding pack" — that
can be created, renamed, duplicated, and **shared as a unit**. Sharing a
section shares its current membership: add a record to it later and existing
shares of the section pick it up.

## Starting from a template

*New → From template* materialises a whole set of sections and records in one
step — useful when every client or project gets the same structure. Templates
are also what give [requests](requests.md) their shape; authoring them is
covered in [Templates](templates.md).
