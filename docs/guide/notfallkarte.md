# Example: Notfallkarte

*Notfallkarte* (German for emergency card) is a small web page on which a
bank-card-sized card for the wallet is made. The card carries a name and a QR
code. Whoever scans it in an emergency sees the emergency contact, allergies,
medication and doctor **as the vault holds them today**, not as they were
when the card was printed. A change in the vault shows on the card straight
away, and once the link is revoked, the card leads nowhere.

It is a complete [link proposal](tools.md) tool and serves as the reference
for building others: a static page without an account, without a backend and
without access to the vault. Its source lives in its own `notfallkarte`
repository.

## The flow, step by step

1. **On the card page**, the name for the card is entered and the groups a
   helper should see are ticked. Insurance and organ donation start unticked,
   since anyone holding the card can read what it leads to.
2. **Continue in revoked** opens a proposal link in the installed app. It
   names the card and a list of record keys, never a value (wrapped here for
   reading):

    ```text
    revoked://p?label=Notfallkarte%20Max%20Mustermann
      &keys=full_name,contact_name,contact_phone,contact_relation,blood_type,allergies,medications,doctor_name,doctor_phone
      &from=Notfallkarte
      &template=Medical%20emergency%20card
    ```

   Without the app installed, the link opens nothing. The page notices that
   nothing took over and says so, with a link to get revoked. After
   installing, **Open Revoked** is pressed once more: the card is still in
   the list, and the app carries the proposal through sign-up and workspace
   setup and opens it once they are done.

3. **In the app**, the share it would create is shown. The keys belong to the
   built-in *Medical emergency card* template, so anything the vault does not
   hold yet is asked for once, with the right label. The proposal sets no
   expiry, since a card has to work on the day it is needed.
4. **After confirmation**, the share is created on the owner's own server, by
   the app.
5. **The link returns to the card page** — either automatically, when the page
   is connected and allowed to receive links, or by being copied in the app
   and pasted into the page. The QR code is drawn from it, and the card is
   offered as a PNG (300 dpi) or as an A4 print sheet at true size.

Once connected, the page also shows the status of each card — active, opened
N×, paused, revoked — and, where that was allowed, the link is revoked when a
card is removed. Cards are found again in another browser through the link's
label and the page's own reference (`<card id>.<groups>`), which was set on
the proposal. Nothing is kept on the server for the page, and its own storage
holds no more than names and ticked groups.

## Who knows what

| | Knows |
|---|---|
| The card page | The name entered, the ticked groups, and the link if it was handed over. Never a value. |
| The owner's server | Everything, as always — it belongs to the owner. |
| Whoever scans the card | What the share resolves to at that moment, for as long as it is active. |

The card itself is the credential: the link opens the data, which is the
whole point of an emergency card. The groups are best chosen with that in
mind. A lost card is dealt with by revoking its link; a new card with a new
link takes about a minute.

## Self-hosting

The page consists of static files and only talks to the server the app names
on the way back, so a single deployment works with every revoked server:

```bash
cd notfallkarte
cp .env.example .env
docker compose up -d --build
```

Like the revoked stack, the compose file publishes no port and joins the
reverse proxy's network (`proxy-network` by default). The proxy points at
`notfallkarte:8080` under a host name of its own, for example
`notfallkarte.example.com`. A revoked server running with a restricted
`--origins` list needs the card page's origin added to it, since the page
calls the server from the browser once connected. `REVOKED_DOWNLOAD_URL` in
`.env` sets where **Get Revoked** leads (https only; empty means revoked's
latest release).

How a tool like this is put together, including a minimal working page, is
described in [Building a tool](../api/tools.md).
