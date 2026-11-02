# Try it in 5 minutes

Share a record, change it, and take it back. You watch the link follow along
at every step. You need the app and nothing else.

!!! warning "This uses the official test server"
    `api.revoked.link` is experimental and for testing, with no guarantees for
    your data. Keep nothing there you can't lose. For real data,
    [run your own server](../installation/index.md).

<video controls preload="none" playsinline poster="https://revoked.link/video/film-share-wide.jpg" style="width:100%" aria-label="A short film showing how to share records, decide who gets in, watermark files and revoke a link. It has no sound.">
  <source media="(max-width: 599px)" src="https://revoked.link/video/film-share-tall.mp4" type="video/mp4">
  <source src="https://revoked.link/video/film-share-wide.mp4" type="video/mp4">
</video>

## 1. Connect to the test server

[Install the app](../installation/app.md) and open it. On the login screen, tap
the server and enter:

```text
https://api.revoked.link
```

Press **Test**, then **Save**.

**You should see** the server's address on the login screen. The app marks it
as the official server.

## 2. Create an account

Sign up with your email address. The server mails you a 6-digit code, and then
you save a passkey on your device. There's no password.

**You should see** your new workspace. It's called *Personal* unless you
changed it.

## 3. Add a record

Choose **New**, add a record, and fill it in:

| Field | Enter |
|---|---|
| Label | `Wi-Fi password` |
| Value | `first-password` |

**You should see** it in your **Vault**, with the key `wi_fi_password`. The app
makes the key from the label.

## 4. Share it

Press **Share** on the record, and create the link. You can leave the rest as
it is. Copy the link. It looks like this, and the last part is its address:

```text
revoked://s/api.revoked.link/k7Qx…
```

Open it in a browser, with your own address in place of `k7Qx…`:

```text
https://api.revoked.link/s/k7Qx…
```

**You should see** a plain page with a button. Press it, and your value shows.

Or read it the way a program would:

```bash
curl "https://api.revoked.link/s/k7Qx….json"
```

```json
{
  "label": "Wi-Fi password",
  "records": [
    { "key": "wi_fi_password", "label": "Wi-Fi password", "type": "text",
      "value": "first-password" }
  ],
  "viewCount": 1
}
```

Every read counts as a view. The real answer has a few more fields.

## 5. Change the value

In your vault, change the value to `second-password`. Don't touch the link. Run
the same command again, or reload the page.

**You should see** `second-password`. Everyone with the link sees the new one,
and you never sent anything.

## 6. Pause it, then revoke it

Open the link under **Shares** and press **Pause**. Run the command again.

```json
{ "code": "link_paused", "message": "This link is paused by its owner and is temporarily unavailable.", "status": 403 }
```

Press **Activate**, and it works again. Now press **Revoke** and run it once
more.

```json
{ "code": "link_revoked", "message": "This link has been revoked.", "status": 410 }
```

Revoking can't be undone. The link is gone for good, and it stopped working the
moment you pressed the button. Not at the next sync.

## If something doesn't match

| What you see | What to do |
|---|---|
| **Test** fails | Check the address starts with `https://`, and that you're online. |
| No code in your mail | Check your spam folder, and that the address is right. A code lasts ten minutes. |
| Still the old value | Make sure you changed the record this link points to. |
| `"requiresPassword": true` | You added a password to the link. Add `?password=…` to the address, or make a new link. |

## Next

- [Do the labs](../labs/index.md): sign-in, requests, attestations and connected tools.
- [See how it works](../how-it-works/index.md), with a diagram of every flow.
- [Run your own server](../installation/index.md), when you're ready for real data.
