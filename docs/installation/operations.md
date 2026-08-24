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

## One instance, for now

The challenge/nonce registry, the rate limiters and the file download-token
registry are all in-process. Run exactly one instance of the server; a second
one behind the same proxy would hand out nonces the first cannot honour.

## Callback delivery

Deliveries to [callback URLs](../api/callbacks.md) are at-most-once with no
retry. A failure notifies the request's owner in-app and is otherwise final —
budget for that when wiring anything critical to a callback.
