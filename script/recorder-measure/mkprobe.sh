#!/bin/bash
# The app probe (Sources/Skilli/Support/RecorderProbe.swift, Debug builds
# only) as work/probe/{A,B}/SkilliRecorderProbe.app: the Debug build under
# another process name (`pkill -x Skilli` elsewhere leaves a long run alone),
# signed again with the same identity, so macOS treats it as skil.li (its
# permissions apply). B adds NSAudioCaptureUsageDescription. Build first:
# ./script/build_and_run.sh build. SKILLI_SIGN_IDENTITY: the identity to
# sign with (default "Apple Development").
set -euo pipefail
K=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$K/../.." && pwd)
for v in A B; do
  P=$K/work/probe/$v/SkilliRecorderProbe.app
  rm -rf "$K/work/probe/$v"; mkdir -p "$K/work/probe/$v"
  cp -R "$ROOT/DerivedData/Build/Products/Debug/Skilli.app" "$P"
  mv "$P/Contents/MacOS/Skilli" "$P/Contents/MacOS/SkilliRecorderProbe"
  plutil -replace CFBundleExecutable -string SkilliRecorderProbe "$P/Contents/Info.plist"
  [ $v = B ] && plutil -insert NSAudioCaptureUsageDescription -string "skil.li records the call's sound (the other side) when you record a meeting; it stays on this Mac." "$P/Contents/Info.plist"
  codesign --force --sign "${SKILLI_SIGN_IDENTITY:-Apple Development}" --preserve-metadata=entitlements,requirements,flags,runtime "$P" 2>/dev/null
  codesign --verify --deep --strict "$P"
done
echo "work/probe ready"
