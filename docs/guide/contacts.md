# Contacts

A contact is a person the workspace sends records to and requests data
from. Sending to a contact skips copying a link by hand: a contact with an
account on the same server receives it directly in the app. Contacts belong
to the workspace, not to the member who added them.

## Adding a contact

**New contact** on the **Contacts** page opens **Add a contact**:

| Field | Use |
|---|---|
| **Name** | How the contact appears in the list. Required. |
| **Email address** | Where the contact is reached. |
| **Server (optional)** | The domain of the contact's own Revoked server, for contacts who run one. |

A contact needs a name and either an email address or a server. The server
refuses a contact that reaches nobody.

A new contact always starts unverified. Only the server marks a contact as
**Verified**; neither the app nor a member can set it. Which account an
email address belongs to is settled by the server, and it is not reported
back for a contact nobody has confirmed: an address can be typed in, and
answering whether it has an account here would turn the contact list into a
way of finding out who holds one.

## Sending records

**Send records** opens a sheet with a **Label** and a choice of records and
sections. **Send** creates a share in this workspace, exactly like one made
under [Sharing](sharing.md): it shows the current values and can be paused
or revoked at any time. A section is sent as a whole, so records added to it
later are included. Records protected by end-to-end encryption cannot be
sent this way.

## Requesting data

**Request data** asks the contact to send something back. The sheet takes a
**Title**, an optional **Template** and **Your identity**, the identity the
request is signed with. **Ask** creates a [request](requests.md) that closes
after one answer. Without a template, the contact adds their own fields.

## Delivery

Before **Send** or **Ask**, the sheet states where the link will go. The
link is created in every case; delivery only decides how it reaches the
contact.

| Contact | Result |
|---|---|
| Has an account on this server | Delivered to the contact's app, with a notification. It appears among their [bookmarks](sharing.md#bookmarking-a-share-you-received). |
| Email address the server may mail | The link is sent by email. |
| Any other contact | The link is shown with a QR code, to be passed on manually. It remains revocable. |

What the sheet reports afterwards depends on the contact. For a contact the
two are in touch with — proven by the server, a member of the same
workspace, or someone who has sent something back — it names where the link
went. For anyone else it says only that the link exists and shows it, which
is also what is said when the delivery was refused. The link may well be in
the contact's app already; the server does not confirm it, because a
confirmation would also answer which addresses hold an account here.

Whether the server sends email, and to whom, is set by the operator with
[`GRANT_EMAIL_RECIPIENTS`](../installation/env.md#emailing-a-share-or-a-request):
nobody, addresses in the server's own domain, addresses on verified Revoked
domains, or anyone. A request also requires the contact to hold an account
on this server to respond. Where the server does not accept new sign-ups,
the request link is returned for manual delivery with a note that the
server operator can add the account.

Nothing is pushed to another server. A contact on their own server receives
the link by email or by hand.

## Unwanted deliveries

A delivery into someone else's app is the one thing a workspace can write
into another account, and the address it is aimed at can be guessed, so it
is bounded. While nothing connects the two accounts, three deliveries a day
reach one recipient
([`RATELIMIT_CONTACT_PAIR`](../installation/env.md#rate-limits)); the rest
are left undelivered, and the sender is told no more than that the link
exists. The count is kept by the server, so deleting the bookmarks does not
make room for more. Once the two are in touch the cap no longer applies.

A received share or request names the account that sent it, which can be
refused: nothing from that account, that address, or that whole domain
reaches the tray again, however long the two have been in touch. A refused
sender is told the same as an unconfirmed one, so they are not invited to
come back under another account. Links that were already delivered stay
where they are and can be removed like any other bookmark.

## Renaming and removing

Selecting a contact opens its options. **Rename** changes only the name.
**Remove** deletes the contact after confirmation; anything already sent
keeps working until it is revoked from [Sharing](sharing.md) or
[Requests](requests.md).

## Who sees a contact {#members}

A new contact is seen by every member of the workspace, who can send to it
and ask from it, as contacts always were. **Visibility** in a contact's
options, offered to whoever added it, keeps it to them instead
(**Private**); other members then find neither the contact nor a way to send
to it. It also sets whether members who may manage contacts can rename and
remove it. Contacts added before this setting existed stay with the
workspace.

## Permissions

Viewing contacts requires **View contacts**; adding, renaming and removing
requires **Manage contacts**. Sending and requesting also require the
permission to manage shares or requests. API keys cannot send to contacts:
only a person can hand something to someone else. The **Contacts** page can
be hidden under [Settings → Features](features.md).
