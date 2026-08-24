# Workspaces & members

A workspace is the unit everything lives in: vault, shares, requests,
templates, identities and members are all scoped to one. You create or join
your first at onboarding, can belong to up to ten, and switch the active one
under **Settings**.

## Permissions

Access is granted per **permission**, not per role. The catalogue pairs a
read grant with a manage grant for each area — vault, collected data, shares,
requests, templates, identities, members — plus *Manage workspace* for
renaming and deletion. When you invite someone or edit a member, you tick
exactly what they may do.

Three grants are marked destructive because they extend or end other people's
access: managing identities, inviting members, and removing members. Anyone
holding the invite grant is an **admin** — the label is derived from what
they can do, never assigned separately — and a workspace always keeps at
least one member who can both invite and remove, so access can never be
orphaned.

## Invites

An invite is a key you create and hand over on any channel. It carries the
permissions you chose, and can be narrowed further:

- **Pinned to an email** — only that account can accept it.
- **Single-use** — spent on first acceptance; otherwise it stays active until
  you revoke it or it expires.

Joining is pasting the key. Before accepting, the app shows what the server
can actually prove about the inviter — the same
[verification](identities.md#reading-a-verdict) shares get. You are notified
when an invite you issued is accepted.

## Leaving, removing, deleting

Removing a member (or leaving) revokes the identities that person used in the
workspace, in the same transaction — their existing shares and responses stop
verifying as this workspace immediately.

Deleting a workspace destroys its contents and revokes its identities.
Revoked identities leave tombstones, so anyone verifying an old share still
gets a definitive "revoked" rather than silence. Deleting your account does
the same for everything you own. Neither is undoable.

A workspace holds at most 50 members.
