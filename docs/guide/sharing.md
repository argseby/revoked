# Sharing

A share is a link to records in the vault. Anyone opening it sees the
current values until the share is revoked. A changed password is visible
to everyone with the link at once; a revoked link stops working the next
time it is opened.

## Creating a share

**Share** on a record, or **New → Share link**, opens the share form. A
share can contain individual records or whole
[sections](vault.md#group-records-into-sections).

The remaining fields have defaults: the label is derived from the shared
content, and the link expires after 30 days. Another date can be chosen,
or the date cleared for a link that does not expire. Once created, the
link is ready to copy or send.

## Access controls

These options can be combined freely:

| Option | Effect |
|---|---|
| **Password** | Must be entered before anything is shown. |
| **Maximum views** | The link revokes itself after that many views. The limit holds even for simultaneous openings. |
| **Expiration date** | The link stops working at that time. |

**Maximum views** is under **Advanced**, together with the link's address,
the watermark, the signature and the API preview.

## Who in the workspace sees a share {#members}

A share is otherwise seen only by the member who created it. **Visibility** on
the share's page sets who else in the workspace sees it:

- **Private**: seen by the owner only.
- **Workspace**: seen by every member who can view shares. Whoever sees a
  share can open its link, and with it everything the link holds.

For a share visible to the workspace, **Editing** sets whether members who
may manage shares can also pause, revoke and change it. Other members' shares
appear under **Shared by members** and open read-only. A share holds only its
creator's own records and sections. Only the owner can change who sees a
share, and only from the app.

## Verification

Under **Advanced → Verification**:

- **Sign with one of your identities.** Recipients can verify against the
  domain that the link was issued by its sender. See
  [Identities & trust](identities.md).
- **Require a verified viewer.** The viewer must prove who they are with an
  identity of their own before anything is shown.

The API preview under **Advanced** shows the exact request the app will
send, and serves as an introduction to the [HTTP API](../api/index.md).

## Share status

| Status | Meaning |
|---|---|
| Active | The link works. |
| Paused | The link is suspended. **Activate** turns it back on. |
| Revoked | The link is permanently disabled, either manually or by reaching its view limit. |
| Expired | The expiration date has passed. |

**Pause** suspends a link temporarily. **Revoke** ends it permanently and
cannot be undone. **Duplicate** creates a new link to the same records,
with a new address and the view count reset to zero.

Badges on each share indicate its kind: password-protected, requiring a
verified viewer, or answering a [request](requests.md).

## Recipient view

A share is sent as a `revoked://` link or as a QR code. The QR code holds a
web address, so a phone camera can open it without the app.

- **In the app**, the link opens directly on the share, after showing
  whether the sender could be verified.
- **In a browser**, a plain page is shown, with no trackers and nothing
  loaded from elsewhere. Nothing is displayed until the button on the page
  is pressed, so opening the page alone does not use up a view. The page
  verifies the sender's domain itself and offers **Open in app**.

## Watermarks

A **Watermark** text can be added when creating or editing a share. Every
image and PDF served by the link is then stamped with that text, the date
and a short tag such as `#a3f9c1`. The same tag is shown on the share, so a
leaked copy or screenshot identifies the link it came through.

The stamp covers the whole page and cannot be cropped out. The original
file is not modified. Files that cannot be stamped (text files, archives,
documents other than PDF) are not served on a watermarked share. Values
shown as text receive a visible overlay on the page, which discourages
copying but cannot prevent it.

## Rental applications

A share can be set up as a rental application. Such a share always carries
a watermark: the server refuses to create one without it and does not
allow it to be removed later. The page presents the applicant's details and
documents in separate cards. The first time the landlord opens it, a
*Your application was opened* notification is sent. Later openings do not
notify again.

Once the landlord has opened it, **Download all** saves every document in
one archive. Each file is stamped exactly as a single download would be. A
file that cannot be stamped is omitted, never included unmarked. The button
works once per visit; reloading the page issues a new one.

The owner can download the same archive without using up a view, and can
preview the stamp on any file before sharing it. A preview's tag ends in
`#preview`, so it cannot pass for a copy actually received. Both are
available through the [HTTP API](../api/index.md).

## Bookmarks {#bookmarking-a-share-you-received}

When signed in, **Bookmark** on an opened share saves it under
**Shares → Received**, so it can be reopened without the original
message. Shares someone on the same server hands over are listed there
too, first, under **Handed to you**.

A bookmark stores only where the link is, never its data. Opening a
bookmark behaves like opening the link: the password, identity check and
view limit still apply, and a paused or revoked share stays closed.
Bookmarks are private to their owner; neither other workspace members nor
API keys can see them.

Bookmarks can be sorted into groups, similar to playlists. **Bookmarked**
on an open share, or **Groups** on a bookmark, selects its groups or
creates a new one. A bookmark can belong to several groups. Deleting a
group keeps its bookmarks.

## Export formats

**Share link** on a share, then **Web & API**, provides its data in formats
other applications read directly, always with the current values:

| Format | Use |
|---|---|
| CSV | Spreadsheets. Includes a ready-made `=IMPORTDATA(…)` formula for Google Sheets. |
| vCard (`.vcf`) | A one-time contact import. |
| CardDAV | A contacts account that stays in sync with the vault. Only on shares without a password, because CardDAV cannot send one. |
| iCalendar (`.ics`) / `webcal://` | Importing into a calendar, or subscribing so it stays current. |
| cURL | A command for use in scripts. |

Clients that poll frequently download again only when a value has
actually changed.
