# Revoked

Revoked replaces stale copies of data with a reference that resolves its current value at read time and stops working the moment you revoke it. Everything lives in your own self-hosted instance under your own domain — recipients hold a link, never your data, so what they see is always current and never leaves your control. Shares and Requests are the same revocable contract, each one bound to a cryptographic identity anchored in your domain's DNS, so both sides can prove who is really asking before anyone answers.


## Sections

- **[Setup](setup/index.md)** — running your own server: install, the `.env`
  reference, DNS, reverse proxy, accounts, backups.
- **[API](api/callbacks.md)** — server-side integration: callbacks, public
  endpoints, verification.
- **[APP](app/index.md)** — the client, per platform.

