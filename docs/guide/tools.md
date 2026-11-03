# Tools & link proposals

Some tools need your data: an emergency-card maker, an application form,
someone else's service. With a **link proposal**, the tool asks for the
records it needs, and you create the share yourself, on your own server.
The tool only ever names keys, never values, and it never gets into your
vault unless you let it read it.

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

## Let a tool suggest a request or an attestation

A tool can fill in more than shares for you. It can suggest:

- a **request**, to collect answers from other people with one of your
  templates. The app opens **New request** with the template, the title and
  the end date filled in.
- an **attestation**, to confirm something about someone in your domain's
  name. The app opens **Confirm something about someone** with the kind and
  the details to fill in. You set every value.
- a **check**, to ask someone to show you an attestation. The app opens
  **See someone's attestation** with what to ask for.

Each form says **Proposed by …** at the top, with the tool's web address
next to the name it gave itself. Check everything before you save. Nothing
happens until you do.

If you connected the tool, it can then follow what you saved: whether a
request is still open and how many people answered, whether an attestation
was accepted, and the result of a check, with what the person chose to
show. It never sees the answers to a request or the values in an
attestation.

## Connect a tool

Once you confirm a proposal, the tool learns nothing more on its own. For
that, you **Connect** it: as a step before the review, or separately, for
example from the tool's settings. A connected tool can see what became of
the links it proposed: active, paused, revoked or expired, and how often
they were opened. It can follow the requests, attestations and checks it
suggested the same way. It never sees what they contain, or anything else in
your vault, unless you give it a section or let it read your vault.

Everything else is a switch, per tool. Under the switches the app shows the
reason the tool gave for asking:

| Switch | What it allows |
|---|---|
| **Vault section** | The tool gets a section of your vault, named after it, to keep what it saves for you. Pick **Read**, and it only sees what you put there. Pick **Manage**, and it can also add records, and change or delete the ones it added. It can't see the rest of your vault. |
| **Manage shares** | The tool shares what is in its section without asking you each time. You see every share in the app, and can stop it. |
| **Manage requests** | The tool sends requests in your name without asking you each time. Only when you confirm on this device, never with a code. |
| **Revoke its links** | The tool can revoke the links and requests it proposed, for example when you throw away the printed card. You're notified like for any other revocation. |
| **Receive links** | When you create a link it proposed, the tool gets it, so you don't copy it over. Links with files or hidden values you always send yourself. |
| **Read vault** | Only when the tool asks, and off until you turn it on. The tool can see the values of your records, but not your encrypted ones, and it can't change anything. What it sees can't be taken back. [Your AI assistant](assistant.md#let-it-read-your-vault) explains what to weigh. |

Switches marked **Sensitive** let the tool do something you can't take
back: hand out links, ask people for data in your name, or read your whole
vault. Turn them on only for a tool you trust with that.

### Confirm on another device

To answer a tool, the app opens the tool's page again in your default
browser. That may not be the browser you started in. A tool that already
knows your server can avoid this by picking up the answer itself. It then
shows a short code such as `83C-047` on its page, and the app shows the
same code before anything is connected. Continue only if both match. The
original tab then carries on, even if you confirmed on your phone.

Already connected in one browser? **Let this browser in** admits another
one. It gets the same permissions as before, nothing more.

## Give a tool its own section

A tool that keeps things for you, like a packing list or a game save, can
keep them in your vault instead of on its own servers. Leave **Vault
section** on when you connect it. The app shows the name of the section it
will get:

- Everything it saves there is yours. You see it in your vault, marked
  **Added by** and the tool's name.
- It can change only what it added. Records you put in its section are
  yours, and it can only read them.
- The section stays in your vault when you disconnect the tool. Turn
  **Vault section** off later, and the tool can't use it any more. Turn it
  on again, and it gets the same section back.

Putting one of your records into a section a tool can read lets the tool
read it. The app asks first, and names the tool. Tap **Add to section** only
if that's what you want. To take it back, remove the record from the
section.

Want a tool to read more? Open it under **Settings → Connected tools**. In
**Vault sections**, every section of yours has a switch: turn one on and the
tool can read it, turn it off and it can't any more. The section stays in
your vault either way. Its own section comes first, marked **Its own**.

## Give your scripts a key

Your own scripts, like one that keeps a record up to date, use an **API
key** instead. You'll find them under **Settings → Developer → API keys**.
Tap **New API key** (**New** once you have one), tick what the key may do,
and, if it should use your vault, pick the **Sections it can reach**. The
key reaches only those.
You see the key once: copy it then. To stop a key, revoke it in the same
list.

## Manage your connected tools

**Settings → Connected tools** lists every tool: when you connected it,
when it was last used, when the connection ends, and everything it
proposed: its links, requests, attestations and checks. There you can
change its permissions and sections, or open or revoke each of its links. **Read your
vault** shows only while it's on. You can turn it off there. To turn it on
again, the tool has to ask when it connects. Tap a
request, an attestation or a check to open it where it lives.

### Take a break from a tool

Not sure you still want it? Turn off **Active**. The tool can't do anything,
its links stop opening, and its requests stop taking answers. Turn it back
on when you want it back, and everything works as before. Any link you paused yourself stays paused.

### Cut a tool off for good

Tap **Disconnect** and the tool is cut off at once. Its links and requests
stay yours and keep working, unless you also tick **Revoke its links too**,
which closes its requests as well. Attestations you issued stay as they are.

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
