# Example: Notfallkarte

*Notfallkarte* (German for emergency card) is a small web page that
generates a wallet-sized card with a name and a QR code. In an emergency,
scanning it shows the emergency contact, allergies, medication and doctor
**as the vault holds them at that moment**, not as they were when the card
was printed. A change in the vault appears on the card immediately; a
revoked link leaves the card leading nowhere.

It is a complete [link proposal](tools.md) tool and a reference for
building others. It is a static page: no account, no backend, no access to
the vault. Its source lives in a separate `notfallkarte` repository.

## Creating a card

1. **On the card page**, the name for the card is entered and the groups a
   helper should see are ticked. Insurance and organ donation start
   unticked, because anyone holding the card can read what it leads to.
2. **Continue in revoked** opens a proposal link in the app. It names the
   card and a list of record keys, never a value (wrapped here for
   readability):

    ```text
    revoked://p?label=Notfallkarte%20Max%20Mustermann
      &keys=full_name,contact_name,contact_phone,contact_relation,blood_type,allergies,medications,doctor_name,doctor_phone
      &from=Notfallkarte
      &template=Medical%20emergency%20card
    ```

   Without the app installed, the link opens nothing. The page detects this
   and links to the Revoked download. After installation, **Open Revoked**
   retries; the card is still in the list. The app keeps the proposal
   through sign-up and setup, and opens it afterwards.

3. **In the app**, the share to be created is shown. The keys belong to the
   built-in *Medical emergency card* template, so anything missing from the
   vault is asked for once, with the matching label. The link does not
   expire, because the card has to work whenever it is needed.
4. **Continue** creates the share on the owner's server.
5. **The link returns to the card page**: automatically if the page is
   connected and allowed to receive links, or by copying it in the app and
   pasting it into the page. The page draws the QR code from it and offers
   the card as a PNG (300 dpi) or as an A4 sheet to print at true size.

Once connected, the page also shows each card's status: active, opened N×,
paused, revoked. If permitted, removing a card revokes its link. In
another browser, the page finds existing cards again by their label and a
reference it added to the proposal. Nothing is stored on the server for
the page, and the page's own storage holds only names and ticked groups.

## Visibility

| | Sees |
|---|---|
| The card page | The entered name, the ticked groups, and the link if it was handed over. Never a value. |
| The owner's server | Everything, as with all data it holds. |
| Whoever scans the card | What the link shows at that moment, for as long as it is active. |

The card itself is the key: the link opens the data. That is the purpose
of an emergency card, so the groups should be chosen with this in mind. A
lost card is handled by revoking its link; a new card with a new link
takes about a minute.

## Self-hosting

The page consists of static files. It only talks to the server the app
names on the way back, so one instance works with every Revoked server:

```bash
cd notfallkarte
cp .env.example .env
docker compose up -d --build
```

Like the Revoked stack, the compose file publishes no port and joins the
reverse proxy's network (`proxy-network` by default). The proxy routes a
dedicated host name, such as `notfallkarte.example.com`, to
`notfallkarte:8080`. If the Revoked server runs with a restricted
`--origins` list, the card page's address must be added to it: once
connected, the page talks to the server from the browser.
`REVOKED_DOWNLOAD_URL` in `.env` sets where **Get Revoked** leads (https
only; empty means Revoked's latest release).

Building a similar tool, including a minimal working page, is covered in
[Building a tool](../api/tools.md).
