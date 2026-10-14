#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
arch="${1:-universal}"
mode="${SIGNING_MODE:-ad-hoc}"
case "$mode" in
  ad-hoc) ;;
  developer-id) : "${SIGNING_IDENTITY:?Developer ID mode requires SIGNING_IDENTITY}" ;;
  *) echo "Unknown signing mode: $mode" >&2; exit 2 ;;
esac
case "$arch" in
  universal) architectures=(arm64 x86_64) ;;
  arm64|x86_64) architectures=("$arch") ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 2 ;;
esac
binaries=()
for architecture in "${architectures[@]}"; do
  ./scripts/swift.sh build -c release --product TidyFolder --arch "$architecture"
  binary_dir="$(./scripts/swift.sh build -c release --arch "$architecture" --show-bin-path)"
  binaries+=("$binary_dir/TidyFolder")
done
app="dist/TidyFolder.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [ "$arch" = universal ]; then
  lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/TidyFolder"
else
  cp "${binaries[0]}" "$app/Contents/MacOS/TidyFolder"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/en.lproj Resources/ru.lproj "$app/Contents/Resources/"
if [ "$mode" = developer-id ]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
fi
EXPECTED_ARCH="$arch" SIGNING_MODE="$mode" ./scripts/verify-release.sh "$app"
