# Workspaces & members

A workspace keeps your things together: vault, shares, requests,
templates, identities and members. You create or join your first one when
you sign up. You can belong to up to ten, and switch between them under
**Settings → Workspaces**.

## Choose what each member can do

You decide exactly what each person may do. When you invite someone or
edit a member, tick the permissions they need. Most areas have one to view
and one to manage: vault, collected data, shares, requests, templates and
identities. Attestations can be viewed and issued, and members can be
viewed, invited and removed. **Manage workspace** covers renaming and
deleting it.

Some permissions are marked as sensitive, because they can hand out access
or lock others out: **Manage identities**, **Issue attestations**,
**Invite members**, **Remove members** and **Manage workspace**.

Anyone who can invite is an **admin**. You don't assign that separately.
A workspace always keeps at least one member who can both invite and
remove, so nobody can lock it for good.

## Invite someone

Create an invite under **Settings → Invites** and send the key any way you
like. It carries the permissions you picked. You can narrow it further:

- **Lock to an email**: only that account can accept it.
- **Single use**: the key stops working once someone joins. Otherwise it
  works until you withdraw it or it expires.

To join, paste the key. Before you accept, the app shows what it can
actually prove about who invited you, with the same
[check](identities.md#check-who-sent-something) you get for shares. You're
notified when someone accepts an invite you sent.

## Leave, remove or delete

When a member leaves or is removed, the identities they used in this
workspace are revoked at the same moment. Their shares and answers stop
showing as verified for this workspace right away.

Deleting a workspace deletes everything in it and revokes its identities.
Anyone who checks an old share afterwards still gets a clear "revoked",
not silence. Deleting your account does the same for everything you own.
Neither can be undone.

A workspace holds at most 50 members.
