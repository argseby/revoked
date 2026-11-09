# Works with Revoked

Each file here is one service listed in **Works with Revoked**, the tab in
the app that lists tools and services built on Revoked. Everything the app
shows about a service comes from its file in this folder. A listing is added
or changed only through a pull request, and each one is reviewed by the
project owner.

The service's own domain takes no part in what is shown. It can confirm the
listing with a small proof file, and nothing more. A domain that changes
hands therefore cannot change the texts or permissions of a listing.

## Adding a service

1. A file `services/<slug>.yaml` is added, following the format below. The
   slug is the file name: lower-case letters, digits and dashes.
2. The catalog is rebuilt from the repository root:

   ```bash
   go run ./cmd/works-with build
   ```

   This writes `app/assets/works_with/catalog.json`, which the app bundles
   and reads. CI fails when the two do not match.
3. A pull request with both files is opened. Anyone can open one, including
   people who use a service but do not run it.

The check runs locally as well:

```bash
go run ./cmd/works-with check
go run ./cmd/works-with online -only <slug>
```

## Verified and unverified

A listing without a proof file is shown as **Unverified**: reviewed, but not
confirmed by the service's website. To confirm it, the service serves this
file at `https://<origin>/.well-known/revoked-listing.json`:

```json
{ "listing": "<slug>", "origin": "https://<origin>" }
```

Both values must match the entry exactly. Once the file is in place, a pull
request sets `verified: true`; CI confirms the file before the owner merges.
The file has no other fields. Texts and permissions are never read from it.

To opt out of being listed, the service adds `"listed": false` to the file,
or asks for removal in an issue.

Services built by the Revoked project (`built_by_revoked: true`) count as
verified without a proof file. The flag is accepted only for origins on
revoked.link.

A weekly check fetches every origin and proof file. Findings are collected in
one issue for the owner:

| Finding | What follows |
|---|---|
| Proof file appears and matches | A pull request sets `verified: true` |
| Proof file disappears or no longer matches | The entry is set back to `verified: false` and reviewed again |
| `"listed": false` | The entry is removed |
| Origin does not answer | `status: unavailable`; removed after 30 days |

## Format

```yaml
schema: 1
slug: example                       # the file name, without .yaml
origin: https://tool.example.org    # https, lower-case, no path. Identifies the service.
name: Example                       # up to 40 characters
description:                        # up to 280 characters each, both required
  en: What the service does, in one or two sentences.
  de: Was der Dienst tut, in ein oder zwei Sätzen.
operator:
  name: Example GmbH
  imprint: https://tool.example.org/imprint     # where the law requires one
  security: mailto:security@example.org         # or an https:// page
privacy_policy: https://tool.example.org/privacy
website: https://tool.example.org/start         # optional, on the origin
source: https://github.com/example/tool         # optional
self_hostable: false
servers: []                         # empty: works with every Revoked server
languages: [de, en]                 # en, de
pricing: free                       # free, paid or freemium
categories: [work]                  # health, housing, work, finance, games, developer, other
does: [share, connect]              # share, collect, prove, sign_in, connect
proposes:                           # what it proposes in the app
  shares:
    templates: [Tenant application]
    keys: [full_name, email]
  requests:
    templates: [Employee onboarding]
permissions:                        # every switch it may ask for when it connects
  - key: revoke_links
    reason:
      en: Removing an entry revokes its link.
      de: Ein entfernter Eintrag widerruft seinen Link.
stores:                             # what it keeps on its own servers
  en: Nothing from the vault.
  de: Nichts aus dem Tresor.
maintainers: [github-account]       # who may propose changes for the service
built_by_revoked: false             # only for origins on revoked.link; counts as verified
verified: false                     # set by the owner once the proof file matches
status: listed                      # listed or unavailable
reviewed: 2026-11-09                # set by the owner when merging
```

Permission keys: `section`, `read_vault`, `revoke_links`, `receive_links`,
`shares:read`, `shares:manage`, `requests:manage`, `attestations:issue`,
`vault:read`, `vault:write`. When a service asks for a switch its entry does
not list, the app points it out and leaves that switch off.

## Requirements

A listing must:

1. Use only the documented flows: link proposals, connect, sign-in, requests,
   attestations and checks. People are never asked to paste vault values
   where a proposal would do.
2. List every permission it asks for, with a reason. Asking for more than
   listed is grounds for removal.
3. Ask for `read_vault` only with a reason the review accepts. A service that
   works without it does not ask for it.
4. Keep no vault values on its servers beyond what `stores` says.
5. Work with any Revoked server, or name the ones it works with in `servers`.
   It does not hard-code `api.revoked.link`.
6. Handle a declined proposal and a revoked link with a clear message.
7. Run on a stable https origin. A new domain is a new listing.
8. Name an operator, with an imprint where the law requires one, a privacy
   policy and a security contact.
9. Not present itself as part of Revoked unless it is.
10. Carry no trackers or ads on the pages where the Revoked flow happens.
11. Describe itself in English and German.

A listing should be open source and self-hostable where that fits, revoke
its own links once they are no longer needed, and use the built-in templates
where one fits.

Not listed are services whose main purpose is collecting data about people
for third parties, and services that send requests in someone's name at
scale.

Paid services are listed on the same terms as free ones.
