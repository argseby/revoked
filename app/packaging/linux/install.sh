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

# Wayland ignores icons a window sets for itself; the compositor matches
# the window's app_id to a .desktop file *by filename*. app_id here is the
# GApplication id, so the entry has to be named for it or the taskbar
# falls back to a generic icon however well the icon is installed.
DESKTOP_ID="com.revoked.revoked_app"
sed "s|^Exec=revoked|Exec=$PREFIX/bin/revoked|" \
    "$SCRIPT_DIR/revoked.desktop" > "$PREFIX/share/applications/$DESKTOP_ID.desktop"
# An older install used the short name; leave no duplicate behind.
rm -f "$PREFIX/share/applications/revoked.desktop"

# Icon themes are indexed per size; without these the launcher shows a
# generic placeholder even though the .desktop names an icon.
for SIZE in 16 32 48 64 128 256 512; do
    ICON_DIR="$PREFIX/share/icons/hicolor/${SIZE}x${SIZE}/apps"
    if [ -f "$SCRIPT_DIR/icons/revoked-$SIZE.png" ]; then
        mkdir -p "$ICON_DIR"
        cp "$SCRIPT_DIR/icons/revoked-$SIZE.png" "$ICON_DIR/revoked.png"
    fi
done
gtk-update-icon-cache -f -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true

update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
xdg-mime default "$DESKTOP_ID.desktop" x-scheme-handler/revoked 2>/dev/null || true

echo "Installed to $APPDIR"
echo "Binary:  $PREFIX/bin/revoked"
echo "Test:    xdg-open 'revoked://s/test'"
[ -n "${PATH##*$PREFIX/bin*}" ] && echo "Note: $PREFIX/bin is not on your PATH."
