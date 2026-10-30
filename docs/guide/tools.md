# Tools & link proposals

Some tools need your data: an emergency-card maker, an application form,
someone else's service. With a **link proposal**, the tool asks for the
records it needs, and you create the share yourself, on your own server.
The tool only ever names keys, never values, and it never gets into your
vault.

A [request](requests.md) works the other way round: the person who wants
the data sends you a form, and you fill it in.

| | Request | Link proposal |
|---|---|---|
| Who starts it | The person who wants the data | A tool, for the person who has the data |
| Where the data ends up | In the requester's workspace, with that request's answers | In a share in the owner's workspace, under **Shares** |
| What the other side keeps | The answers: typed, or linked to your vault so you can take them back | At most the link, and only once you hand it over |

[Notfallkarte](notfallkarte.md) is a complete example: a web page that
turns a proposal into an emergency card for your wallet.

## Review what a tool asks for

A proposal opens the app on **Link proposal from …**. The name after
*from* is what the tool calls itself, so treat it as a claim. Next to it is
the tool's web address. That's what really identifies it.

You see every record the share would include, found in your vault by the
keys the tool named. Missing some? Fill them in right there. A proposal can
name a [template](templates.md) for its keys, which gives each one a label
and an input. What you enter is saved to your vault like any other record.

Nothing is created until you press **Continue**. **Decline** takes you back
to the tool without sharing anything.

A proposal can also set the share's options: an expiry in days, a
watermark text, or that it's a rental application. The share is created
with exactly those. If any part of a proposal is broken, the whole thing is
refused (*This link doesn't work*). The app never guesses what the tool
meant.

## Connect a tool

Once you confirm a proposal, the tool learns nothing more on its own. For
that, you **Connect** it: as a step before the review, or separately, for
example from the tool's settings. A connected tool can see what became of
the links it proposed: active, paused, revoked or expired, and how often
they were opened. It never sees what they contain, or anything else in
your vault.

Two more permissions are your choice, per tool. Each one shows the reason
the tool gave for asking:

| Permission | What it allows |
|---|---|
| **Revoke links it proposed** | The tool can end a link that came from its own proposal, for example when you delete the printed card it belongs to. It can end shares this way, but never create or read them. You're notified like for any other revocation. |
| **Receive the links it proposed** | The finished link goes straight to the tool, so you don't have to copy it over. Links with a hidden record or a file are never handed over: copy those yourself. |

### Confirm on another device

To answer a tool, the app opens the tool's page again in your default
browser. That may not be the browser you started in. A tool that already
knows your server can avoid this by picking up the answer itself. It then
shows a short code such as `83C-047` on its page, and the app shows the
same code before anything is connected. Continue only if both match. The
original tab then carries on, even if you confirmed on your phone.

Already connected in one browser? **Let this browser in** admits another
one. It gets the same permissions as before, nothing more.

## Manage your connected tools

**Settings → Connected tools** lists every tool: when you connected it,
when it was last used, when the connection ends, and the links it
proposed. There you can change its two permissions, open or revoke each of
its links, or **Disconnect** it. Disconnecting cuts the tool off at once.
The links themselves stay and keep working.

A connection lasts **90 days** from the last time you confirmed it in the
app. Only confirming it there again renews it; a tool can't keep itself
alive. Everything a tool does (connecting, reading, revoking,
disconnecting) is recorded in the audit log under its web address.
