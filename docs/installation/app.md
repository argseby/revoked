# Install the app

Download the app from the [latest release](https://github.com/argseby/revoked/releases/latest).
Every release has native builds for **Linux**, **Windows** and **Android**,
built by CI from the tagged commit.

On the desktop, you have one manual step: register the `revoked://` link
scheme. Shares and requests travel as `revoked://` links, so there's no web
page for a phisher to copy. But until the scheme is registered, clicking such
a link does nothing at all.

## Linux

Extract the tarball. From inside the extracted folder, run:

```bash
./packaging/install.sh
```

It installs to `~/.local`, adds the desktop entry, and registers the
`revoked://` scheme.

You need **libsecret** (it comes with GNOME Keyring or KWallet). Without it
the app runs, but it can't keep an identity's private key in the system
keychain, so you can't sign or do handshakes.

## Windows

Extract the zip. Then either run the installer, or edit the two paths in
`packaging/register-scheme.reg` to point at your extracted folder and
double-click it.

Builds aren't signed yet, so SmartScreen warns you on first run. Click
*More info → Run anyway*.

## Android

Install the signed APK from the same release page. Your phone asks you to
allow installs from that source. The `revoked://` scheme registers itself —
nothing else to do.

Don't install the file named `-testing-only`. It's signed with a throwaway
debug key, so it can't update an earlier install. You'd have to reinstall, and
that wipes your identities' private keys. They never left the device, so
nothing can bring them back.

## Next

To connect to a server and open your first link, see
[the guide](../guide/index.md#first-start).
