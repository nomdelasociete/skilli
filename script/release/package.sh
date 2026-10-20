#!/usr/bin/env bash
# Notarized and stapled: the app (its zip is what Sparkle downloads), then a
# DMG with an Applications link on the branded window (what the website and
# Homebrew download).
# Out: dist/release/files/skil.li-<version>-<build>.{zip,dmg}.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ -d "$APP" ]] || { echo "No build: run script/release/build.sh first." >&2; exit 2; }
version="$(plist_value "$APP" CFBundleShortVersionString)"
build="$(plist_value "$APP" CFBundleVersion)"
name="skil.li-$version-$build"
files="$DIST/files"
rm -rf "$files" && mkdir -p "$files"

# The app, notarized and stapled.
/usr/bin/ditto -c -k --keepParent "$APP" "$DIST/notary.zip"
notarize "$DIST/notary.zip"
xcrun stapler staple "$APP"
spctl -a -vv --type execute "$APP"
/usr/bin/ditto -c -k --keepParent --sequesterRsrc --rsrc "$APP" "$files/$name.zip"

# The DMG: the app and a link to Applications on the branded background
# (dmgbuild lays out the window without Finder), signed, notarized, stapled.
venv="$DIST/venv"
[[ -x "$venv/bin/dmgbuild" ]] || { python3 -m venv "$venv" && "$venv/bin/pip" install --quiet "dmgbuild==$DMGBUILD_VERSION"; }
"$venv/bin/dmgbuild" -s "$ROOT_DIR/script/release/dmg_settings.py" \
  -D app="$APP" -D background="$ROOT_DIR/assets/brand/dmg/background.png" \
  "skil.li" "$files/$name.dmg" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" "$files/$name.dmg"
notarize "$files/$name.dmg"
xcrun stapler staple "$files/$name.dmg"
spctl -a -vv --type open --context context:primary-signature "$files/$name.dmg"
echo "Packaged: $files/$name.zip, $files/$name.dmg"
