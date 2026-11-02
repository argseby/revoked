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
proposed. There you can change its two permissions, or open or revoke each
of its links.

### Take a break from a tool

Not sure you still want it? Tap **Pause**. The tool can't do anything, and
its links stop opening too. Tap **Activate** when you want it back, and
everything works as before. Any link you paused yourself stays paused.

### Cut a tool off for good

Tap **Disconnect** and the tool is cut off at once. Its links stay yours and
keep working, unless you also tick **Revoke its links too**.

A connection lasts **90 days** from the last time you confirmed it in the
app. Only confirming it there again renews it; a tool can't keep itself
alive. Everything a tool does (connecting, reading, revoking,
disconnecting) is recorded in the audit log under its web address.

## See where you signed in

Signed in to a game or a shop with Revoked? Find it again under
**Settings → Connected tools**, in **Services you signed in to**. Each
service shows when you first and last signed in, what it learned about you,
and any entries you shared.

To stop a service reading your entries, tap its link under **Shared entries**
and choose **Revoke**. It can't read them from then on.

### Pause a service

Tap **Pause** and you can't sign in to that service with Revoked. It can't read
your entries either. Tap **Activate** to undo it, and the service knows you as
before.

### Disconnect a service

Done with a service? Tap **Disconnect**. It can't read your entries any more,
and you can only sign in there again by approving it in the app.

### Come back as someone new

When you disconnect, tick **Get a new ID** and the service sees you as someone
new if you ever come back. If you've already disconnected, the same button is
on the service's page.

Think before you tick it. You can't get your old account there back, along with
anything saved in it, like game progress. Not sure? Use **Pause** instead.

When you come back, the app shows you what the service is asking for, with
nothing picked. Your email, your name or your identity can still tell the service
who you are, so share them only if you don't mind that.

## Choose your name for each service

When a service asks for your name, you decide which one it gets. You can use
a game name in one place and your real name in another. The top of **Your name**
shows what the service will see.

Tap one of your identities or vault entries to use it. Want a new name just for
that service? Type it in **Your new name**. Don't want to share one? Turn off the
switch, and you can still sign in.

Using a vault entry? Change the entry, and the service can pick up the new
name. Some services only update it the next time you sign in. Your choice is
remembered, and you can change it at your next sign-in. Either way, the
service knows you by the same ID, unless you ask for a new one.

## Choose what a service reads

A service can ask for something from your vault, like a game asking for a
player name. The app shows what the service will see, and you decide:

- Tap one of the entries suggested for you.
- Not there? Tap **Browse your vault**, open a section and pick an entry. Or use
  **Search your vault** to look through every section.
- Type in **Your new value** to save a new entry and share that.
- Turn off the switch to keep it to yourself. You can still sign in.

Pick an entry with a different key, and the app adds an alias to your vault, so
it's ready next time.

Your entries come from the workspace you're in. Have more than one? Tap the
workspace name on the same screen to switch. New entries are saved there too,
and the app stays in that workspace afterwards.

Anything added for a service goes in its own section of your vault, named after
the service, like **Sign-in · showdown.example**. So you can always see what a
service asked you to add. To go to that service, open the section's menu and
choose **Open service**. Entries you already had stay where they are.

## Sign out of a service

The service keeps its own login, so sign out there. **Pause** and
**Disconnect** don't do that for you, so you may stay signed in until you do.
It may also have saved what it learned, like your email address, and only the
service can delete that.
