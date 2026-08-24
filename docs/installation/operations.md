# Operating notes

What a running server records, enforces and — for now — cannot do.

## The audit log

Every request-driven create, update and delete is recorded: who (account or
API key), what changed (before/after snapshots), from where (IP and user
agent). Secret material is redacted before the snapshot is stored — vault
values, submitted gate passwords, collected data, credential tokens — so the
log can answer "what happened" without becoming a second copy of the secrets.

The log is superuser-only, readable through the `/_/` dashboard. Server-side
writes the system makes on its own behalf (notifications, grant
materialisation) are not request-driven and do not appear.

## Built-in limits

| Limit | Value |
|---|---|
| Workspaces per account | 10 |
| Members per workspace | 50 |
| Record value length | 1000 characters |
| File uploads | [Your choice](env.md#files) — per-file and per-workspace budgets |

## The template catalogue

The server ships with a set of
[built-in templates](../guide/templates.md#built-in-templates) and seeds them
on every boot. To change what your instance offers, drop JSON files into a
`templates/` folder next to `pb_data` (or wherever
[`TEMPLATES_DIR`](env.md#storage) points) and restart:

- **One file per template, the filename is its id** — `wifi_guest.json`
  becomes the `wifi_guest` template. A file holding an *array* of templates
  works too; each entry then needs its own `"id"`.
- **A restart syncs the folder.** Changed files update the template in
  place, new files add one, and a removed file deletes it — unless a request
  still references it, in which case the template is kept and a warning is
  logged.
- **Reusing a shipped id overrides that built-in.** Ship your own
  `wifi_access.json` and it replaces the bundled one; delete your file and
  the bundled version returns on the next restart.
- **A malformed file never blocks startup** — it is logged and skipped, and
  the rest of the catalogue loads normally.

A file looks like this:

```json
{
  "name": "Wi-Fi guest access",
  "description": "Shown under the template's name in the app.",
  "schema": {
    "records": [
      { "key": "ssid", "label": "Network name", "type": "text", "required": true },
      { "key": "password", "label": "Password", "type": "text", "format": "hidden" }
    ],
    "sections": []
  }
}
```

`schema` is the same shape the in-app editor's JSON view shows: `records` and
`sections`, each field with a `key`, `label`,
[`type`](../guide/vault.md#records), and optional `format` (`hidden`),
`required`, `reason` and default `value`.

Built-ins belong to no workspace: every workspace sees them, none can edit
them, and workspace templates are never touched by the sync.

## One instance, for now

The challenge/nonce registry, the rate limiters and the file download-token
registry are all in-process. Run exactly one instance of the server; a second
one behind the same proxy would hand out nonces the first cannot honour.

## Callback delivery

Deliveries to [callback URLs](../api/callbacks.md) are at-most-once with no
retry. A failure notifies the request's owner in-app and is otherwise final —
budget for that when wiring anything critical to a callback.
