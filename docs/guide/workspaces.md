# Workspaces & members

A workspace groups a vault, shares, requests, templates, identities and
members. The first workspace is created or joined at sign-up. An account
can belong to up to ten workspaces and switch between them under
**Settings → Workspaces**.

## Member permissions

Permissions are set per member, by ticking them when inviting or editing a
member. Editing a member also shows which parts of the app that member has
enabled. Most areas have one permission to view and one to manage: vault,
collected data, shares, requests, templates and identities. Attestations
can be viewed and issued; members can be viewed, invited and removed.
**Manage workspace** covers renaming and deleting the workspace.

Some permissions are marked as sensitive, because they can grant access or
lock others out: **Manage identities**, **Issue attestations**,
**Invite members**, **Remove members** and **Manage workspace**.

Any member who can invite is an **admin**; the role is not assigned
separately. A workspace always retains at least one member who can both
invite and remove, so it cannot be locked permanently.

## Who sees what {#visibility}

Each vault section, share, request, template, contact and attestation has a
**Visibility**: **Private** (its owner only), **Workspace** (every member
with the matching permission) or **Groups** (members of the chosen groups).
The owner sets it, from the item's page or options; the guides for each area
describe what it means there.

### Default visibility {#defaults}

**Default visibility** in a workspace's options sets what new items of each
area start with. Vault sections, shares and requests start **Private** and
templates, contacts and attestations **Workspace** unless the workspace says
otherwise. The choice is shown, and can be changed, when an item is created.
Existing items keep theirs, and a default never grants anything by itself.
What the server creates on its own, such as an answer to a request or a
sign-in's share, stays private.

### Groups {#groups}

**Groups** in the active workspace's options lists its groups, such as HR,
Service or Techs. Every member sees them; members who can invite create,
rename and delete groups and choose who is in them. Only members of the
workspace can be in a group, and leaving the workspace leaves its groups.
Deleting a group leaves items visible to it alone with their owner.

## Invites

**New invite** under **Settings → Invites** creates a key, which can be
sent through any channel. The member type sets the initial permissions and
visible parts of the app: **Vault only**, **Vault and sharing** or
**Everything**. **Advanced** allows each permission and each visible part
to be chosen individually.

After joining, the visible parts are the member's own choice, under
**Settings → Features**; the invite only presets them for a member who has
not chosen yet. Hiding a part of the app never removes a permission, and
showing one never grants one. The invite carries the selected permissions
and can be restricted further:

- **Restrict to email**: only that account can accept it.
- **Single use**: the key stops working once someone joins. Otherwise it
  remains valid until withdrawn or expired.

An invite is accepted by pasting the key. Before acceptance, the app shows
what it can prove about the inviter, using the same
[sender check](identities.md#check-who-sent-something) as for shares. The
inviter is notified when an invite is accepted.

## Leaving, removal and deletion

When a member leaves or is removed, the identities they used in the
workspace are revoked at the same moment. Their shares and responses
immediately stop showing as verified for this workspace.

Deleting a workspace deletes everything in it and revokes its identities.
Checking an old share afterwards still returns a clear "revoked", not
silence. Deleting an account does the same for everything it owns.
Neither can be undone.

A workspace holds at most 50 members.
