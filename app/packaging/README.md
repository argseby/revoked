# Desktop packaging

`revoked://` links are how shares and requests reach people, and a desktop
build does not register that scheme by itself — the same way Android did
nothing with them until its intent filter existed. These files close that gap.

## Linux

The release tarball extracts to a directory containing the binary, its `data/`
and `lib/`, and this `packaging/` folder. From inside it:

```sh
./packaging/install.sh          # installs to ~/.local, registers revoked://
```

It needs `libsecret` at runtime (GNOME Keyring or KWallet). Without it the app
runs but cannot store an identity's private key, so signing is unavailable.

## Windows

Extract the zip, then either run an installer that registers the scheme, or
edit the two paths in `register-scheme.reg` to match the extraction directory
and double-click it.

Builds are unsigned unless a certificate is configured in CI, so SmartScreen
will warn on first run. For a product whose entire pitch is verifiable trust,
signing is worth the certificate cost before any public release.
