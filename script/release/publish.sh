#!/usr/bin/env bash
# The whole release, public at the end: build, notarize, package, sign the
# feed, then a GitHub release of this repository (DMG, zip,
# appcast; skil.li.dmg and appcast.xml under stable names for
# skil.li/download and skil.li/appcast.xml) and the Homebrew cask updated.
# Refuses a build number the feed already has.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

"$ROOT_DIR/script/release/build.sh"
version="$(plist_value "$APP" CFBundleShortVersionString)"
build="$(plist_value "$APP" CFBundleVersion)"
tag="v$version-$build"
published="$(curl -fsSL "$FEED_URL" 2>/dev/null | perl -ne 'if (m{<sparkle:version>([0-9]+)</sparkle:version>}) { print "$1\n"; exit }' || true)"
if [[ "$published" =~ ^[0-9]+$ && "$build" -le "$published" ]]; then
  echo "The feed already has build $published; this is $build. Commit, then release again." >&2
  exit 2
fi
"$ROOT_DIR/script/release/package.sh"
"$ROOT_DIR/script/release/appcast.sh"

files="$DIST/files"
dmg="$files/skil.li-$version-$build.dmg"
cp "$dmg" "$files/skil.li.dmg"
# A draft first, its files uploaded (again when GitHub times out, as it did
# for 0.1.3), then published: skil.li/download never points at a release
# without its files.
assets=("$dmg" "$files/skil.li-$version-$build.zip" "$files/skil.li.dmg" "$files/appcast.xml")
gh release view "$tag" --repo "$RELEASES_REPO" >/dev/null 2>&1 || \
  gh release create "$tag" --repo "$RELEASES_REPO" --draft --title "skil.li $version ($build)" \
    --notes "skil.li $version, build $build. Download: https://skil.li/download · Homebrew: brew install --cask nomdelasociete/tap/skilli"
for attempt in 1 2 3; do
  gh release upload "$tag" --repo "$RELEASES_REPO" --clobber "${assets[@]}" && break
  [[ "$attempt" == 3 ]] && { echo "Upload failed 3 times: the draft $tag waits; run publish.sh again." >&2; exit 1; }
  sleep 10
done
gh release edit "$tag" --repo "$RELEASES_REPO" --draft=false --latest >/dev/null

# The cask: this version and its DMG's checksum, through GitHub's API (no
# clone): the file's current blob, then its new contents.
sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
cask="$(sed -e "s/@VERSION@/$version,$build/" -e "s/@SHA256@/$sha/" "$ROOT_DIR/script/release/skilli.rb.in")"
# Another repository: its own token in GitHub Actions (SKILLI_TAP_TOKEN).
tap_gh() { if [[ -n "${SKILLI_TAP_TOKEN:-}" ]]; then GH_TOKEN="$SKILLI_TAP_TOKEN" gh "$@"; else gh "$@"; fi; }
current="$(tap_gh api "repos/$TAP_REPO/contents/Casks/skilli.rb" --jq .sha 2>/dev/null || true)"
tap_gh api --method PUT "repos/$TAP_REPO/contents/Casks/skilli.rb" \
  -f message="skil.li $version ($build)" \
  -f content="$(printf '%s\n' "$cask" | base64)" \
  ${current:+-f sha="$current"} >/dev/null

curl -fsSIL https://skil.li/download -o /dev/null
# GitHub's "latest" link follows a new release after a minute or two
# (0.1.3 and 0.2.1 failed here while published): the feed is read again,
# every 10 s, for 3 minutes at most: each read (20 s) and each wait is cut to
# what is left of them. A read is whole (`grep -q` closing a pipe would make
# curl fail under pipefail), and only a complete one counts (a partial
# transfer can hold the tag).
feed_has_build() {
  local feed read_status=0
  feed="$(curl -fsSL --max-time "$1" "$FEED_URL")" || read_status=$?
  [[ "$read_status" == 0 && "$feed" == *"<sparkle:version>$build</sparkle:version>"* ]]
}
deadline=$((SECONDS + 180))
found=0
# `left` is tested where it is computed: `curl --max-time 0` would mean no limit.
while left=$((deadline - SECONDS)); (( left > 0 )); do
  if feed_has_build "$(( left < 20 ? left : 20 ))"; then found=1; break; fi
  left=$((deadline - SECONDS))
  (( left <= 0 )) || sleep "$(( left < 10 ? left : 10 ))"
done
[[ "$found" == 1 ]] || { echo "The feed still does not say build $build after 3 minutes: check $FEED_URL." >&2; exit 1; }
echo "Published skil.li $version ($build): https://github.com/$RELEASES_REPO/releases/tag/$tag"
