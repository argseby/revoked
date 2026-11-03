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
