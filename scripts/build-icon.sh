#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
iconset="dist/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
if ! iconutil -c icns "$iconset" -o dist/AppIcon.icns; then
  python3 scripts/pack-icon.py "$iconset" dist/AppIcon.icns
fi
