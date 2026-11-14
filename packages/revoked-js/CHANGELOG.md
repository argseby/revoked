# Changelog

## Unreleased

- A credential option that is present but empty, such as
  `apiKey: process.env.REVOKED_API_KEY` with the variable unset, is refused
  when the client is created instead of sending every call without a
  credential. The options accept `string | undefined` for that reason.

## 0.1.0

- First release: the `Revoked` client for API keys, connected tools and
  sessions. It covers shares, requests, templates, vault records and
  sections, identities, attestations, credentials, contacts, workspaces,
  members, invites, groups, API keys, notifications, connections, sign-ins,
  webhooks and grants.
- `@kiunke.dev/revoked/public`, `connect`, `webhooks`, `identity`, `trust` and
  `sealed` entry points.
