#!/usr/bin/env sh
# Installs a Revoked build into ~/.local so `revoked://` links open it.
# Works whether you run it from the bundle root or from inside packaging/.
set -eu

# Resolve the bundle root from this script's own location, rather than
# trusting the working directory.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$(basename "$SCRIPT_DIR")" in
    packaging) BUNDLE=$(dirname "$SCRIPT_DIR") ;;
    *)         BUNDLE="$SCRIPT_DIR" ;;
esac

if [ ! -x "$BUNDLE/revoked_app" ]; then
    echo "error: revoked_app not found in $BUNDLE" >&2
    echo "Run this from the extracted release, next to the revoked_app binary." >&2
    exit 1
fi

PREFIX="${PREFIX:-$HOME/.local}"
APPDIR="$PREFIX/lib/revoked"

mkdir -p "$APPDIR" "$PREFIX/bin" "$PREFIX/share/applications"
cp -r "$BUNDLE/." "$APPDIR/"

ln -sf "$APPDIR/revoked_app" "$PREFIX/bin/revoked"

sed "s|^Exec=revoked|Exec=$PREFIX/bin/revoked|" \
    "$SCRIPT_DIR/revoked.desktop" > "$PREFIX/share/applications/revoked.desktop"

update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
xdg-mime default revoked.desktop x-scheme-handler/revoked 2>/dev/null || true

echo "Installed to $APPDIR"
echo "Binary:  $PREFIX/bin/revoked"
echo "Test:    xdg-open 'revoked://s/test'"
[ -n "${PATH##*$PREFIX/bin*}" ] && echo "Note: $PREFIX/bin is not on your PATH."
