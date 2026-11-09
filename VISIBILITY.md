# Who sees what inside a workspace — design

## 1. Summary

Inside a workspace, almost everything a member creates is visible to that
member alone. Records, sections, shares and requests are read through
self-only rules. Writes are wider: any member holding the matching manage
permission passes the rule, whoever owns the row. The only way to show vault
data to other members is a section shared with members, served by its own
route (`/api/shared/vault`). Templates, contacts and attestations, on the
other hand, are visible to the whole workspace.

This design gives every item an **audience** and an **editing** setting, set
on the item itself, with one widget for it everywhere in the app:

- **Audience**: who sees the item. `private` (the owner), `workspace` (every
  member), or `groups` (members of the named groups). Groups aren't built
  yet, but the stored shape already allows for them, so adding them later is
  new UI and one new collection, not a migration of every item.
- **Editing**: who may change, pause, end or delete it. `owner`, or
  `audience` (members who see it and hold the area's manage permission).

| Decision | Choice | Why |
|---|---|---|
| Where visibility lives | On each item, not as workspace-wide switches | A company's 50 members share one vault but not each other's links. A switch per area can't express that |
| Shape | `audience {kind, groups[]}` from the first migration | Groups (HR, Service, Techs) are planned. A two-value flag would need a second migration across every collection |
| Permissions | Still required on top of the audience | Being in the audience of a share is not the same as being allowed to view shares. Both must hold |
| Edit | Owner, plus the audience with the manage permission when the owner allows it | Fixes today's gap where members can change rows they can't see |
| Changing the audience | The owner only, from the app (admins for items whose owner has left) | The same rule that holds for shared sections today |
| Source of truth | One Go function pair, `CanSee` / `CanEdit` | One answer, used by rules, routes, keys, tools and webhooks alike |
| How rules enforce it | Server-maintained `readers` / `editors` on each row, matched by the rule | Rules can't reliably join through multi-value columns (`util/rules.go`). Filtering lists in hooks breaks pagination and totals |
| Workspace defaults | A default audience per area, used to pre-fill new items | Families and companies want different starting points. A default never grants access by itself |
| Tools | May suggest an audience. What a tool creates directly is private until the owner widens it | A connect link can be phished. Widening who sees something stays a person's act |
| Migration | Everything starts as it is seen today | Nobody sees anything new on the day it ships |

---

## 2. Goals and non-goals

**Goals**

- One model for who sees and who edits, across records, sections, shares,
  requests and their answers, templates, attestations and contacts.
- Private work and shared work side by side in the same workspace.
- Reads and writes that agree: an item that can't be seen can't be changed.
- API keys, connected tools and webhooks bound by the same answer as people.
- A stored shape that takes groups without migrating existing items.
- An exhaustive test matrix, so the answer is checked rather than assumed.

**Non-goals**

- Groups themselves: the `groups` collection, managing membership, and the
  group option in the widget. §6 describes how they slot in.
- Visibility per record. The vault's unit stays the section (§4.2).
- Encryption keys per audience. Encrypted records stay under the
  workspace key in this design; see §12, question 2.
- Public links and request links. A link stays a capability on its own for
  whoever holds it, as in [ACCESS.md](ACCESS.md).
- Personal data that has no workspace dimension: bookmarks, reminders,
  credentials, attestation checks, sign-ins, contact blocks. These stay
  owner-only.

---

## 3. Today

| Data | Read | Write |
|---|---|---|
| Records, sections | owner only (`legacyWorkspaceSelfOnly`) | any member, permission checked by `BindAccessPreflight` |
| Shares (links), requests | owner only | any member, permission checked |
| Request answers | owner of the request (records with `requestedBy`) | any member with `responses:manage` |
| Shared sections | members with `vault:read`, through `/api/shared/vault` only | unchanged: any member with `vault:write` |
| Templates | every member | admins |
| Contacts | every member | any member, permission checked |
| Attestations | every member with `attestations:read` | holders of `attestations:issue` |
| Identities, notifications | owner only | owner |

Three consequences drive this design:

1. **Writes reach further than reads.** A member with `vault:write` can
   change or delete another member's record by id without being able to
   list it.
2. **Read permissions barely apply to people.** Reads are self-only and
   owners always keep their own rows, so `shares:read` ("See the shares this
   workspace has issued") shows a member nothing beyond their own.
3. **API keys see across members.** The key branch of each rule checks only
   the workspace and the scope. A key with `link:read` sees every member's
   shares, more than its creator sees in the app.

---

## 4. The model

### 4.1 Fields

Every item in a participating collection carries:

```
user        owner (exists today)
audience    { kind: "private" | "workspace" | "groups", groups: [groupId] }
editing     "owner" | "audience"
readers     [userId]   server-maintained, never written by a client
editors     [userId]   server-maintained, never written by a client
```

`audience` is stored as two columns, `audienceKind` (select) and
`audienceGroups` (relation, empty until groups exist), so rules and indexes
can use them directly.

`groups` with an empty list behaves as `private`. A group that is deleted
drops out of every list it appears in; an item left with no group falls back
to the owner alone. The audience only ever narrows by accident, never widens.

### 4.2 Which item carries the audience

| Area | Unit with an audience | Notes |
|---|---|---|
| Vault | the **section** | A record is seen by its owner and by everyone who sees any section holding it. Records in no section are private |
| Files | as records | A file record follows its sections like any other record |
| Aliases | as records, narrowed by the parent | An alias is visible only to members who could also see the record it reads through |
| Shares | the share | Its record list shows only the records the viewer can see; the rest are counted, not named |
| Requests | the request | |
| Answers | follow their request | Records with `requestedBy` have no audience of their own |
| Templates | the template | Built-in templates stay visible to everyone |
| Attestations | the attestation | |
| Contacts | the contact | |

A record sits in several sections (`sections.records` is many-to-many), so
adding a record to a section is a grant. Two rules keep that honest:

- A record may be added only to sections its owner may edit.
- A section whose audience is wider than `private` holds only records its
  owner created, as `/api/shared/vault` already requires today.

### 4.3 The two answers

```
CanSee(member, item) =
    member is item.owner
 || ( member is in item.audience
      && member holds the area's read permission )

CanEdit(member, item) =
    member is item.owner
 || ( item.editing == "audience"
      && CanSee(member, item)
      && member holds the area's manage permission )
```

- "In the audience": `workspace` means any current member; `groups` means a
  member of at least one listed group.
- Ending, pausing, renaming and deleting are all edits.
- Changing `audience` or `editing` is not an ordinary edit: only the owner
  may, and only with a person's session. When the owner is no longer a
  member, members holding `members:remove` may.
- For answers, the request's audience applies, with `responses:read` and
  `responses:manage` as the permissions.

### 4.4 Workspace defaults

`workspaces.defaultAudience` holds one audience per area. New items are
pre-filled from it, in the app and for API keys. The owner can change the
pre-filled value before saving. A default never changes existing items, and
never grants anything by itself: the area's permission still applies.

Suggested defaults for a new workspace: vault sections `private`, shares
`private`, requests `private`, templates `workspace`, attestations
`workspace`, contacts `workspace`. A personal workspace with one member never
notices the difference.

---

## 5. Enforcement

### 5.1 One source of truth

`services.Access` holds `CanSee` and `CanEdit`, plus `Readers(item)` and
`Editors(item)`, which list every member for whom the answer is yes. Nothing
else decides visibility. Every route, hook and resolver calls into it.

### 5.2 Materialized for the rules

The collection API and its rules stay the way the app reads data. Rules
can't evaluate permissions or join through multi-value columns reliably, and
filtering a list in a hook after the query breaks pages and totals. So the
answer is stored on each row:

- `readers` and `editors` hold user ids, at most 50 (the member cap).
- Read rules become: owner, or `readers ?= @request.auth.id`, inside the
  active workspace.
- Write rules become: owner, or `editors ?= @request.auth.id`.
- A hook rejects any client write to `readers`, `editors`, and to
  `audience` / `editing` from anyone but the owner.

`readers` / `editors` are a cache of `services.Access`, and are recomputed:

| Change | Rows recomputed |
|---|---|
| An item's audience or editing changes | that item (and, for a section, the records it holds; for a request, its answers) |
| A record is added to or removed from a section | that record |
| A member joins | items with audience `workspace` in that workspace |
| A member leaves or is removed | every item in that workspace listing them |
| A member's permissions change | items in the areas whose permission changed |
| A group's members change (later) | items naming that group |
| A group is deleted (later) | items naming that group |

Each recompute runs inside the transaction of the change that caused it, so
a permission withdrawal and the loss of access commit together, as sealed
access already does in `hooks/workspaceMembers.go`.

Two checks keep the cache honest:

- **A consistency test** builds random workspaces, applies random changes,
  and asserts after each that every row's `readers` / `editors` equal what
  `services.Access` computes.
- **A startup check** recomputes a sample of rows (all of them in dev) and
  logs any mismatch at error level before serving.

### 5.3 API keys

A key acts as its creator, narrowed by its scopes. The key branch of each
rule becomes `readers ?= @request.auth.user` (or `editors` for writes), plus
the scope test it has today. A key therefore never sees more than the person
who made it, and loses access when they do. The vault keeps its separate
reach model from [ACCESS.md](ACCESS.md); within its sections, a key also
sees only what its creator sees.

New items created by a key take the workspace default for their area.

### 5.4 Connected tools

`services.Credential` gains the connection's user as the subject of
`CanSee` / `CanEdit`, intersected with its reach. A tool's own section stays
private to its owner unless the owner widens it.

What a tool creates directly (shares, requests, attestations) is always
`private`, whatever the workspace default. Only the owner widens it, in the
app.

### 5.5 Routes that read outside the rules

Every route that loads workspace data with `FindRecordsByFilter` or
`FindRecordById` on behalf of a member, key or tool calls `services.Access`
before returning it. Today that includes, at least:

- `routes/vault.go`, `routes/sharedVault.go` (folded away in phase 1)
- `routes/ownerFiles.go`, `routes/connectionGrants.go`, `routes/connections.go`
- `routes/requestGrants.go`, `routes/contactGrants.go`, `routes/remoteGrants.go`
- `services/webhookEvents.go`, `services/notifications.go`

Public routes (`publicLinks.go`, `publicRequests.go`, `publicShort.go`,
`publicFiles.go`, `publicDav.go`) are unaffected: they serve whoever holds
the link.

### 5.6 Webhooks and notifications

- **Webhooks** act as the member who created the endpoint. An event about an
  item is sent only when that member could see the item at the time of the
  event.
- **Notifications** go to the owner, as today. Notifying the rest of the
  audience (for example HR when an onboarding request is answered) is
  §12, question 3.

### 5.7 Rule shape

For records, read (the user branch, simplified):

```
@request.auth.collectionName = 'users'
&& workspace = @request.auth.activeWorkspace
&& ( user = @request.auth.id || readers ?= @request.auth.id )
```

The membership join stays as it is today, so a removed member is refused
even before a recompute lands. `util.CollectionAccess` gains the new kinds,
and `TestAccessRegistryMatchesRules` keeps the registry and the deployed
rules byte-identical.

---

## 6. Groups, later

The model already carries everything groups need. Adding them takes:

- `groups` (`workspace`, `key`, `name`) and `groupMembers` (`group`, `user`).
- Managing groups with `members:add` / `members:remove`.
- `services.Access` treating `audience.kind = groups` as "member of any
  listed group".
- The recompute triggers for group changes from §5.2.
- The group option in the access widget, and groups in the proposal
  parameter (§7).

No existing item changes, and no rule changes: rules only match `readers`.

---

## 7. Proposals and connected tools

Proposal links (`revoked://p`, `revoked://pr`, `revoked://attest`,
`revoked://check`) gain one optional parameter:

| Parameter | Values | Meaning |
|---|---|---|
| `visibility` | `private`, `workspace`, `group:<key>` (comma-separated for several groups) | Pre-fills the audience on the proposal screen |

- The value is a suggestion. The owner sees it in the access row, marked as
  suggested by the tool, and saves whatever the row shows when the proposal
  is confirmed.
- A value wider than the workspace default is shown with a note to that
  effect.
- An unknown group key falls back to the workspace default, with a note.
- Before groups exist, `group:` values fall back the same way.

The same parameter is accepted by the MCP server in `cmd/revoked-mcp` (`mcpserver/proposals.go`), which builds
proposal links.

---

## 8. In the app

### 8.1 One widget

`AccessControl` is the only place an audience is chosen or shown. It comes in
three sizes:

- **Full**, as the **Access** tab on every detail screen of a participating
  item: audience options, editing options, and a summary line ("Visible to
  14 members · editable by the owner") with the list of members behind it.
- **Row**, a single "Visible to" row in create sheets and proposal screens,
  pre-filled from the workspace default or the tool's suggestion.
- **Badge**, a small icon on list rows: lock for private, building for the
  workspace, group icon for groups.

The member list behind the summary comes from
`GET /api/access/{collection}/{id}`, which returns names and counts computed
by `services.Access`. Members without `members:read` see counts only.

### 8.2 Screens

- Vault: section detail gains the Access tab; the **Share with members** menu
  item and the **Members** badge are replaced by it. Sections shared by
  others keep the **Shared by** label.
- Shares, requests, templates, attestations, contacts: Access tab on detail,
  row in the create sheet, badge on list rows, a **Visible to** filter in the
  existing filter dialogs.
- Request answers: show the request's audience, read-only.
- Proposal screens for shares, requests, attestations and checks: the row,
  with the tool's suggestion.
- Settings → Workspace: **Default visibility for new items**, one row per
  area.
- Connected tools and API keys: a line stating that they see what their
  owner sees, within their permissions and sections.

### 8.3 Words

Copy follows the app's descriptive voice:

| Place | Text |
|---|---|
| Private | "Seen by the owner only." |
| Workspace | "Seen by every member who can view shares." (area name varies) |
| Groups | "Seen by members of the selected groups." |
| Editing, owner | "Others can open it but not change, pause or end it." |
| Editing, audience | "Pausing, ending and editing are open to them." |
| Tool suggestion | "Suggested by the tool." |
| Wider than default | "Wider than the workspace default." |
| Defaults page | "New items start with these settings. Existing items keep theirs." |

---

## 9. Migration

| Data | Starts as | Editing |
|---|---|---|
| Records, sections, shares, requests | `private` | `owner` |
| Sections with `shared = true` | `workspace` | `audience` (matches today's documented behaviour) |
| Templates | `workspace` | `audience` (today only admins edit them; holders of `templates:manage` would, after this) |
| Contacts | `workspace` | `audience` |
| Attestations | `workspace` | `audience` |

Then `readers` / `editors` are computed for every row, and the startup check
runs once in full.

What changes on that day:

- Nobody sees anything they couldn't see before.
- Members lose the ability to change rows they couldn't see (§3, item 1).
- API keys lose sight of other members' shares and requests (§3, item 3).
  The changelog says so, since scripts may depend on it.
- Template editing moves from the admin role to holders of
  `templates:manage`. That is the one place where edit access can widen, for
  members who hold the permission without being admins. Migrating templates
  with editing `owner` instead would avoid it.

`sections.shared` stays readable for one release and is then removed.
`/api/shared/vault` answers from the new model during that release and is
then removed; the app moves to the collection API in phase 1.

---

## 10. Phases

Each phase ships with its app screens, tests and docs, and leaves the system
consistent.

1. **Foundation and vault.** The fields on sections and records,
   `services.Access`, recompute hooks, new rules for records and sections,
   the migration of shared sections, the consistency test, the startup
   check, `AccessControl` in the vault, `GET /api/access/...`.
2. **Shares, requests and answers.** Fields, rules, recompute, share detail
   showing only visible records, answer records following their request,
   Access tab and rows.
3. **Templates, contacts, attestations.** Same pattern; these are the areas
   that move from "every member" to an explicit `workspace` audience.
4. **Credentials.** API keys acting as their creator, connections through
   `services.Credential`, webhooks as the endpoint's creator, the
   `visibility` proposal parameter, tool-created items private.
5. **Workspace defaults.** The settings page and pre-filling everywhere.
6. **Groups.** §6.

Docs: `docs/guide/workspaces.md` gains a visibility section, `vault.md`'s
"Sharing a section with members" is rewritten around it, and
`docs/api/authentication.md` describes keys acting as their creator.

---

## 11. Tests

One table-driven matrix per area, in the style of `tests/`:

- **Subjects**: owner; member in the audience with the read permission;
  member in the audience without it; member with the manage permission and
  editing `owner`; member with it and editing `audience`; member outside the
  audience; removed member; member of another workspace; API key of the owner;
  API key of another member; connection of the owner (whole vault and
  sections); webhook of another member.
- **Audiences**: `private`, `workspace`, and `groups` (built against a test
  group table from phase 1, so the shape is exercised before the UI exists).
- **Actions**: list, view, update, delete, change audience, and every custom
  route of §5.5.

Plus the consistency test of §5.2, and regression tests for the three gaps
of §3.

---

## 12. Open questions

1. **Identities.** They stay personal here. Should a workspace be able to
   use one member's identity as the company's sender, with an audience?
2. **Encryption per audience.** Encrypted records are written under the
   workspace key, which every member with vault access may hold, so the
   privacy of a private encrypted record rests on the server, as today.
   Should private and group items get keys of their own later?
3. **Notifying the audience.** When an HR request is answered, should the
   whole HR audience be notified, or only the owner?
4. **When an owner leaves.** Workspace and group items stay, editable by
   their audience as configured and re-assignable by admins. What happens to
   private items: kept for admins to hand over, or deleted with the
   membership?
5. **Audit logs.** Who reads the audit trail of a workspace item: its
   editors, or admins only?
6. **Default editing.** Should new workspace-visible items start with
   editing `owner` or `audience`?
7. **View permissions for people.** Members read templates and contacts
   without `templates:read` / `contacts:read`, as before audiences. Should
   the audience require them, as it does for shares, requests and the vault?

---

## 13. As built

### Phase 1

Where the build differs from the design above, or goes further:

- **Where the answer lives.** `services.Access` is not one type: the answer
  is the set of functions in `cmd/revoked/services/visibility.go`
  (`ExpectedAccess`, `CanSee`, `CanEdit`, the `Recompute*` functions,
  `ReconcileVisibility`). The hooks are in `cmd/revoked/hooks/visibility.go`,
  which replaced `sharedSections.go`.
- **Rule form.** The rules match `readers.id ?= @request.auth.id` (and
  `editors.id`). The bare `readers ?= …` form compares against the stored
  JSON text and never matches; `TestVisibilityMatrix` would catch a return to
  it. `readers` and `editors` are hidden fields, still usable in rules, and
  never part of a response.
- **Records have no audience of their own.** A record is seen through the
  sections of its own owner that hold it. Files, aliases and request answers
  stay owner-only in phase 1.
- **The startup check repairs every row on every start**, not a sample. Rows
  never filled (both columns empty, as right after the migration) are filled
  quietly. Any other difference is logged at error level, since it means a
  recompute hook missed something.
- **Groups exist as tables** (`groups`, `groupMembers`), superuser-only, so
  the tests exercise the `groups` audience from now on. Nothing in the app
  shows them yet.
- **Shares hold only their creator's items.** A share created or changed
  through the collection API, or a contact share, may name only records and
  sections its creator owns. Members can see each other's record ids now, and
  this stops those records from leaving the workspace through a link.
  Existing shares are untouched: only ids added by a save are checked.
- **The older `shared` flag** still works. Setting it sets the audience it
  stood for (`workspace` with editing `audience`, matching what it allowed
  before). The flag is kept in step with the audience for one release.
- **The app** lists only its own sections and records from the collection
  API (`filter: user = "<id>"`), and keeps listing other members' sections
  through `/api/shared/vault`. The section menu's **Visibility** item opens the
  visibility sheet, which offered **Private** and **Workspace** in phase 1.
  Editing a colleague's record from the app came later (see "Also built").
- **Members see more fields** of a shared record through the collection API
  than through `/api/shared/vault` (for example `hashSalt` and `writtenBy`).
  None of them is secret from someone who can read the value.
- **Migration rules come from the builders.** `000095` takes its rules from
  `util.AudienceReadRules` and the registry rather than frozen strings, as
  `000053` does. A later change to those rules needs its own reconcile
  migration; `TestAccessRegistryMatchesRules` now checks the read rules too.
- **Not built:** admins changing the audience of a section whose owner has
  left (§4.3).

### Phase 2

- **Shares and requests carry an audience** of their own
  (`000096_add_share_request_visibility.go`), with the same fields as
  sections, read with `link:read` / `request:read` and edited with
  `link:update` / `request:update`. Update and delete rules admit the owner
  and the members listed in `editors` (`AccessWorkspaceAudienceSelf`). Every
  existing share and request starts private.
- **Answers follow the request** through the routes that read them, not
  through rows of their own: answers live in the responders' vaults and reach
  the requester only through `GET /api/requests/{id}/links`. That route now
  answers the request's owner and the members who see the request and hold
  `responses:read` (others in the audience get 403, everyone else 404).
  Trying a request's callback (`/api/requests/callback-test`) is open to whoever may
  edit the request.
- **A share still holds only its creator's items** (phase 1's rule stays).
  So a share visible to the workspace shows its viewers its link, and
  through it what the owner put in; the sheet says so.
- **The app** lists its own shares and requests (`filter: user = "<id>"`)
  and, apart, those other members opened to the person
  (`user != "<id>"`) under **Shared by members**. Those open read-only: no
  edit, pause, revoke, delete or access controls, and their contents are
  counted rather than resolved against the person's own vault. The
  responder's own answer to a request is looked up with the person's id, as
  a colleague's answer to the same request may be visible now.
- **The access sheet** is one widget (`core/widgets/access_sheet.dart`) for
  sections, shares and requests, with words per area. In the app it is
  named **Visibility** rather than the **Access** of §8: a request's page
  already has an Access group, for its password, respondents and expiry.
- **Not built in phase 2:** editing a colleague's share or request from the
  app, and groups in the sheet (both built later, below), and notifying the
  audience when an answer arrives (§12, question 3).

### Phase 3

- **Templates, contacts and attestations carry an audience**
  (`000097_add_workspace_data_visibility.go`). Every existing row starts as
  `workspace` with editing `audience`, and so does a new one that names no
  audience (`services.DefaultAudience`): these were workspace data, and a
  new one stays so unless its owner narrows it.
- **Read permissions as before.** Templates and contacts never needed
  `templates:read` / `contacts:read` for a member to see them, and still
  don't: everyone in the audience reads them. Attestations always needed
  `attestations:read` (their own hook checks it), and the audience needs it
  too. Whether the view permissions should start to apply for people is
  §12, question 7.
- **Owners.** Templates gained `user`, set on create. Contacts gained
  `createdBy`, set by the server on create: a contact's `user` is the
  account it points to, not who added it, and treating it as the owner would
  have let that person edit the entry. Rows older than the migration have no
  owner, stay with the workspace, and nobody can change their audience
  (§12, question 4 covers handing such rows to an admin).
- **Attestations need the permission, owned or not**
  (`AccessWorkspaceAudienceAdmin`): their owner is listed among the editors
  only while holding `attestations:issue`, and the rule admits editors alone.
- **Routes.** Sending to or asking from a contact refuses one the member
  does not see (404, as for a missing one). A template named when asking a
  contact, or by a connected tool, must be one the member (or the tool's
  owner) sees.
- **Migrations no longer read the live registry.** `000071` rendered the
  contacts rules from `util.CollectionAccess` at run time, so giving
  contacts an audience broke a from-scratch replay at `000071`. It now
  states the specs it meant, as `applyFrozenRules` asks, and `000095`–`000097`
  pass theirs explicitly too.
- **The app** offers **Visibility** in the options of a template, contact or
  attestation to its owner. Lists are unchanged: they always showed the
  workspace's rows, and a colleague's private row simply stops arriving.

### Phase 4

- **API keys act as their creator.** Every rule's key branch on a collection
  with an audience also requires the key's creator among the row's readers
  (or editors, for a change): `readers.id ?= @request.auth.user`
  (`000098_bind_keys_to_their_creator.go`). Before, a key with a scope saw
  every member's rows of its workspace. The changelog should say so, since
  scripts may have relied on it.
- **Webhooks** hear about an item only when the member who made the
  endpoint sees it (`services.EmitWebhookEventAbout`); answers to a request
  also need `responses:read`. For a deleted record or request the readers
  are worked out before the deletion. Workspace-level events (members, keys,
  connections, identities) are unchanged.
- **Tools.** What a tool creates directly (a share, a request, its own
  section) is pinned private, whatever the workspace's default. Proposal
  links carry an optional `visibility=private|workspace`, which the MCP
  server's `propose_share`, `propose_request` and `propose_attestation`
  accept; the app pre-fills the choice with it and marks it as suggested.
  Groups are not part of the parameter yet.

### Phase 5

- **Workspace defaults** live in `workspaces.defaultAudience`
  (`000099_add_workspace_default_audience.go`), a map from collection to
  `private` or `workspace`, validated on save. **Default visibility** in a
  workspace's options edits it, for members who may manage the workspace.
- **Defaults apply to what people create** through the API (the request
  guard). Items the server creates (answer links, sign-in shares, sends to a
  contact, answer and sign-in sections) keep the built-in default, and
  answer sections always stay private.
- **Create sheets** for sections, shares, requests and attestations show
  **Visible to**, pre-filled from a tool's suggestion, else the workspace's
  default; the choice is part of the create request, so an item never exists
  with the wrong audience, even briefly. Templates and contacts take the
  default without a choice in their create sheets.
- Naming an audience other than the default on create is an owner's act, so
  an API key creating an item may not name one; it gets the default.

### Phase 6: groups

- **`/api/groups`** lists the active workspace's groups (any member) and
  creates, renames and deletes them and changes their members (members who
  may invite). Only workspace members join a group; leaving the workspace
  leaves its groups (`services.LeaveWorkspaceGroups`, in the same
  transaction).
- **The Visibility sheet** offers **Groups** once the workspace has any, with
  the groups to tick; the current ones come from the access summary. Groups
  are not offered in create sheets: an item starts private or workspace and
  is narrowed to groups from its page.
- **Settings → Workspaces → Groups** lists the groups and, for members who
  may invite, manages them.

### Also built

- **Editing colleagues' items from the app** where their owner opened
  editing: values of records in a colleague's section (written encrypted when
  the record is), and a colleague's share or request (edit, pause, revoke,
  delete; not its contents, and not who sees it). The app asks
  `GET /api/access/...` for `canEdit` rather than guessing.

