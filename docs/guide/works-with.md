# Works with Revoked

**Works with Revoked** is a tab in the app that lists services and tools
built on Revoked, such as [Notfallkarte](notfallkarte.md). Each listing is
reviewed before it appears. A tool that is not listed works exactly as well;
the list only helps to find one.

## The list

The tab sits after Contacts. On a phone it is reached through **More**, from
the card on **Home** while no tool is connected, or from **New → Service**.
It belongs to the *Connected tools* feature and is hidden with it.

Services are searched by name, address, description and the records they
propose. **Filter and sort** narrows the list by what a service does (share,
collect, prove, sign in, connect), its category, the access it may ask for,
where it runs, its languages and its listing mark. Services already
connected are listed first and marked **Connected**.

A service's page shows what it can see, the permissions it may ask for with
the reason it gives, the records it proposes, who runs it, and links to its
privacy policy, imprint, source code and security contact. **Open service**
opens its website. Nothing is proposed or connected from the list itself;
that still happens through the service, as described in
[Tools & link proposals](tools.md). **Report a problem** opens an issue about
the listing.

## Marks

| Mark | Meaning |
|---|---|
| **Listed** | Reviewed, and confirmed by the service on its own website |
| **Unverified** | Reviewed, but not yet confirmed by the service on its own website |
| **Unavailable** | The service has not answered for a while; it is removed if that stays so |
| **Built by Revoked** | Made by the Revoked project; always counts as confirmed |

A listing is not an endorsement. The service's address remains what
identifies it, and it is shown on every proposal as before.

## On proposal and connect screens

When a proposal, a connect request or a sign-in comes from a listed address,
a **Listed** or **Unverified** chip appears beside the address. Selecting it
opens the listing in a sheet, without leaving the proposal.

When a listed service asks for more than its listing declares, the screen
says so above the switches:

- on **Connect**, a switch the listing does not name starts off;
- on a **link proposal**, a record the listing does not name starts
  unticked.

Either can still be turned on. The comparison happens on the device against
the list the app holds; the service learns nothing about it. Matching works
because a tool's address is bound to the link: the answer only ever goes
back to that address, so a page claiming another tool's address cannot
receive it.

## Where the list comes from

Every listing is a file in the repository's `services/` folder and is added
or changed only through a reviewed pull request. A copy of the list ships
with the app, so it works offline. A newer copy is read from the repository
at most once a day; only the file is fetched, and no search or selection
leaves the device.

How a service is listed, and what it must meet, is described in
[`services/README.md`](https://github.com/argseby/revoked/tree/main/services).
