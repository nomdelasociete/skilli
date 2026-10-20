# Shared by the release scripts: where things go and what they are called.
# Sourced, never run.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="$ROOT_DIR/dist/release"
# In a .noindex folder: Spotlight would list every exported copy as an app.
APP="$DIST/export.noindex/Skilli.app"
TEAM_ID="JSFMAD28GS"
SIGN_IDENTITY="Developer ID Application: NOM DE LA SOCIETE ($TEAM_ID)"
# Every credential comes from the environment first (GitHub Actions'
# `release` environment, .github/workflows/release.yml), else from this Mac's
# login keychain as before.
# Notarization: an App Store Connect API key (SKILLI_NOTARY_KEY_FILE, its
# _ID and the team's SKILLI_NOTARY_ISSUER), else the team's notarytool
# profile (xcrun notarytool store-credentials): the same Apple team as dsmn.
NOTARY_PROFILE="${SKILLI_NOTARY_PROFILE:-dsmn-notary}"
# Sparkle's EdDSA key: SKILLI_SPARKLE_KEY_FILE (its private key) and
# SKILLI_SPARKLE_PUBLIC_ED_KEY, else the login keychain under this account.
SPARKLE_KEY_ACCOUNT="${SKILLI_SPARKLE_KEY_ACCOUNT:-nomdelasociete-skilli}"
FEED_URL="${SKILLI_UPDATE_FEED_URL:-https://skil.li/appcast.xml}"
# skil.li's Klipy key (Search GIFs): SKILLI_KLIPY_KEY, else the one inside this
# Mac's own skil.li (`./script/build_and_run.sh daily` carries it over).
# The Homebrew tap is written with SKILLI_TAP_TOKEN when set (a token for that
# repository only), else with gh's own sign-in.
KLIPY_KEY_APP="${SKILLI_KLIPY_KEY_APP:-$ROOT_DIR/DerivedData/Build/Products/Release/Skilli.app}"
# Public files: this repository's GitHub releases; skil.li/download and
# skil.li/appcast.xml redirect to the latest one's.
RELEASES_REPO="${SKILLI_RELEASES_REPO:-nomdelasociete/skilli}"
TAP_REPO="${SKILLI_TAP_REPO:-nomdelasociete/homebrew-tap}"
# Lays out the DMG window; installed in dist/release/venv by package.sh.
DMGBUILD_VERSION="1.6.7"

sparkle_tool() {
  local name="$1" match
  for root in "$ROOT_DIR/DerivedData" "$DIST/DerivedData" "$HOME/Library/Developer/Xcode/DerivedData"; do
    [[ -d "$root" ]] || continue
    match="$(find "$root" -type f -path "*artifacts/sparkle/Sparkle/bin/$name" -perm -111 2>/dev/null | head -n 1)"
    if [[ -n "$match" ]]; then printf '%s\n' "$match"; return 0; fi
  done
  echo "Sparkle's $name not found: build the app once (xcodebuild resolves the package)." >&2
  return 1
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }

# Submits a file to Apple's notary service and waits for its verdict: with
# the API key when the environment has one, else the keychain profile.
notarize() {
  if [[ -n "${SKILLI_NOTARY_KEY_FILE:-}" ]]; then
    xcrun notarytool submit "$1" --key "$SKILLI_NOTARY_KEY_FILE" --key-id "$SKILLI_NOTARY_KEY_ID" \
      --issuer "$SKILLI_NOTARY_ISSUER" --wait
  else
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  fi
}
