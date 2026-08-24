# Templates

A template is a blueprint: sections and fields, each with a key, label, type
and format. One template serves both directions of the product —

- a [request](requests.md) uses it to say what responders should fill in,
- the vault's *From template* uses it to
  [materialise the same structure](vault.md#starting-from-a-template) as real
  sections and records in one step.

## Authoring

The editor has two faces of the same template: a **visual builder** (add
section, add field, reorder) and a **raw JSON view**, and edits round-trip
between them — build visually, fine-tune as JSON, or paste a template someone
sent you.

Per field you choose the [type](vault.md#records), and two flags:

- **Required** — a request built on this template refuses submission without
  it.
- **Hidden** — values land as masked records, for fields that collect
  secrets.

## Built-in templates

Every server ships with a catalogue of ready-made templates — Wi-Fi access,
API credentials, personal information, employee onboarding and more — so the
template list is never empty on a fresh install. They appear in every
workspace, marked **Built-in**, and work everywhere a template does: pick one
when [creating a request](requests.md) or under the vault's
[*From template*](vault.md#starting-from-a-template).

Built-ins are read-only — no one can edit or delete them, not even a
workspace admin. For a variant, create a workspace template of your own with
the fields you want. If you run the server yourself, you can also
[change the catalogue](../installation/operations.md#the-template-catalogue)
for the whole instance.
