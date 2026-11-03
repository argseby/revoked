# End-to-end encryption

An end-to-end encrypted record is readable only on the account's own
devices. The app encrypts its value before upload, and the server stores
it without being able to read it, so a stolen database, a backup or a
curious operator reveals nothing of that value.

The feature is in alpha and has not yet been reviewed by an independent
cryptographer. It is managed under **Settings → End-to-end encryption**.

## Turning it on

**Turn on** creates the keys for this device and a recovery key. The
recovery key is shown once, as groups of characters; the last two groups
are typed back to confirm it was saved. It restores access if every
device is lost, and nobody can reset it, not even the server operator.

After that, a record is encrypted with the **End-to-end encrypted** toggle
when it is created, or with **Encrypt end to end** on an existing record.
**Stop encrypting** makes the value readable to the server again.

Files and aliases cannot be encrypted. Encrypted records cannot be shared
yet: links cannot show them, so encrypting a record removes it from its
links.

## Devices {#devices}

Only the devices on the account's device list can read encrypted records.
A new device joins in one of three ways:

| Way | How |
|---|---|
| Another device | On the new device, **Add this device** shows a code. On a device already on the list, **Add a device** scans or pastes it, and both show the same short code to compare. That device then shows a confirmation code, entered on the new device to finish. |
| A passkey | A passkey connected to encryption opens the records on any device signed in with it. **Connect your passkey** connects the one used to sign in. Some passkeys cannot do this. |
| The recovery key | **Use your recovery key** gives this device access and removes every other device from the list. They must be added again. |

**Remove** takes a device or passkey off the list. It can read nothing
encrypted from then on, but keeps copies of what it already read, so a
secret that matters should be changed. A removed device stays signed in
until **Sign out everywhere else** ends its session.

An entry added from another device appears under **New on the device
list**; **That was me** confirms it, and an unknown device should be
removed. A change this device cannot confirm shows **The device list
changed**, and the device stops encrypting and sharing keys until it is
resolved.

## Recovery key

**Replace recovery key** issues a new one; only one is valid at a time.
Without a recovery key, losing every device means losing every encrypted
record. Nobody can restore them, and the app says so.

## What stays readable to the server

Only the value is encrypted. The server still sees each record's label,
key and type, its sections, when it changed, and roughly how large it is.
An encrypted record's value on the server is always empty. See
[what the server can and can't see](../how-it-works/index.md#what-the-server-can-and-cant-see).

## Starting over

**Start over** is for when every device and the recovery key are lost. It
requires typing a confirmation phrase, then clears the device list and
permanently deletes every encrypted record that nobody else can read.
Other records are not affected. A notification records the reset, and a
device that knew the old list treats the new one as untrusted until
**I started over: rejoin** is chosen there.

## Limits

- Encrypting an existing record does not erase the past: server backups
  may still hold the old value.
- Records open only in the app, not in a browser. Other members of a
  workspace cannot read them yet and see a locked row.
- A device with malware on it is not protected.
- Whoever can use a connected passkey holds the key, including anyone a
  passkey provider or shared password manager syncs it to. The sign-in
  page that unlocks it is served by the server, so a server serving a
  modified page could capture it.
- Every device on the list has equal power. A stolen device can remove
  the others; the owner sees an alert, and the recovery key is the way
  back.
- A dishonest server can delay news of a change to the device list, and
  on a fresh device can show an encrypted record as unencrypted. The
  **End-to-end encrypted** badge is the signal to check.

Developers can find the API in
[Encrypted records](../api/reference/encrypted-records.md).
