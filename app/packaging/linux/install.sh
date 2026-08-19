#!/usr/bin/env sh
# Installs a Revoked build into ~/.local so `revoked://` links open it.
# Run from inside the extracted release directory.
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
APPDIR="$PREFIX/lib/revoked"

mkdir -p "$APPDIR" "$PREFIX/bin" "$PREFIX/share/applications"
cp -r ./* "$APPDIR/"

ln -sf "$APPDIR/revoked_app" "$PREFIX/bin/revoked"

sed "s|^Exec=revoked|Exec=$PREFIX/bin/revoked|" \
    "$APPDIR/packaging/revoked.desktop" > "$PREFIX/share/applications/revoked.desktop"

# Registers the scheme handler; without it the link opens nothing.
update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
xdg-mime default revoked.desktop x-scheme-handler/revoked 2>/dev/null || true

echo "Installed. Check with:  xdg-open 'revoked://s/test'"
