# Requests

A request collects information from other people. A link is sent,
recipients fill it in, and the responses arrive structured as requested. A
response given from the responder's vault arrives as a link to their data,
not a copy: the responder keeps it current and can revoke it.

For the reverse direction, a tool asking for records someone already
holds, see [link proposals](tools.md). A request brings responses into the
requester's workspace. A proposal creates a share in the owner's
workspace.

## Creating a request

**New → Request** creates a request from a [template](templates.md), whose
fields define what is asked. Without a template, **Allow extra fields**
lets respondents add fields of their own. A request must ask for
something. An empty title defaults to the template's name.

After creation, the link is shown together with a short message to send
with it, which explains that responses are given in the Revoked app.

The following options are under **Advanced**:

**Respondents**

- **Require a verified identity.** Respondents must prove who they are with
  an identity before answering. **Any** accepts any identity; **This server
  only** accepts only identities from the requester's own server.
- **Identifier.** A value passed to the respondent separately, such as a
  customer or case number. It must be entered to respond, which ties each
  response to a known person.
- **Password.** The simplest restriction, also passed on separately.

**Limits and callback**

- **Max responses** and **Expires at** close the request automatically.
- A **Callback URL** forwards each response to an external system as it
  arrives. See [Callbacks](../api/callbacks.md).

## Responding to a request

Responding requires a Revoked account. The response is kept in the
responder's own workspace, where it can be changed or revoked later.

Each field is answered with **Use a record** or **Use a different value**.
A record is preferable: the response stays under the responder's control,
the requester always sees its current value, and it can be withdrawn at
any time, like a [share](sharing.md). **Revoke response** withdraws a
response.

Before anything is sent, the app verifies the requester. A request whose
claim contradicts its domain is blocked as forged. A request whose sender
cannot be confirmed requires explicit confirmation to proceed. Responding
again later updates the existing response instead of adding a second one.

Requests from other Revoked servers work the same way. The response is
given from the responder's own account and stays on the responder's
server; the requesting server fetches it from there each time it is
needed. Revoking it at the source revokes it for the requester as well.

## Responses {#reading-what-came-back}

**View responses** on a request lists its responses, either as a **List**
or as a **Sheet** with one row per respondent and one column per field.

Each response shows whether it was typed or links to the respondent's
vault. A linked response also shows whether it is still active or was
revoked. If a response lives on another server that cannot be reached, no
values are shown, never a stale copy. **Open in Vault** keeps a response.
Revoking the request stops new responses.

Notifications are sent when a response arrives, when the request is full
or expires, and when a callback fails.
