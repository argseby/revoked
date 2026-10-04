# Tools & link proposals

A [request](requests.md) is one way of getting data from someone: a form is
published, and the other side answers it. A **link proposal** works the other
way round. A tool — a web page, a script, someone else's service — names the
records it would like to see shared, and the share is created by the person
who holds them, on their own server. Only record keys are part of a proposal,
never values, and the vault itself stays out of the tool's reach.

| | Request | Link proposal |
|---|---|---|
| Started by | The person who wants the data | A tool, on behalf of the person who holds it |
| Travels as | `revoked://r/…` → a form at `/r/{slug}` | `revoked://p?label=…&keys=…` |
| Where the data ends up | In the requester's **Data** tab | In a share of the vault's owner, under **Links** |
| Held by the other side | The answers (typed, or a revocable grant) | At most the link, and only once it was handed over |

[Notfallkarte](notfallkarte.md) is a complete example: a web page on which a
proposal becomes an emergency card for the wallet.

## Reviewing a proposal

A proposal opens the app on **Link proposal from …**. The name after *from*
is the one the tool gives itself, and it is shown as a claim. Next to it
stands the tool's web address, which is what actually identifies it.

Every record the share would include is listed, read from the vault by the
keys the tool named. Keys the vault does not hold yet can be filled in right
there: a proposal may name a [template](templates.md) describing its keys,
which gives the app a label and an input for each of them. Values entered
this way are saved to the vault like any other record.

Nothing is created before **Continue** is pressed. **Decline** returns to the
tool without anything having been shared.

A proposal may also carry share settings — an expiry in days, a watermark
stamp, a purpose such as `application` — and the share is created with
exactly those. A proposal that is malformed in any part is refused as a whole
(*This link doesn't work*) rather than repaired into something the tool did
not mean.

## Connected tools

Once a proposal has been confirmed, a tool learns nothing further on its own.
For that it needs to be **connected**, either as part of a proposal (a
*Connect …* step before the review) or separately, for example from the
tool's settings. A connected tool can see what became of the links it
proposed: whether they are active, paused, revoked or expired, and how often
they were opened. Their contents are never part of that, and neither is
anything else in the vault.

Two further permissions are granted or refused per tool, each shown together
with the reason the tool gave for asking:

| Permission | Meaning |
|---|---|
| **May revoke its links** | A link that came from the tool's own proposal can be ended by it — for example when the printed card it belongs to is deleted. Shares can be ended this way, but never started or read. The revocation is notified like any other. |
| **May receive links** | The finished link is handed to the tool, so it doesn't have to be copied over by hand. Shares containing a **hidden** record or a file are never handed over; those are copied manually. |

### Other browsers and phones

The app answers a tool by opening the tool's page again, in whichever browser
the system uses for links — not necessarily the one the process started in.
A tool that already knows the server can avoid that by collecting the answer
itself. In that case a short code such as `83C-047` is shown on the page, and
the same code appears in the app before anything is connected. When both
match, the original tab continues, even if the confirmation happened on a
phone.

A tool already connected in one browser can be admitted to another one
(**Let this browser in**). No new permissions come with that; the other
browser receives the same ones as before.

## Managing connections

**Settings → Workspace → Connected tools** lists every tool, together with
when it was connected and last used, when the connection ends, and the links
it proposed. Its two permissions can be changed there, each of its links can
be opened or revoked, and the tool can be disconnected. Disconnecting ends
every token it holds at once; the links themselves remain and keep working.

A connection lasts **90 days** from the last time it was confirmed in the
app, and it is only renewed by confirming it there again — a tool has no way
of keeping itself alive. Everything a tool does (connecting, reading,
revoking, disconnecting) is recorded in the audit log under its web address.
