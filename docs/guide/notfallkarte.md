# Example: Notfallkarte

*Notfallkarte* (German for emergency card) is a small web page that makes a
wallet-sized card with your name and a QR code. In an emergency, whoever
scans it sees your emergency contact, allergies, medication and doctor
**as your vault holds them today**, not as they were when you printed the
card. Change something in your vault, and the card shows it straight away.
Revoke the link, and the card leads nowhere.

It's a complete [link proposal](tools.md) tool, and the model for building
your own. It's a static page: no account, no backend, no access to your
vault. Its source lives in its own `notfallkarte` repository.

## Make a card, step by step

1. **On the card page**, enter the name for the card and tick the groups a
   helper should see. Insurance and organ donation start unticked, because
   anyone holding the card can read what it leads to.
2. **Continue in revoked** opens a proposal link in the app. It names the
   card and a list of record keys, never a value (wrapped here so it's
   easier to read):

    ```text
    revoked://p?label=Notfallkarte%20Max%20Mustermann
      &keys=full_name,contact_name,contact_phone,contact_relation,blood_type,allergies,medications,doctor_name,doctor_phone
      &from=Notfallkarte
      &template=Medical%20emergency%20card
    ```

   No app yet? Then the link opens nothing. The page notices and tells you,
   with a link to get Revoked. Once it's installed, press **Open Revoked**
   again. Your card is still in the list. The app keeps the proposal while
   you sign up and set up, and opens it when you're done.

3. **In the app**, you see the share it would create. The keys belong to the
   built-in *Medical emergency card* template, so anything your vault
   doesn't have yet is asked for once, with the right label. The link
   doesn't expire, because the card has to work on the day you need it.
4. **Press Continue**, and the app creates the share on your own server.
5. **The link comes back to the card page**: on its own if the page is
   connected and allowed to receive links, or you copy it in the app and
   paste it into the page. The page draws the QR code from it and offers
   the card as a PNG (300 dpi) or as an A4 sheet to print at true size.

Once connected, the page also shows each card's status: active, opened
N×, paused, revoked. If you allowed it, removing a card revokes its link.
In another browser, the page finds your cards again by their label and a
reference it added to the proposal. Nothing is stored on the server for the
page, and the page's own storage keeps only names and ticked groups.

## Who can see what

| | Sees |
|---|---|
| The card page | The name you entered, the groups you ticked, and the link if you handed it over. Never a value. |
| Your server | Everything, as always. It's yours. |
| Whoever scans the card | What the link shows at that moment, for as long as it's active. |

The card itself is the key: the link opens the data. That's the whole
point of an emergency card, so choose the groups with that in mind. Lost
your card? Revoke its link. A new card with a new link takes about a
minute.

## Host it yourself

The page is just static files. It only talks to the server the app names
on the way back, so one copy works with every Revoked server:

```bash
cd notfallkarte
cp .env.example .env
docker compose up -d --build
```

Like the Revoked stack, the compose file publishes no port and joins the
reverse proxy's network (`proxy-network` by default). Point the proxy at
`notfallkarte:8080` under a host name of its own, such as
`notfallkarte.example.com`. If your Revoked server runs with a restricted
`--origins` list, add the card page's address to it: once connected, the
page talks to the server from the browser. `REVOKED_DOWNLOAD_URL` in `.env`
sets where **Get Revoked** leads (https only; leave it empty for Revoked's
latest release).

To build a tool like this, including a minimal working page, see
[Building a tool](../api/tools.md).
