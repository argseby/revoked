# Section views

A section in the [vault](vault.md#group-records-into-sections) is a list of
records. Many sections describe one thing, though: a Wi-Fi network, an
emergency card, a car, a medication plan. A **section view** shows such a
section as that thing: the network with a code to scan, the card with its
call buttons, the car with the days left until its inspection, the plan with
the next dose.

A view is a small JSON layout. It holds no values of its own: every value it
shows comes from a record, looked up by the record's key. The records stay
exactly as they are; a view only reads them.

## Card and records

A section with a view opens as a card. A switch next to the section title
flips between the card, labelled with the view's name, and **Records**, the
plain list the section is made of. Records are added and edited in the list
as before; the card follows their current values.

Views appear in three places:

- in the vault in the app, for the owner's own sections and for sections
  other members make visible to the workspace,
- on received shares in the app,
- on the public share page, for anyone opening a share link.

## Where a view comes from

The view a section shows is chosen in this order:

1. **A view saved on the section itself.** It wins over everything else.
2. **A template's view whose `match` keys the section holds.** A section
   with the keys `network_name` and `wifi_password` shows the Wi-Fi view
   whether or not it was created from the Wi-Fi template.
3. Otherwise the section shows its records, without a switch.

Every [built-in template](templates.md#built-in-templates) ships with a view
in its schema under `"view"`. When a template creates a section, its view
is copied onto that section, so later changes to the section's view leave the
template untouched, and the other way round.

### Editing a section's view {#edit-a-section}

**Section view** in a section's menu opens a JSON editor with a live
preview below it. The editor starts from the view the section shows now, its
own or the one it takes from a template. The preview draws the view over the
section's current records while the JSON is changed, so a missing key or a
misspelled block shows at once. **Start from…** offers every template's view
as a starting point, and **Remove view** empties it. Saving stores the view
on the section; it then takes precedence over any template's view. A section
saved with no view shows its records again, unless a template's view
matches it.

### Editing a template's view {#edit-a-template}

In the [template editor](templates.md#custom-templates), the **View** part
holds the template's view as code, with a preview below it. The preview uses
sample values made from the template's own fields: each field's default
value, or a sample of its type. In the JSON mode the view is part of the
schema text under `"view"`, beside `"records"`, and the **View** part shows
only its preview. The view is copied onto every section the template creates
from then on.

## Format reference

A view is one JSON object:

```json
{
  "version": 1,
  "id": "wifi",
  "name": "Wi-Fi network",
  "accent": "teal",
  "match": ["network_name", "wifi_password"],
  "blocks": [
    { "type": "header", "icon": "wifi", "title": "{network_name}" }
  ]
}
```

### Top-level fields

| Field | Required | Meaning |
|---|---|---|
| `version` | Yes | The format version. Only `1` exists. A view with a higher version is not shown. |
| `id` | Yes | A short name for the view, such as `wifi`. |
| `name` | No | The name on the card/records switch and the header's fallback title. Defaults to `id`. |
| `accent` | No | The card's colour: `teal`, `blue`, `red`, `amber`, `green` or `violet`. Defaults to `blue`; an unknown name also reads as blue. Raw colour values are not accepted. |
| `match` | Yes | The record keys a section must hold for a template's view to apply to it. An entry `group:<name>` asks for at least one member of that [record group](#record-groups). At least one entry is needed. |
| `blocks` | Yes | The blocks of the card, drawn top to bottom. At least one valid block is needed. |

Only the section's own records decide whether `match` is met. Records found
elsewhere in the vault can fill in values, but never make a view apply.

### Blocks

Every block has a `type` and may carry a [`when`](#conditions) condition.
Blocks of a type the app does not know are skipped, as are blocks missing a
required option.

#### `header`

The card's title row: an icon in the accent colour, a small line above the
title and an optional line below it.

| Option | Default | Meaning |
|---|---|---|
| `title` | — | The title. When it is empty once filled in, the view's `name` is shown. |
| `eyebrow` | — | A small line above the title. |
| `subtitle` | — | A small line below the title. |
| `icon` | `folder` | One of `wifi`, `health`, `car`, `medication`, `person`, `phone`, `calendar`, `key`, `server`, `finance`, `folder`. An unknown name shows the folder. |

The eyebrow and subtitle are left out when any value they name is missing.

```json
{ "type": "header", "icon": "car", "eyebrow": "{make_model}",
  "title": "{license_plate|upper}" }
```

#### `text`

One line of text, left out when any value it names is missing.

| Option | Default | Meaning |
|---|---|---|
| `text` | — | The text. |
| `tone` | `muted` | `muted` (small and grey), `body` (regular text) or `warning` (with a warning sign). |

```json
{ "type": "text", "text": "Check with the doctor before changing a dose." }
```

#### `badges`

Small labels in a row. Each item has its own condition, so a badge appears
only when its record says so.

| Item option | Default | Meaning |
|---|---|---|
| `text` | — | The label. Required. |
| `tone` | `neutral` | `neutral`, `success`, `warning`, `danger` or `accent` (the view's accent colour). |
| `when` | — | A [condition](#conditions) for this badge alone. |

The block is left out when no badge is shown. A badge whose text names a
value that is missing is left out too, like an unfilled fact.

```json
{ "type": "badges", "items": [
  { "text": "Organ donor", "tone": "success",
    "when": { "key": "organ_donor", "is": "true" } },
  { "text": "Blood type {blood_type}", "tone": "danger",
    "when": { "key": "blood_type" } } ] }
```

#### `facts`

Labelled values in a grid of up to three columns, fewer on narrow screens.
An item whose value names a missing record is left out, so an unanswered
field leaves no gap; the block is left out when no item remains.

| Item option | Default | Meaning |
|---|---|---|
| `label` | — | The label above the value. Required. |
| `value` | — | The value, usually one or more placeholders. Required. |
| `mono` | `false` | Shows the value in a fixed-width font, for numbers and codes. |

A hidden record named in a fact reads as dots. Hidden values belong in a
`secret` block, which can reveal them.

```json
{ "type": "facts", "items": [
  { "label": "Insurer", "value": "{insurer}" },
  { "label": "Policy number", "value": "{policy_number}", "mono": true } ] }
```

#### `secret`

A value that stays covered until revealed, with buttons to show and to copy
it.

| Option | Default | Meaning |
|---|---|---|
| `key` | — | The record's key. Required. |
| `label` | the key | The label above the value. |

The value is covered whether or not its record is marked hidden. A record
not filled in yet reads "Not filled in yet."; an
[encrypted record](encryption.md) this device cannot open reads "Not
readable on this device."

```json
{ "type": "secret", "label": "Password", "key": "wifi_password" }
```

#### `qr`

A code to scan, filled in from records.

| Option | Default | Meaning |
|---|---|---|
| `data` | — | The text the code carries, with placeholders. |
| `revealWith` | — | The key of a `secret` the code contains. The code stays covered until that secret is revealed on the card. |
| `caption` | — | A line below the code. |

The block is left out when any value `data` names is missing. A code that
carries a hidden value stays covered until that value is revealed in a
`secret` block, whether or not `revealWith` names it; `revealWith` adds a
secret to wait for explicitly.

```json
{ "type": "qr", "revealWith": "wifi_password",
  "data": "WIFI:T:WPA;S:{network_name|wifi};P:{wifi_password|wifi};;",
  "caption": "Scan with a phone camera to join." }
```

#### `actions`

Buttons that act on a record's value.

| Item option | Default | Meaning |
|---|---|---|
| `label` | — | The button text. Required. |
| `key` | — | The record holding the address or number. Required. |
| `kind` | `url` | `url` opens a web address, `tel` starts a call, `mail` writes an email. |

A button is left out when its record is empty or hidden, and when the value
is not an `http`, `https`, `tel` or `mailto` address. For `tel`, everything
except digits and `+` is dropped from the number. When the label names a
missing value, that placeholder is dropped from it: "Call {insurer}" reads
"Call".

```json
{ "type": "actions", "items": [
  { "label": "Call {contact_name}", "key": "contact_phone", "kind": "tel" },
  { "label": "Router admin", "key": "router_admin", "kind": "url" } ] }
```

#### `countdown`

The days until a date, with the date itself.

| Option | Default | Meaning |
|---|---|---|
| `key` | — | The record holding the date. Required. |
| `label` | — | The label above the date. |
| `warnDays` | `30` | How many days ahead the countdown turns to a warning. |

Days are counted in whole calendar days. More than `warnDays` away the
countdown is neutral; within `warnDays`, and on the day itself ("Today"), it
shows as a warning; once the date has passed it shows as overdue in the
danger colour. The block is left out when the record holds no readable date.

```json
{ "type": "countdown", "label": "Next inspection", "key": "inspection_due",
  "warnDays": 45 }
```

#### `split`

Two columns side by side: a wide `main` and a narrow `side`, each a list of
blocks. On narrow screens, and with large text, the side column moves below
the main one.

| Option | Default | Meaning |
|---|---|---|
| `main` | — | Blocks for the wide column. |
| `side` | — | Blocks for the narrow column, such as a `qr`. |

```json
{ "type": "split",
  "main": [ { "type": "secret", "label": "Password", "key": "wifi_password" } ],
  "side": [ { "type": "qr", "data": "{network_name}" } ] }
```

#### `schedule`

A plan over the day for every member of a [record group](#record-groups):
one row per member, one column per time of day. It suits medication plans,
and works out the next dose and when a stock runs out.

| Option | Default | Meaning |
|---|---|---|
| `group` | — | The record group's name. Required. |
| `heading` | `Item` | The heading of the first column. |
| `label` | `name` | The member field shown as the row's name. |
| `detail` | — | A member field shown below the name, such as the dose. |
| `note` | — | A member field shown as a further line below. |
| `until` | — | A member field holding an end date. After it, the row is dimmed and marked "ended". |
| `columns` | — | The times of day, each `{ "field", "label", "time" }`: the member field holding the amount, the column heading (defaults to the field) and the time as `HH:mm` (defaults to `08:00`). |
| `next` | `false` | Shows the next dose: what is due, at what time, and how long until then. |
| `refill` | — | `{ "stock": "<field>", "warnDays": 7 }`: warns when a member's stock lasts `warnDays` days or fewer. `warnDays` defaults to `7`. |

**Amounts.** A cell is read as an amount: `1`, `2`, `0.5` or `1,5`,
fractions such as `1/2`, and the signs `½`, `¼`, `¾` and `⅓`. An empty
cell, `-`, `–` and `0` mean none, and show as a dash.

**Next dose.** The earliest column time from now on, today or else
tomorrow, at which a running member takes more than none. All members due
at that time are listed together.

**Days of stock.** The stock field is read as an amount and divided by the
member's daily total (the sum of its columns), rounded down. Members that
have ended, or that have no stock or no daily amount, get no warning. With
none left, the warning asks for a refill now.

```json
{ "type": "schedule", "group": "medication", "heading": "Medicine",
  "detail": "dose", "until": "until",
  "columns": [
    { "field": "morning", "label": "Morn", "time": "08:00" },
    { "field": "evening", "label": "Eve", "time": "18:00" } ],
  "next": true, "refill": { "stock": "stock", "warnDays": 7 } }
```

#### `divider`

A thin line between blocks. It has no options and is often given a `when`,
so it appears only when the part below it has content.

```json
{ "type": "divider", "when": { "key": "contact_name" } }
```

### Conditions {#conditions}

Any block, and any badge, may carry `when`:

| Form | Shown when |
|---|---|
| `{ "key": "contact_name" }` | the record holds a value that is not empty |
| `{ "key": "guest_network", "is": "true" }` | the record's value, trimmed, is exactly the given text |

A yes/no record holds `true` or `false`. A condition on a record that is
missing, hidden from this device or encrypted for other devices counts as
empty.

### Placeholders and filters {#placeholders}

Text options hold `{key}` to insert a record's value. Keys are written in
lower case with digits, `_` and `-`. A filter follows a bar, and several can
be chained: `{key|filter}`, `{key|lower|wifi}`.

| Filter | Effect |
|---|---|
| `upper` | upper case: `b-ab 123` becomes `B-AB 123` |
| `lower` | lower case |
| `date` | a stored date as a readable calendar day |
| `wifi` | escapes `\`, `;`, `,`, `:` and `"` with a backslash, as a Wi-Fi join code requires |

The list is fixed: views never compute. An unknown filter leaves the value
as it is.

**Where values are found.** A key is looked up in the section's own records
first, then in the rest of the owner's vault, so one card can draw on
records a template spread over several sections, such as an emergency
contact and a doctor. Answers received through requests are not part of
that lookup. On a public share page, only the records in the share are
found; anything else reads as missing. An [alias](vault.md#aliases) reads
the record it points at.

**Missing and hidden values.** A missing value fills in as nothing; most
blocks then leave out the line that names it, as described for each block.
A hidden record fills in as dots until it is revealed in a `secret` block
on the card.

### Record groups {#record-groups}

A record group holds several members of the same shape, such as the
medicines of a plan. Its records are keyed `<group>-<n>-<field>`:

| Key | Value |
|---|---|
| `medication-1-name` | Ibuprofen |
| `medication-1-dose` | 400 mg |
| `medication-1-evening` | 1 |
| `medication-2-name` | Vitamin D |
| `medication-2-morning` | ½ |

Members are ordered by `n`. A member whose fields are all empty is left out.
`group:medication` in `match` is met as soon as the section holds one such
record, and a `schedule` block with `"group": "medication"` reads
`name`, `dose`, `morning` and so on as each member's fields.

## Examples

The four views that ship with the built-in templates, from easy to hard.

### Wi-Fi network

A header, a hidden password with show and copy, and a join code that stays
covered until the password is revealed. It demonstrates `split`, a
`secret` with a `qr` that waits for it, and the `wifi` filter.

```json
{
  "version": 1, "id": "wifi", "name": "Wi-Fi network", "accent": "teal",
  "match": ["network_name", "wifi_password"],
  "blocks": [
    { "type": "split",
      "main": [
        { "type": "header", "icon": "wifi", "eyebrow": "Wi-Fi network",
          "title": "{network_name}" },
        { "type": "badges", "items": [
          { "text": "Guest network", "tone": "accent",
            "when": { "key": "guest_network", "is": "true" } } ] },
        { "type": "secret", "label": "Password", "key": "wifi_password" },
        { "type": "actions", "items": [
          { "label": "Router admin", "key": "router_admin", "kind": "url" } ] }
      ],
      "side": [
        { "type": "qr", "revealWith": "wifi_password",
          "data": "WIFI:T:WPA;S:{network_name|wifi};P:{wifi_password|wifi};;",
          "caption": "Scan with a phone camera to join." }
      ] }
  ]
}
```

### Emergency card

Conditional badges, two grids of facts and call buttons. It demonstrates
conditions, facts that leave out unanswered fields, a divider that appears
only with an emergency contact, and values drawn from the other sections the
template fills.

```json
{
  "version": 1, "id": "emergency", "name": "Emergency card", "accent": "red",
  "match": ["blood_type"],
  "blocks": [
    { "type": "header", "icon": "health", "eyebrow": "Medical emergency card",
      "title": "{full_name}" },
    { "type": "badges", "items": [
      { "text": "Organ donor", "tone": "success",
        "when": { "key": "organ_donor", "is": "true" } },
      { "text": "Blood type {blood_type}", "tone": "danger",
        "when": { "key": "blood_type" } } ] },
    { "type": "facts", "items": [
      { "label": "Allergies", "value": "{allergies}" },
      { "label": "Medications", "value": "{medications}" },
      { "label": "Insurance", "value": "{insurance_provider}" },
      { "label": "Insurance number", "value": "{insurance_number}", "mono": true }
    ] },
    { "type": "divider", "when": { "key": "contact_name" } },
    { "type": "facts", "items": [
      { "label": "Emergency contact", "value": "{contact_name}" },
      { "label": "Relation", "value": "{contact_relation}" },
      { "label": "Doctor", "value": "{doctor_name}" }
    ] },
    { "type": "actions", "items": [
      { "label": "Call {contact_name}", "key": "contact_phone", "kind": "tel" },
      { "label": "Call the doctor", "key": "doctor_phone", "kind": "tel" } ] }
  ]
}
```

### Vehicle

A plate in capitals, the inspection date with a countdown that turns to a
warning 45 days ahead, and a call button for the insurer. It demonstrates
the `upper` filter, `countdown` with `warnDays`, and an action label that
names a value.

```json
{
  "version": 1, "id": "vehicle", "name": "Vehicle", "accent": "blue",
  "match": ["license_plate"],
  "blocks": [
    { "type": "header", "icon": "car", "eyebrow": "{make_model}",
      "title": "{license_plate|upper}" },
    { "type": "countdown", "label": "Next inspection", "key": "inspection_due",
      "warnDays": 45 },
    { "type": "facts", "items": [
      { "label": "Vehicle identification number", "value": "{vin}", "mono": true },
      { "label": "Insurer", "value": "{insurer}" },
      { "label": "Policy number", "value": "{policy_number}", "mono": true }
    ] },
    { "type": "actions", "items": [
      { "label": "Call {insurer}", "key": "insurer_phone", "kind": "tel" } ] }
  ]
}
```

### Medication plan

A record group laid out as a daily schedule, with the next dose and a refill
warning a week before a stock runs out. It demonstrates `group:` in
`match`, record groups, and the `schedule` block with `until`, `next` and
`refill`.

```json
{
  "version": 1, "id": "medication", "name": "Medication plan",
  "accent": "violet",
  "match": ["group:medication"],
  "blocks": [
    { "type": "header", "icon": "medication", "eyebrow": "Medication plan",
      "title": "{patient_name}", "subtitle": "Prescribed by {prescriber}" },
    { "type": "schedule", "group": "medication", "heading": "Medicine",
      "label": "name", "detail": "dose", "note": "note", "until": "until",
      "columns": [
        { "field": "morning", "label": "Morn", "time": "08:00" },
        { "field": "noon", "label": "Noon", "time": "12:00" },
        { "field": "evening", "label": "Eve", "time": "18:00" },
        { "field": "night", "label": "Night", "time": "22:00" } ],
      "next": true,
      "refill": { "stock": "stock", "warnDays": 7 } },
    { "type": "text", "text": "Check with the doctor before changing a dose." }
  ]
}
```

## Safety

A view is a layout written as data, not a program:

- **No code.** A view cannot run scripts or expressions. Placeholders insert
  values; the filters are a fixed list. Calculations such as the next dose
  or a countdown are built into the blocks and only configured by the view.
- **Nothing from outside.** A view loads no images, fonts or addresses.
  Colours and icons come from fixed lists of names.
- **Only records.** Every value comes from a record the viewer may already
  read. A view grants no access: on a public share page it sees only the
  shared records.
- **Hidden stays hidden.** A hidden value appears as dots until revealed in
  a `secret` block; a `qr` that carries it stays covered until then; an
  action never opens a hidden value.
- **Safe links only.** Action buttons open `http`, `https`, `tel` and
  `mailto` addresses and nothing else.

## Limits

- The format is at version 1. A view asking for a newer version is not
  shown, and the section shows its records.
- A block of an unknown type is skipped; the rest of the view is shown. This
  lets a view written for a newer app still show what an older app knows.
- A view that cannot be read (no `id`, an empty `match`, no valid block, or
  JSON that does not parse) is not shown, and the section falls back to its
  records.
