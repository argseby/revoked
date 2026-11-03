# Passkeys

A passkey signs in to Revoked without a password. It is unlocked with a
fingerprint, face or PIN, and stays on the device or in the password
manager that saved it. The server keeps only its public half.

Passkeys are managed under **Settings → Passkeys**. A passkey on each
device prevents lockout when one of them is lost.

## Adding a passkey

A new passkey is saved on a page of the server, opened in the browser.
Two ways lead there:

| Control | Use |
|---|---|
| **Add passkey** | Opens the page on the current device. In the top bar, or the floating button on a phone. |
| **Copy link for another device** | Copies a link to open on a different device. The link works once, within 15 minutes. |

On the page, **Save passkey** asks the device where to store it, such as
the phone itself or a password manager. Once saved, sign-in with that
passkey is available in the app on that device. Back in the app, the new
passkey appears in the list.

A device can hold only one passkey per account. The page refuses a second
one and says so.

## Names and the list

Each passkey is named after the browser and system it was made on, for
example "Safari on iPhone" or "Chrome on Windows", so passkeys can be told
apart. The name is set when the passkey is saved.

The list shows every passkey on the account, newest first, with the day it
was added and the day it was last used, or "never used".

## Removing a passkey

Tapping a passkey offers **Remove**. A removed passkey stops signing in at
once. It stays on the device or in the password manager until deleted
there.

The last passkey cannot be removed, because without it there is no way to
sign in. Its option reads **Remove (requires another passkey)** until a
second passkey is added.

If the passkey also opens end-to-end encrypted records, removing it from
a device that holds the key takes it off the device list too. Otherwise
it stays listed under **Settings → End-to-end encryption**, where it can
be removed separately. See [End-to-end encryption](encryption.md).

## Passkeys and encrypted records

On systems that support it, a passkey can also open end-to-end encrypted
records. Signing in with that passkey on a new device then opens them
there without a code from another device. Not every passkey can do this;
older systems and some hardware keys cannot. The details are in
[End-to-end encryption](encryption.md#devices).

Anyone able to use the passkey can open those records. A passkey synced
through a provider or shared through a password manager extends that
access to everyone and every device it reaches.

## Limits

- Passkeys work only at the server's own address, and only in a browser
  that supports them.
- Signing in has no password fallback. With every passkey lost, a new one
  can be added only through a link from the server operator.
- The server never receives a passkey's private key. See
  [what the server can and can't see](../how-it-works/index.md#what-the-server-can-and-cant-see).
