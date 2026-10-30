# Add people

People sign in with a **passkey**: a key their device keeps and unlocks with a
fingerprint, face or PIN. There are no passwords, so there's nothing to reuse,
leak or phish.

A passkey only works at the address it was made for. So people sign in on
your server's own page, `/passkey`. The app opens it in the browser, and the
page sends them back signed in. On Android it opens inside the app, in a
browser tab (a Custom Tab) that closes itself once they're signed in. Without
a browser that offers one, and on the desktop, it opens in the browser.

People must reach that page at your server's real address over HTTPS (your
`DOMAIN`). On a development machine, use `http://localhost:<port>` — not
`127.0.0.1`, which no passkey can be bound to.

People can't sign themselves up: registration is **off by default**, so only
you can add people to a fresh server. With `ALLOW_SIGNUPS=false`, the sign-in
page says the server is invite-only, and the registration endpoint refuses.

## Create an account

Run this on the server:

```bash
docker compose exec api /pb/revoked user upsert someone@example.com
```

It creates the account if needed and prints a **one-time link**, good for 24
hours. Send it to the person. They open it on the device they'll use, save a
passkey, and sign in from the app. The command writes straight to the
application, so it works even with signups off.

You can also:

- set the `USER_EMAIL` [seed](env.md#seed-accounts). The account is created
  on boot, and until it has a passkey every start logs a fresh link;
- add the user in the superuser dashboard at `/_/` (users collection). Then
  run `user upsert` to get a link — an account made there has no way in yet.

## Someone lost their devices

If someone loses every device with their passkey on it, they can't sign in.
Nothing they know can get them back in — that's the point. Run `user upsert`
for their address again and send them the new link. Their old passkeys keep
working until they remove them under **Settings → Account → Passkeys**.

To avoid this, tell people to keep a passkey on more than one device.
**Settings → Account → Passkeys** adds one on the device in hand, or copies a
fifteen-minute link to open on another. Many password managers and platforms
also sync passkeys across a person's devices by themselves.

## Moving from passwords

Accounts made before passkeys keep everything they own, but their password
no longer signs them in. Run `user upsert` once per address and send out the
links.

## The superuser

The `/_/` dashboard account is separate from app accounts and still signs in
with a password. Create it on your first visit to `/_/`, through the install
link printed in the logs, or with the `ADMIN_EMAIL`/`ADMIN_PASSWORD` seed
pair. It manages collections and settings. It can't sign in to the app.

## Let people sign themselves up

Set `ALLOW_SIGNUPS=true` and restart. Anyone who can reach your server can
then create an account with an email address and a passkey.

That address is whatever they typed. To make sure it's theirs, also set
`SIGNUP_VERIFY_EMAIL=true` and set up the [mail server](env.md#mail). The
sign-in page then mails a 6-digit code, and only the right code lets them save
a passkey. A code lasts ten minutes and allows five guesses. An address gets
at most one code a minute and five an hour. Accounts confirmed this way are
marked verified.

The sign-in page shows new people where they are (*Step 2 of 3 · Confirm
email*: email, code, passkey; two steps without confirmation). It's in English
and German, picked from the browser and switchable at the top. The code is
mailed in the language the page was showing. If someone with an account picks
*Create an account* anyway, the browser offers their passkey when they tap the
email field (where the browser supports it) and signs them in with it.

Inviting members into an *existing* workspace is separate. It happens in the
app (workspace invites) and works whatever this setting says.

## What people see first

On first login, people land in onboarding. They either create a workspace or
join one by pasting an invite key. A new workspace is called *Personal* unless
they rename it. They also name themselves for their signing identity — the
app suggests a name from their email address, and it's what recipients of
their shares and requests see. If a link brought them to the app — a link
proposal, a connect request, an invite — it opens once they're through.
