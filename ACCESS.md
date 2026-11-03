# One access model for everything that isn't the app — design

## 1. Summary

Today every way into revoked from code has its own rules. An API key gets
scopes but never the vault. A connected tool gets three switches
(`allowRevoke`, `allowHandOver`, `allowVaultRead`), and it may only *propose*
shares, never create them. The MCP server is a connected tool with
`allowVaultRead` set. A sign-in is a fourth kind of thing again. Each one was
right when it was added. Together they are four answers to the same
question: *what may this credential do, and on which data?*

This design gives every credential the same two-part answer:

- **Permissions**: what it may do, from the one catalogue in
  `util/permissions.go`.
- **Reach**: which vault data it may do that to: **none**, **sections**, or
  **the whole vault**.

| Decision | Choice | Why |
|---|---|---|
| Permissions | One catalogue for people, API keys and connections | A second list drifts, and the app already serves this one from `GET /api/permissions` |
| Vault reach | `none`, `sections` or `all`, stored on the credential | Lets a service keep data with you without seeing the rest of the vault |
| Whole vault | Only a person, or a connection answered on the owner's own machine | The MCP case is the only one where the owner and the reader are the same machine. Anything reachable by phishing gets less |
| A connected service | Gets its own section at connect, and may read, write and upload files there | "Your vault, its section": the service keeps its data with you, and you can share, pause or delete it like anything else |
| An API key | May be given sections, never `all` | Fixes the Steam example (one record kept current) without handing a pasted string the vault |
| Where reach is checked | In Go, on one route family, not in collection rules | Rules can't reliably join through `sections.records` (CLAUDE.md, *Do not match member permissions inside a rule*), and a reach check written twice drifts |
| What a service may change | Only records it wrote. Records the owner adds to its section are read-only to it | Adding a record to a section should never let a service overwrite it |
| On disconnect | The section and its records stay the owner's | The same rule as everything a tool proposed today |

---

## 2. Goals and non-goals

**Goals**

- One way to answer "what can this credential do?". The answer is the same
  pair (permissions, reach) everywhere, including in the app's settings.
- A connected service can **keep data in the owner's vault**: write records,
  upload files, keep them current, and read them back. It cannot see anything
  outside its reach.
- Within its reach, a credential can do **everything its permissions allow**:
  create shares and requests directly instead of proposing them, not only
  watch what the owner made of a proposal.
- The whole-vault grant stays what it is today: an MCP assistant the owner
  runs on their own machine, after a warning.

**Non-goals**

- Encrypted (sealed) records. The server can't read them, so no reach can
  include their values (invariant 13). A sealed record inside a reached
  section looks missing, exactly as `GET /api/connection/vault/{id}` treats
  it today.
- Things only a person may do: passkeys, deleting the account, inviting or
  removing members, and the encryption device list. Those stay members-only
  whatever the permissions say (`MembersOnly` in the catalogue already marks
  them, plus the account routes that check for a `users` session).
- Changing what a public slug can do. A share or request link stays a
  capability on its own, outside this model.

---

## 3. Today

| Credential | Header | Permissions | Vault | Creates directly |
|---|---|---|---|---|
| App session | `Authorization: Bearer` | per workspace membership | all of the person's | everything |
| API key | `X-API-Key` | scopes from the catalogue, fixed at creation | never (`api_key_vault_scope`) | shares, requests, templates, … through the collection API |
| Connected tool | `X-Revoked-Connection` | `allowRevoke`, `allowHandOver` | `allowVaultRead`: read-only, all of it, refused for a polled token | nothing: it proposes `revoked://` links |
| MCP assistant | same as a tool | same as a tool | as a tool, with the loopback `/callback` so it is never polled | nothing |
| Sign-in (OIDC) | its own tokens | the claims the person chose | what the person chose to share at sign-in | nothing |

The connection already has the hard parts this design needs: PKCE, the
owner's approval in the app, pause and resume, the 90-day expiry, a
per-connection rate limit on vault reads, and an audit row for every record
read (`auditToolReadRecord`).

---

## 4. The model

A credential is **who holds it**, **what it may do** and **where**.

```
credential
  holder       person | api key (the workspace's own script) | connection (a tool someone runs)
  permissions  keys from util.Permissions, expanded to scopes when granted
  reach        none | sections | all
  sections     the sections it reaches, when reach = sections
```

A request is allowed when the credential holds the scope for the action *and*
every record or section the action touches is within its reach. Things a
credential created itself — shares, requests, attestations, checks — are
within its reach, as a tool's proposals are within its connection today.

| Holder | May hold `all` | Default reach | Notes |
|---|---|---|---|
| Person | yes | `all` | Unchanged. |
| Connection, answered on the owner's machine (`Poll = false` and a loopback client) | yes, after the warning | `sections` (its own) | This is today's MCP case. |
| Connection, answered by polling or redirect to a remote origin | no | `sections` (its own) | Phishing can reach this. What it gets is a section the attacker would have to fill themselves. |
| API key | no | `none` | The owner picks sections when creating the key. |

### 4.1 A service's own section

At connect, a tool that asks for it gets one new section in the owner's
workspace, named after the tool (`clientName`), keyed from it with a suffix
when the key is taken. The connection records it in `connections.sections`.

- **Writing.** The tool creates records and files in its section through the
  route family in §5. Each one carries `writtenBy` (the connection). The app
  shows the tool's name on those records, so a service can't slip a record
  called "Bank details" into the vault that passes as the owner's.
- **Reading.** The tool reads everything in its section: what it wrote, and
  what the owner added.
- **Changing.** The tool may update or delete only records whose `writtenBy`
  is its connection. What the owner adds is read-only to it.
- **The owner adds a record.** Adding an existing record to a tool's section
  is a grant, and the app confirms it in those words before saving, with the
  tool's name and origin. Removing it from the section removes the tool's
  access on the next request. Nothing is cached on the server.
- **More sections.** The owner may give a connection further sections from
  **Settings → Connected tools**. The tool can read those and can't change
  anything in them.
- **Disconnect.** The connection ends. The section and every record in it
  stay the owner's. `writtenBy` stays as history.

A record can sit in several sections (`sections.records` is many-to-many),
which is what makes adding one a grant. That is the reason reach is checked
per request rather than copied anywhere.

### 4.2 Everything else within reach

With the matching permission, a connection may:

- **create shares** of records and sections within its reach. The existing
  rule that a share holding a hidden record or a file is never *handed over*
  to a tool becomes unnecessary inside the tool's own reach (it can already
  read them). It still applies to anything outside it.
- **create requests**, whose answers land in the owner's workspace as today
  (invariant 12 holds: the responder still manages their side). Reading
  those answers needs `responses:read`, and the consent screen says it hands
  other people's answers to the tool.
- **issue attestations and checks**, as it proposes them today.
- **end** what it created — today's `allowRevoke`.

Proposals (`revoked://p`, `pr`, `attest`, `check`) stay. They remain the way
for a tool with no connection, and for one that wants the owner to choose the
values.

---

## 5. API

One route family for every non-person credential, under `/api/vault` for data
and the existing collection API for the rest. The handler resolves the
credential (API key or connection), its permissions and its reach, and
checks both in Go.

| Route | Does | Needs |
|---|---|---|
| `GET /api/vault` | Records within reach: `id`, `key`, `label`, `type`, `format`, `updated`, `section`, `writtenBy`. No values. | `vault:read` |
| `GET /api/vault/{id}` | One record with its value, or a file's metadata | `vault:read` |
| `GET /api/vault/{id}/file` | The file's bytes | `vault:read` |
| `POST /api/vault` | Create a record or upload a file into one of its sections | `vault:write` |
| `PATCH /api/vault/{id}` | Change a record it wrote | `vault:write` |
| `DELETE /api/vault/{id}` | Delete a record it wrote | `vault:write` |

`GET /api/connection/vault` and `/{id}` become aliases of the first two for
a connection with reach `all`, so `revoked-mcp` keeps working unchanged.

`vault:read` and `vault:write` lose `MembersOnly` and gain a rule instead:
**a non-person credential holds them only together with a reach that isn't
`all`**, except the loopback connection. `MembersOnlyScopes` turns into a
check on (scope, reach) rather than on the scope alone.

The collection API keeps serving people. For API keys, record and section
rules stay as they are (no vault scopes), so the reach check never has to be
expressed as a PocketBase filter.

### Connect link

`revoked://connect` and `revoked://p` gain:

| Parameter | Meaning |
|---|---|
| `scopes` | Comma-separated permission keys the tool asks for. Replaces nothing yet: `allowRevoke` and `allowHandOver` keep their own parameters until §8 phase 3. |
| `section` | Asks for its own section. `1`, or a template name to shape it. |
| `section_reason` | Why, up to 120 characters, shown like `revoke_reason`. |

`vault=1` (whole vault) keeps its current meaning and conditions.

### Storage

Before the first write, check that the tool's section would stay under a
per-connection cap (`CONNECTION_STORAGE_MB`, default to be decided), across
its files and values. Values written by a tool go through the same validation
as the app's. File uploads use the existing file path and its size limit.

---

## 6. Security

- **Reach is checked on every request in Go**, never cached, never in a rule.
  Proposed invariant 15: *a non-person credential reaches the vault only
  through `/api/vault`, which checks reach per record on every request; only
  a person, or a connection answered on the owner's own machine, may hold
  reach `all`.*
- **Polling can never yield `all`.** Unchanged from today
  (`vaultReadable`). A polled connection may get its own section.
- **A tool can't write outside its section** and can't change what it didn't
  write. A record's `writtenBy` is set by the server and immutable.
- **Records a tool wrote are labelled** with the tool's name wherever the
  owner sees them, and in shares the owner makes of them.
- **Audit.** Every read is already audited by key. Writes go through the
  audit hook, so `util.RedactAuditData` applies, and a new secret-bearing
  field joins its catalogue (invariant 10).
- **Rate limits.** The 120-per-minute read limit applies per connection, and
  a write limit is added beside it.
- **Errors** name the missing scope or that a record is outside reach. They
  never name the section or record a credential *could* reach (invariant 9).
- **Sealed records** within reach behave as missing, for reads and writes.

---

## 7. In the app

Shipped words to reuse: **Connected tools**, **Read your vault**, **End what
it proposed**, **section**.

- **Connect sheet.** Lists what the tool asks for, as the permission labels
  `GET /api/permissions` already serves, plus one row for its section:
  "Keep its own section in your vault". **Read your vault** stays a separate,
  off-by-default switch with today's warning, offered only when the
  connection allows it.
- **Settings → Connected tools.** Each tool shows its permissions and its
  sections, where the owner can open the section, add another one, or take
  one away. API keys move onto the same screen in phase 4.
- **Vault.** A record a tool wrote shows the tool's name. Adding a record to
  a tool's section asks first.
- **Sharing.** A section a tool reaches says so, so the owner knows a share
  of it includes what the tool writes.

---

## 8. Phases

1. **Own section for connections.** `connections.sections`, `records.writtenBy`,
   `/api/vault` with reach `sections`, the connect parameters, the app's
   connect sheet and labels, and `revoked-mcp` tools to read and write its
   section. Tests in the style of `tests/connectionVault_test.go`.
2. **Sections for API keys.** Pick sections when creating a key, use
   `/api/vault`. Rewrite `examples/steam_now_playing.py` to use it.
3. **One permission list for connections.** `scopes` on the connect link.
   Fold `allowRevoke` and `allowHandOver` into permissions with a migration
   that converts existing connections. Let connections create shares and
   requests within reach.
4. **API keys as connections.** An API key becomes a connection the owner
   creates in Settings, with the token shown once and no PKCE. `X-API-Key`
   stays accepted as an alias. One table, one settings screen.

Each phase ships on its own, and the docs change with it: a **Ways to
connect** page in `docs/api/`, a guide section on a tool's own section, and
`docs/api/authentication.md`'s "Choosing a credential" table rewritten
around (permissions, reach).

---

## 9. Open questions

1. **Sign-ins.** A sign-in already appears under **Connected tools** and
   shares data as a living grant. Should it become a connection with reach
   too, so a game can keep a save file in your vault? It fits the model, but
   it needs OIDC tokens to map onto connections.
2. **Answering requests from a tool.** Within reach, a tool could answer a
   request on the owner's behalf: the answer still lands in the owner's
   workspace, which keeps invariant 12 in spirit. The invariant's wording
   ("requires a `users` JWT") would have to change. In or out?
3. **Storage cap.** A size, and whether files and values count together.
4. **Several sections per tool.** Is "its own section plus any the owner
   adds" enough, or should a tool be able to ask for named sections ("save
   games", "settings")?
5. **Disconnect.** Should the app offer to delete what the tool wrote, or
   always keep it?
6. **Templates.** If `section` names a template, does the app create the
   template's records up front, or only when the tool writes them?

---

## 10. As built

Where the build differs from the design above:

- **The storage cap** is `CONNECTION_STORAGE_MB`, default 100, files and values
  together, per key or tool. 0 means no cap (§9, question 3).
- **Reach is stored beside the credential**, not as `vault:*` scopes:
  `vaultAccess` (`read` or `write`) and `sections` on both keys and
  connections, plus a connection's own `section`. A key's record scopes would
  be honoured by the collection rules across the workspace (invariant 15).
  `vault:read` and `vault:write` stay the permission keys people pick; the
  server turns them into `vaultAccess`.
- **`allowRevoke` and `allowHandOver` are gone as fields.** A migration turned
  them into exactly the scopes they stood for: `link:update`,
  `request:update`, `attestation:update` for ending, and `link:read` for
  receiving links. The API still reports both, derived from the scopes, and
  still accepts them, so older tools and apps keep working.
- **A tool may hold** `shares:read`, `shares:manage`, `requests:manage`,
  `attestations:issue`, `vault:read` and `vault:write`, the catalogue entries
  its routes act on. Members, templates, contacts and settings stay with
  people and keys.
- **Asking for its own section asks for `vault:write`.** It works over
  polling too: the section starts empty, so a phished connect reaches nothing
  the owner had.
- **A request a tool creates** asks as the identity it names, or the
  workspace's primary identity. It is refused to a token collected by
  polling (`connection_polled`), like the whole vault: a request asks
  strangers for data in the owner's name, and whoever sent the connect link
  can read the owner its check code. A share stays allowed, since it holds
  only what the tool could read anyway.
- **`/api/connection/vault`** answers exactly as `/api/vault`.
- **Phase 4 is one model and one screen, not one table.** Keys and
  connections share the permission catalogue, the reach fields and the
  resolver behind `/api/vault` (`services.Credential`), and the app manages
  them together. A key is still an `apiKeys` row: it authenticates as a
  PocketBase auth record, which is how the collection rules admit it to
  shares, requests, templates and the rest. Turning keys into connections
  would take every one of those rules with it.
- **Answering requests from a tool** (§9, question 2) and **sign-ins as
  connections** (question 1) are not built.
