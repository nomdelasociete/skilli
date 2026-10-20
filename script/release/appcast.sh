#!/usr/bin/env bash
# Sparkle's feed for the packaged zip, signed with the EdDSA key; the zip is
# downloaded from this release's GitHub assets. Out: dist/release/files/appcast.xml.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

version="$(plist_value "$APP" CFBundleShortVersionString)"
build="$(plist_value "$APP" CFBundleVersion)"
tag="v$version-$build"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$DIST/files/skil.li-$version-$build.zip" "$work/"
# The private key from its file when the environment gives one, else the keychain.
if [[ -n "${SKILLI_SPARKLE_KEY_FILE:-}" ]]; then
  key=(--ed-key-file "$SKILLI_SPARKLE_KEY_FILE")
else
  key=(--account "$SPARKLE_KEY_ACCOUNT")
fi
"$(sparkle_tool generate_appcast)" "${key[@]}" \
  --download-url-prefix "https://github.com/$RELEASES_REPO/releases/download/$tag/" \
  --link "https://skil.li" "$work"
grep -q 'sparkle:edSignature' "$work/appcast.xml" || { echo "The appcast is not signed." >&2; exit 2; }
# The channel is named after the bundle (Skilli); readers see skil.li. Only
# the enclosures are signed, so the title can change.
sed -i '' 's#<title>Skilli</title>#<title>skil.li</title>#' "$work/appcast.xml"
cp "$work/appcast.xml" "$DIST/files/appcast.xml"
echo "Appcast: $DIST/files/appcast.xml ($tag)"
