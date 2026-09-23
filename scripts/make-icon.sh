#!/bin/zsh
# Regenerates assets/AppIcon.icns from assets/app-icon.svg. Needs rsvg-convert
# (brew install librsvg). The .icns is committed, so building never needs this.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || { echo "needs rsvg-convert: brew install librsvg"; exit 1; }

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  rsvg-convert -w $size -h $size assets/app-icon.svg -o "$ICONSET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) assets/app-icon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
rsvg-convert -w 512 -h 512 assets/app-icon.svg -o assets/app-icon.png
rm -rf "$(dirname "$ICONSET")"
echo "wrote assets/AppIcon.icns and assets/app-icon.png"
