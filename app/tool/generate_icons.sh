#!/usr/bin/env sh
# Renders every platform icon from the two logo SVGs in assets/icon/.
#
#   ./tool/generate_icons.sh
#
# Needs rsvg-convert and ImageMagick. The outputs are committed, because the
# platform build systems read them directly and CI does not run this.
set -eu

APP=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$APP"

LIGHT=assets/icon/revoced-mark-redacted-black-on-white.svg
DARK=assets/icon/revoced-mark-redacted-white-on-black.svg
OUT=build/icon
mkdir -p "$OUT"

# The mark alone, for surfaces that bring their own background: Android's
# adaptive and themed icons, and the iOS dark icon. The dark logo is used as a
# luminance mask, so whatever it paints black comes out transparent.
{
    echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500"><mask id="m">'
    sed 's/width="2000" height="2000"/width="500" height="500"/' "$DARK"
    echo '</mask><rect width="500" height="500" fill="#ffffff" mask="url(#m)"/></svg>'
} > "$OUT/mark.svg"

rsvg-convert -w 1024 -h 1024 "$DARK" -o "$OUT/app_icon.png"
rsvg-convert -w 1024 -h 1024 "$LIGHT" -o "$OUT/app_icon_light.png"
rsvg-convert -w 1024 -h 1024 "$OUT/mark.svg" -o "$OUT/app_icon_mark.png"

# Desktops draw an icon as-is rather than masking it, so they get the plate
# on Apple's icon grid: an 824px rounded square centred on a 1024px canvas.
magick "$OUT/app_icon.png" -resize 824x824 \
    \( -size 824x824 xc:none -fill white -draw "roundrectangle 0,0,823,823,185,185" \) \
    -alpha set -compose DstIn -composite -compose over \
    -background none -gravity center -extent 1024x1024 \
    "PNG32:$OUT/app_icon_desktop.png"

for SIZE in 16 32 48 64 128 256 512; do
    magick "$OUT/app_icon_desktop.png" -resize "${SIZE}x${SIZE}" \
        "PNG32:packaging/linux/icons/revoked-$SIZE.png"
done

dart run flutter_launcher_icons
