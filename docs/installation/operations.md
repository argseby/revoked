# Day-to-day running

What your server records, what it limits, and what it can't do yet.

## Read the audit log

Every create, update and delete made through a request is logged: who did it
(account or API key), what changed (before and after), and from where (IP and
user agent). Secrets are blanked out before anything is stored — vault values,
submitted gate passwords, collected data, credential tokens. So the log tells
you what happened without becoming a second copy of your secrets.

What a connected tool does is logged under the `connections` collection, by
the tool's origin:

- `tool_authorized` — the owner connected or renewed it.
- `tool_browser_added` — the app let another of the owner's browsers into a
  connection that was already live, without asking again and without
  renewing it.
- `tool_connected` — a browser exchanged its code for a token.
- `tool_read` — it read where its links stand. One entry per ten minutes of
  use, not one per request.
- `tool_revoked_link` — it revoked one of its links, named in the row.
- `tool_permission_changed` — the owner allowed or stopped that.
- `tool_disconnected` — it disconnected itself.

When the owner disconnects a tool, that's an ordinary `delete`.

Only the superuser can read the log, in the `/_/` dashboard. Writes the server
makes on its own (notifications, grant materialisation) don't come from a
request, so they don't appear.

## Built-in limits

| Limit | Value |
|---|---|
| Workspaces per account | 10 |
| Members per workspace | 50 |
| Record value length | 1000 characters |
| File uploads | [Your choice](env.md#files) — per-file and per-workspace budgets |

## The template catalogue

Your server comes with a set of
[built-in templates](../guide/templates.md#built-in-templates) and loads them
on every boot. To change what your server offers, drop JSON files into a
`templates/` folder next to `pb_data` (or wherever
[`TEMPLATES_DIR`](env.md#storage) points) and restart:

- **One file per template; the filename is its id.** `wifi_guest.json`
  becomes the `wifi_guest` template. A file can also hold an *array* of
  templates; then each entry needs its own `"id"`.
- **A restart syncs the folder.** A changed file updates its template, a new
  file adds one, and a removed file deletes it. If a request still uses that
  template, it's kept and a warning is logged.
- **Use a shipped id to replace that built-in.** Add your own
  `wifi_access.json` and it replaces the bundled one. Delete your file and the
  bundled one comes back on the next restart.
- **A broken file never stops startup.** It's logged and skipped, and the
  rest of the catalogue loads as usual.

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

`schema` has the same shape the in-app editor's JSON view shows: `records` and
`sections`. Each field has a `key`, a `label`, a
[`type`](../guide/vault.md#records), and optionally `format` (`hidden`),
`required`, `reason` and a default `value`.

Built-ins belong to no workspace. Every workspace sees them, none can edit
them, and the sync never touches workspace templates.

## Run only one instance

The challenge/nonce registry, the rate limiters and the file download-token
registry all live in the server's memory. Run exactly one instance. A second
one behind the same proxy would hand out nonces the first can't honour.

## Callbacks are sent once

Each delivery to a [callback URL](../api/callbacks.md) is tried at most once,
with no retry. If it fails, the request's owner gets an in-app notification,
and that's it. Keep this in mind before you hang anything critical on a
callback.
