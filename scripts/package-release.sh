#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: package-release.sh VERSION}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 2; }
EXPECTED_VERSION="$version" ./scripts/verify-release.sh dist/TidyFolder.app
name="TidyFolder-${version}-macOS"
ditto -c -k --sequesterRsrc --keepParent dist/TidyFolder.app "dist/$name.zip"
stage="$(mktemp -d "$PWD/dist/dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto dist/TidyFolder.app "$stage/TidyFolder.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname TidyFolder -srcfolder "$stage" -ov -format UDZO "dist/$name.dmg"
if [ "${SIGNING_MODE:-ad-hoc}" = developer-id ]; then
  : "${SIGNING_IDENTITY:?Requires SIGNING_IDENTITY}"
  : "${NOTARY_PROFILE:?Requires NOTARY_PROFILE}"
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "dist/$name.dmg"
  xcrun notarytool submit "dist/$name.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple dist/TidyFolder.app
  xcrun stapler staple "dist/$name.dmg"
  ditto -c -k --sequesterRsrc --keepParent dist/TidyFolder.app "dist/$name.zip"
fi
(cd dist && shasum -a 256 "$name.zip" "$name.dmg" > SHA256SUMS)
echo "Packaged $name (${SIGNING_MODE:-ad-hoc})"
