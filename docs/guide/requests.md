# Requests

A request asks other people for information. You send a link, they fill it
in, and the answers arrive sorted the way you asked. When someone answers
from their own vault, you get a link to their data, not a copy. They keep
it up to date, and they can take it back.

Want it the other way round, with a tool asking for records someone already
has? That's a [link proposal](tools.md). A request brings answers into
your workspace. A proposal creates a share in the owner's workspace.

## Ask for what you need

Choose **New → Request** and pick a [template](templates.md). Its fields
are what people are asked to fill in. No template? Then switch on **Allow
extra fields**, so people add fields of their own. A request has to ask for
something. Leave the title empty, and it takes the template's name.

Once it's created, you get the link and a short message to send with it.
The message tells people they answer in the Revoked app.

These options sit under **Advanced**:

**Who can respond**

- **Require a verified identity.** People have to prove who they are with
  an identity before they answer. Accept **Any** identity, or only those
  **From this root**, your own server.
- **Identifier.** Something you tell the person yourself, such as a
  customer number or a case number. They have to enter it, so you know whose
  answer it is.
- **Password.** The simplest lock. Tell it to them yourself, too.

**Limits and callback**

- **Max responses** and **Expires at** close the request on their own.
- A **Callback URL** sends every answer to your own system as it arrives.
  See [Callbacks](../api/callbacks.md).

## Answer a request

You need a Revoked account to answer. Your answer is kept in your own
workspace, so you can change it or take it back later.

For each field, choose **Use a vault entry** or type a value. A vault entry
is the better choice: the answer stays yours. The person who asked always
sees its current value, and you can withdraw it any time, just like a
[share](sharing.md). **Revoke my response** takes your answer back.

Before you send anything, the app checks who is asking. If the request's
claim contradicts its domain, it's blocked: it's a fake. If the sender
can't be confirmed, you have to say you want to go ahead. Answering again
later updates your answer instead of adding a second one.

Requests from other Revoked servers work the same way. You answer from
your own account, and your answer stays on your own server. The other
server fetches it from there each time it's needed. Revoke it at home, and
it's revoked for them too.

## Read the answers {#reading-what-came-back}

Open a request and press **View responses**. Switch between **List** and
**Sheet**: the sheet shows one row per person and one column per field.

Each answer shows whether it was typed or links to the person's vault. A
linked answer also shows whether it still works or was revoked. If an
answer lives on another server and that server can't be reached, you see
no values, never an old copy. To keep an answer, press **Open in Vault**.
Revoking the request stops new answers.

You get a notification when an answer arrives, when the request is full or
expires, and when a callback fails.
