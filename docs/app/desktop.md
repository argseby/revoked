# Desktop install

Every [release](https://github.com/argseby/revoked/releases/latest) ships
native bundles for **Linux** and **Windows**, built by CI from the tagged
commit.

One manual step matters on both platforms: registering the `revoked://` URL
scheme. Shares and requests travel as `revoked://` deep links precisely so
there is no web page for a phisher to imitate — but an unregistered scheme
means every such link silently does nothing.

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

## First start

The app talks to `https://api.revoked.link` by default. Self-hosting? On the
login screen, open **server settings** and enter your own server's address —
it is tested and persisted before anything else happens.

## Opening links

With the scheme registered, clicking a `revoked://` link anywhere opens the
app directly on that share or request. Inside the app, **Ctrl+V** with a link
on your clipboard opens it too — and the *Open a link* dialog can verify a
link's sender against DNS before you open it.
