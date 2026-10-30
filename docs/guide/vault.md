# Vault

Your vault is where your information lives. Everything you share points
back here. Change a value once, and every share of it shows the new value
right away.

## Add a record {#records}

A record is one piece of information, with a label and a value. Pick a type
so the app shows and checks the value the right way:

| Type | Use it for |
|---|---|
| Text | Anything written (the default) |
| Number | A number |
| Link | A web address |
| Yes/no | A yes-or-no answer |
| Date and time | A date, with its time |
| File | A document or an image |

A value can be up to 1000 characters long. Files have their own limits.

Each record also gets a key, made from its label: `Steuer-ID (privat)`
becomes `steuer_id_privat`. Templates, requests and scripts find your
records by their key. To pick your own, open **Advanced**.

### Hide what's sensitive

Mark a record **Hidden**, and the app masks its value until you reveal it.
Use it for passwords, tokens, anything you don't want read over your
shoulder. On a file, hiding masks the file name.

### Files

A file record holds one upload. You can swap in a new version later, and
rename what people see when they download it. The name is only a label.
Whether you can upload, and how much, is up to
[whoever runs your server](../installation/env.md#files).

### Aliases

Someone asks for `iban`, but you saved it as `bank_account`? Add an alias.
It points at your existing record and always shows its current value. They
get the key they asked for, and your data stays in one place.

### Get reminded

A record can remind you about itself. Open it and add a reminder:

- **On a date**: in a week, a month, a year, or on a day you pick. Handy for
  a passport that needs renewing or a contract to cancel.
- **On a change**: the first time this record's value changes, or another
  record's in the same workspace. For an alias, a change to the record it
  points at counts.

The reminder lands in your notifications, with your note. It names the
record but never shows its value. Each reminder goes off once; add it again
from the record to hear about the next time too. Reminders are yours alone.
Other members of the workspace don't see them.

## Group records into sections

A section groups records that belong together, like "Banking" or
"Onboarding pack". You can rename it, duplicate it, and **share it as one**.
A shared section always shows what's in it today: add a record later, and
everyone with the link sees it too.

## Start from a template

**New → From a template** creates a whole set of sections and records in
one go. Handy when every client or project needs the same setup. Templates
also decide what a [request](requests.md) asks for. To build your own, see
[Templates](templates.md).
