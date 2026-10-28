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
# A critical release (SKILLI_CRITICAL_UPDATE=true, the workflow's `critical`
# input): Sparkle shows it at once, even with automatic updates on, and it
# cannot be skipped. The feed holds one release only, so a later release
# stays critical for anyone below the last critical build, read from the
# live feed (a release that cannot read it stops: it would drop that).
critical=()
if [[ "${SKILLI_CRITICAL_UPDATE:-}" == true ]]; then
  critical=(--critical-update-version "")
else
  live="$(curl -fsSL "$FEED_URL")" || live=""
  # A feed only when it holds a release: an empty or other page would look
  # like one without a critical release.
  [[ "$live" == *"<rss"* && "$live" =~ \<sparkle:version\>[0-9]+\</sparkle:version\> ]] \
    || { echo "Cannot read $FEED_URL as a feed to keep its critical release." >&2; exit 2; }
  below="$(printf '%s' "$live" | perl -0ne '
    if (m{<sparkle:criticalUpdate\s+sparkle:version="([0-9]+)"}) { print $1 }
    elsif (m{<sparkle:criticalUpdate\b} && m{<sparkle:version>([0-9]+)</sparkle:version>}) { print $1 }')"
  if [[ -n "$below" ]]; then critical=(--critical-update-version "$below"); fi
fi
"$(sparkle_tool generate_appcast)" "${key[@]}" ${critical[@]+"${critical[@]}"} \
  --download-url-prefix "https://github.com/$RELEASES_REPO/releases/download/$tag/" \
  --link "https://skil.li" "$work"
grep -q 'sparkle:edSignature' "$work/appcast.xml" || { echo "The appcast is not signed." >&2; exit 2; }
# The channel is named after the bundle (Skilli); readers see skil.li. Only
# the enclosures are signed, so the title can change.
sed -i '' 's#<title>Skilli</title>#<title>skil.li</title>#' "$work/appcast.xml"
cp "$work/appcast.xml" "$DIST/files/appcast.xml"
echo "Appcast: $DIST/files/appcast.xml ($tag${critical[1]+, critical${critical[1]:+ below ${critical[1]}}})"
