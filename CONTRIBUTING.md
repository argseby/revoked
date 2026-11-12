# Contributing

How to run Revoked from source, how releases work and how the apps get built.
To use Revoked or run your own server, start at the
[docs](https://docs.revoked.link) instead.

## What's in here

| Path | |
|---|---|
| `cmd/`, `util/`, `migrations/`, `tests/` | The Go API, built on [PocketBase](https://pocketbase.io) |
| `app/` | The Flutter app |
| `web/` | A small Svelte web client for application links |
| `docs/` | The source of [docs.revoked.link](https://docs.revoked.link) |
| `examples/` | Working examples, such as the Corner Shop sign-in demo |
| `deploy/`, `Dockerfile`, `docker-compose.yml` | Running it on a server |
| `app/packaging/` | Desktop scheme registration and install helpers |
| `video/` | The website's films, rendered with Remotion |

[ARCHITECTURE.md](ARCHITECTURE.md) explains how it's built, and
[E2EE.md](E2EE.md) covers end-to-end encryption.

## Development

You need Go for the server and Flutter for the app.

```bash
cp .env.example .env                            # DOMAIN is required
go run ./cmd/revoked serve --http="0.0.0.0:3000"
```

Always run it from the repository root. The server looks for `.env`,
`pb_data/` and its root key in the current directory, so a different
directory means a different server.

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after any store change
flutter run
```

| Task | Command |
|---|---|
| Build / vet | `go build ./...` · `go vet ./...` |
| Test | `go test ./... -count=1 -p 1 -timeout 10m` |
| Format | `gofmt -w .` · `cd app && dart format .` |
| App checks | `cd app && flutter analyze && flutter test` |

The Go tests start a real PocketBase on `127.0.0.1:5559` and talk to it over
HTTP. They need no outside services, but they do use that port — so run them
with `-p 1`.

## Documentation

Documentation source lives in `docs/`. Endpoint reference pages under
`docs/api/reference/` are generated from `docs/api/openapi.yaml`; changes to
those pages belong in the specification or `tools/docs/gen_api_reference.py`.
The handwritten guides explain when and how to use that contract.

Task and integration pages should include:

- A plain-language purpose and one concrete scenario before protocol details.
- Prerequisites, including which system is running, which credential is needed
  and which permissions or sections it must have.
- Examples beside the behavior they explain. Commands define their variables;
  placeholders are identified, and partial snippets say what is omitted.
- The expected response or visible result, including valid empty results and
  declined optional data.
- Common failures with specific checks, plus a link to the complete example or
  endpoint reference where one exists.

Examples use the shipped routes, field names and UI labels. Credentials from
an API key, connection, Revoked session and service sign-in are distinguished
explicitly. Revocation describes future access; it cannot recall information
already copied. Examples should be understandable without an AI assistant or
reading the source implementation.

The local documentation build uses the same generation and strict build as CI:

```bash
python3 -m venv .venv
.venv/bin/pip install -r docs/requirements.txt
.venv/bin/python tools/docs/gen_api_reference.py
mkdir -p docs/assets/brand
cp app/assets/icon/*.svg docs/assets/brand/
.venv/bin/zensical build --strict
```

New pages are also added to the explicit navigation in `zensical.toml`.

## Commits and releases

Write [Conventional Commits](https://www.conventionalcommits.org) as
`type(scope): message`. The **type** sets the version. The scope is a free
label (`app`, `api`, `docs`, `site`, …) and never does.

**Allowed labels are: 
app, api, docs ci, site, core, tests**

| Type | Version bump | Lands in the changelog as |
|---|---|---|
| `breaking:` (or `breaking!:`) | major (minor while still 0.x) | ⚠️ Breaking Changes |
| `feat:` | minor | ✨ Features |
| `fix:` | patch | 🐛 Bug Fixes |
| `docs:` `chore:` `ci:` `refactor:` `test:` `style:` `perf:` | **none — no release** | not listed |

If none of the commits pushed to `main` is a `fix`/`feat`/`breaking`, there's
no tag and no release.

**What runs when:**

- **Every PR and push** (`main`/`dev`): CI — Go build + tests, Flutter
  analyze + tests.
- **Merge to `main` with a `fix`/`feat`/`breaking` commit**: the release
  workflow tags, writes the changelog, creates the GitHub release, then
  builds the Linux, Windows and Android apps and attaches them to it.
- **Merge to `main` touching only `docs/`**: the docs site redeploys to
  Pages; no version, no release, no desktop builds.

Work on `dev` or a `type/short-description` branch and open a PR into `dev`.
`main` is protected and triggers releases.

## Building the apps

Each release builds Linux, Windows and Android apps and attaches them
(`.github/workflows/desktop.yml`). Flutter can't cross-compile for the
desktop, so each one builds on its own runner.

Android won't install an unsigned APK, so every build gets signed. Put your
keystore in the repository secrets (`ANDROID_KEYSTORE_BASE64`,
`ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`) and CI
signs with it. Without them, CI uses a fresh debug key on every run. That APK
installs, but it can't update an earlier install. The forced reinstall wipes
the identities' private keys, which never left the device and can't be
recreated. That's why the file is named `-testing-only`. None of this involves
the Play Store.

Create the keystore once and keep the file safe. If you lose it, no future
build can update an installed app:

```bash
keytool -genkey -v -keystore revoked-release.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias revoked
base64 -w0 revoked-release.jks   # paste into ANDROID_KEYSTORE_BASE64
```

Windows builds are unsigned unless a certificate is set up, so SmartScreen warns
on first run.
