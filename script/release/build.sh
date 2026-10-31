#!/usr/bin/env bash
# The Developer ID build: archived from a clean checkout (its build number is
# the commit count), signed with the team's Developer ID, the update feed
# and Sparkle's public key in it; its version SKILLI_MARKETING_VERSION
# (publish.sh, from script/release/version.sh), else project.yml's.
# Out: dist/release/export.noindex/Skilli.app.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain --untracked-files=no)" && "${SKILLI_ALLOW_DIRTY:-0}" != "1" ]]; then
  echo "Uncommitted changes: a release is built from a clean checkout." >&2
  exit 2
fi
# Sparkle's tools (generate_keys, generate_appcast) come with its package.
xcodegen generate >/dev/null
xcodebuild -resolvePackageDependencies -project Skilli.xcodeproj -scheme Skilli -derivedDataPath "$DIST/DerivedData" >/dev/null
public_key="${SKILLI_SPARKLE_PUBLIC_ED_KEY:-$("$ROOT_DIR/script/release/keys.sh" -p 2>/dev/null || true)}"
if [[ -z "$public_key" ]]; then
  echo "No Sparkle key: SKILLI_SPARKLE_PUBLIC_ED_KEY, or run script/release/keys.sh once." >&2
  exit 2
fi

# Klipy's key stays out of the repository and the keychain: from the environment
# (GitHub Actions), else from this Mac's own skil.li (`daily`), which has it.
# Without one, Search GIFs finds only the GIFs on the Mac until a user adds theirs.
klipy_key="${SKILLI_KLIPY_KEY:-}"
if [[ -z "$klipy_key" && -f "$KLIPY_KEY_APP/Contents/Info.plist" ]]; then
  # PlistBuddy prints its errors on stdout: kept only when it succeeds.
  klipy_key="$(/usr/libexec/PlistBuddy -c 'Print :SkilliKlipyKey' "$KLIPY_KEY_APP/Contents/Info.plist" 2>/dev/null)" || klipy_key=""
fi
if [[ -z "$klipy_key" ]]; then
  echo "No Klipy key (SKILLI_KLIPY_KEY, or this Mac's daily skil.li): this build searches only GIFs on the Mac." >&2
fi

version=()
if [[ -n "${SKILLI_MARKETING_VERSION:-}" ]]; then
  [[ "$SKILLI_MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "SKILLI_MARKETING_VERSION is not x.y.z." >&2; exit 2; }
  version=(MARKETING_VERSION="$SKILLI_MARKETING_VERSION")
fi

rm -rf "$DIST/Skilli.xcarchive" "$DIST/export" "$DIST/export.noindex"
mkdir -p "$DIST"
xcodebuild \
  -project Skilli.xcodeproj -scheme Skilli -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$DIST/Skilli.xcarchive" \
  -derivedDataPath "$DIST/DerivedData" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Developer ID Application" \
  SKILLI_UPDATE_FEED_URL="$FEED_URL" SKILLI_SPARKLE_PUBLIC_ED_KEY="$public_key" SKILLI_KLIPY_KEY="$klipy_key" \
  ${version[@]+"${version[@]}"} \
  archive | tail -n 3
xcodebuild -exportArchive -archivePath "$DIST/Skilli.xcarchive" -exportPath "$DIST/export.noindex" \
  -exportOptionsPlist "$ROOT_DIR/Config/ExportOptions.plist" | tail -n 2

codesign --verify --deep --strict --verbose=1 "$APP"
# The self-tests and their test data never ship (SelfTest.swift needs SKILLI_SELFTEST).
if strings "$APP/Contents/MacOS/Skilli" | grep -q 'SELFTEST'; then
  echo "This build contains the self-tests: not a release." >&2; exit 2
fi
[[ "$(plist_value "$APP" SUFeedURL)" == "$FEED_URL" ]] || { echo "SUFeedURL missing in the build" >&2; exit 2; }
if [[ -n "${SKILLI_MARKETING_VERSION:-}" && "$(plist_value "$APP" CFBundleShortVersionString)" != "$SKILLI_MARKETING_VERSION" ]]; then
  echo "The build says $(plist_value "$APP" CFBundleShortVersionString), not $SKILLI_MARKETING_VERSION." >&2; exit 2
fi
echo "Built skil.li $(plist_value "$APP" CFBundleShortVersionString) ($(plist_value "$APP" CFBundleVersion)): $APP"
