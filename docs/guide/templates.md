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

Some templates ship read-only; duplicate one to make it yours.
