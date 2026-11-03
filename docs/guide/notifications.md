# Notifications

**Notifications** lists what happened to the workspace's shares, requests
and attestations, newest first. It opens from the sidebar or the bell, which
carries the number of unread notifications.

## Events

The server adds a notification for each of these events:

| Event | Notification |
|---|---|
| A request receives a response, or a responder updates one | Request received a new response; A response was updated |
| A request reaches its response limit, or expires | Request completed; Request expired |
| A link expires, is revoked, or reaches its view limit | Link expired; Link revoked; Link reached max views |
| A response to a request is revoked or expires on the sender's side | Shared data revoked; Shared data expired |
| A rental application is opened for the first time | Your application was opened |
| A request's callback URL cannot be reached | Callback delivery failed |
| The email carrying a link or request does not arrive | Email not delivered |
| A webhook is switched off after three days of failed deliveries | Webhook turned off |
| An invite is accepted | Invite accepted |
| Someone on the server shares something or asks for something | Something was shared with you; Someone needs something from you |
| An attestation offer is accepted, or an attestation is shown | Attestation accepted; An attestation was shown to you |
| Encrypted records are reset from a signed-in session | Your encrypted records were reset |
| A [reminder](vault.md#get-reminded) fires | Reminder: followed by the record's name |

A notification never contains a record's value. See
[Request callbacks](../api/callbacks.md) and [Webhooks](../api/webhooks.md).

## Filters

| Filter | Lists |
|---|---|
| **All** | Every notification |
| **Unread** | Notifications not yet read |
| **Needs attention** | Failed callbacks, undelivered emails and reset encrypted records |

Each filter shows its count. A notification that needs attention has a red
icon, and an unread one a dot at the end of the row.

## Grouping by day

Notifications are grouped under **Today**, **Yesterday**, **This week** and
**Earlier**; empty groups are left out. Each row shows how long ago it
arrived, such as "5 min ago", a weekday, or a date.

## Opening a notification

Tapping a notification marks it as read and opens what it refers to:

| Refers to | Opens |
|---|---|
| A record | The record |
| A request | The request and its responses |
| A link | The link |
| A shown attestation | **Checked** under **Attestations** |
| A share or request from a contact | **Received** under **Requests** |

Notifications about invites, webhooks and encrypted records open nothing;
the text carries the full message.

## Managing notifications

Each row's **Options** menu holds **Mark as read** (or **Mark as unread**)
and **Delete**. Swiping a row to the left also deletes it.

The **More** menu beside the filters applies to the whole list:

- **Mark all as read** marks every unread notification as read.
- The delete entry, which names the count (as in "Delete 3 read
  notifications"), removes every read notification after a confirmation.
  Unread notifications are kept.

## Refresh

The app loads the latest 100 notifications at sign-in and checks for new
ones every minute while it is open. Reminders fire on the server's clock,
so they arrive through this check without any action in the app.
