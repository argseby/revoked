# Installing the app

Every [release](https://github.com/argseby/revoked/releases/latest) ships
native bundles for **Linux**, **Windows** and **Android**, built by CI from
the tagged commit.

One manual step matters on the desktop platforms: registering the
`revoked://` URL scheme. Shares and requests travel as `revoked://` deep
links precisely so there is no web page for a phisher to imitate — but an
unregistered scheme means every such link silently does nothing.

## Linux

Extract the tarball and run, from inside the extracted directory:

```bash
./packaging/install.sh
```

It installs to `~/.local`, writes the desktop entry, and registers the
`revoked://` scheme.

Runtime requirement: **libsecret** (present with GNOME Keyring or KWallet).
Without it the app runs but cannot store an identity's private key in the
system keychain, so signing and handshakes are unavailable.

## Windows

Extract the zip, then either run the installer, or edit the two paths in
`packaging/register-scheme.reg` to your extraction directory and double-click
it.

Builds are currently unsigned, so SmartScreen warns on first run —
*More info → Run anyway*.

## Android

Install the signed APK from the same release page. Installing outside a
store needs the usual "allow from this source" confirmation; the
`revoked://` scheme registers itself through the app's manifest — no manual
step.

Avoid the artifact named `-testing-only`: it is signed with a throwaway
debug key, so it cannot update a previous install, and the forced reinstall
wipes the identity private keys — which never left the device and cannot be
regenerated.

## After installing

Connecting to a server and opening your first link are covered in
[the guide](../guide/index.md#first-start).
