# Sharing

A share is a link to records in your vault. Whoever opens it sees today's
values, until you revoke it. Change a password, and everyone with the link
sees the new one. Revoke the link, and it stops working the next time
someone opens it.

## Share your first record

Press **Share** on a record, or choose **New → Share link**. Pick what to
share: single records, or whole [sections](vault.md#group-records-into-sections).

You can leave the rest as it is. The label comes from what you share, and
the link expires after 30 days. Pick another date, or clear it for a link
that doesn't expire. Create it, and your link is ready to copy or send.

## Decide who gets in

Use any of these, in any combination:

| Option | What it does |
|---|---|
| **Password** | The viewer has to enter it before they see anything. |
| **Maximum views** | The link revokes itself after that many views. Even people opening it at the same moment can't get past the limit. |
| **Expiration date** | The link stops working at that moment. |

**Maximum views** sits under **Advanced**, together with the link's
address, the watermark, your signature and the API preview.

## Prove it came from you

Under **Advanced → Verification**:

- **Sign with one of your identities.** Recipients can then check against
  your domain that the link really came from you. See
  [Identities & trust](identities.md).
- **Require a verified viewer.** The viewer has to prove who they are with
  their own identity before they see anything.

The API preview under **Advanced** shows the exact request the app is about
to send. It's the quickest way to learn the [HTTP API](../api/index.md).

## Pause, revoke or duplicate

| Status | What it means |
|---|---|
| Active | The link works. |
| Paused | The link is on hold. Press **Activate** to turn it back on. |
| Revoked | The link is gone for good. You revoked it, or it reached its view limit. |
| Expired | Its expiration date has passed. |

**Pause** when you need a moment. **Revoke** when you're done: it can't be
undone. **Duplicate** makes a new link to the same records, with a fresh
address and the view count back at zero.

Badges on each share tell you what kind it is at a glance: it has a
password, it needs a verified viewer, or it answers a
[request](requests.md).

## What your recipient sees

You send a `revoked://` link, or a QR code. The QR code holds a web
address, so a phone camera works even without the app.

- **In the app**, the link opens right on the share. Before anything else,
  it shows whether the sender checks out.
- **In a browser**, they get a plain page with no trackers and nothing
  loaded from elsewhere. Nothing is shown until they press the button on
  the page, so just opening it never uses up a view. The page checks the
  sender's domain by itself, and offers **Open in app**.

## Watermark your files

Add a **Watermark** text when you create or edit a share. Every image and
PDF the link serves is then stamped with your text, the date, and a short
tag such as `#a3f9c1`. The same tag shows on the share. So a leaked copy or
screenshot tells you which link it came through.

The stamp covers the whole page, so it can't be cropped away. Your own file
stays unchanged. Files that can't be stamped (text files, archives,
documents other than PDF) are not served on a watermarked share. Values
shown as text get a visible overlay on the page. That discourages copying,
but can't stop it.

## Rental applications

A share can be set up as a rental application. It then always carries a
watermark: the server won't create one without, and won't let you switch
it off later. The page shows the applicant's details and documents in
cards of their own. The first time the landlord opens it, you get a *Your
application was opened* notification. Later opens don't notify you again.

Once the landlord has opened it, **Download all** saves every document in
one archive. Each file is stamped exactly like a single download. A file
that can't be stamped is left out, never included unmarked. The button
works once per visit; reloading the page gives a new one.

You can download the same archive yourself, without using up a view. You
can also preview the stamp on any of your files before you share it. A
preview's tag ends in `#preview`, so it can never pass for a copy someone
really received. Both are available through the [HTTP API](../api/index.md).

## Keep a share someone sent you {#bookmarking-a-share-you-received}

Signed in, press **Bookmark** on a share you opened. It's saved under
**Requests → Received**, so you can open it again without digging for the
original message.

A bookmark only remembers where the link is. It never stores the data.
Opening it works like opening the link: the password, identity check and
view limit still apply. If the owner paused or revoked the share, it stays
closed. Only you see your bookmarks: not other members of your
workspaces, and not API keys.

Sort bookmarks into groups, the way you'd sort videos into playlists. Press
**Bookmarked** on an open share, or **Groups** on a bookmark, to pick its
groups or make a new one. A bookmark can sit in several groups. Deleting a
group keeps its bookmarks.

## Use a share in other apps

Press **Share link** on a share, then **Web & API**. You get its data in
formats other apps read directly, always with the current values:

| Format | Use it for |
|---|---|
| CSV | Spreadsheets. Includes a ready-made `=IMPORTDATA(…)` formula for Google Sheets. |
| vCard (`.vcf`) | Importing a contact once. |
| CardDAV | A contacts account that stays in sync with your vault. Only on shares without a password, because CardDAV can't send one. |
| iCalendar (`.ics`) / `webcal://` | Importing into a calendar, or subscribing so it stays up to date. |
| cURL | A command to paste into your scripts. |

Apps that check often only download again when a value has actually
changed.
