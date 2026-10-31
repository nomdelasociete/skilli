#!/bin/sh
# Run by Xcode after each build of skil.li (project.yml, postBuildScripts),
# before signing: the build number is the commit count, and the commit and
# the time of the build go beside it, so Settings → About and Copy
# Diagnostics say which build runs. A "+" after the commit: changes not
# committed yet were built.
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
[ -f "$plist" ] || exit 0
cd "$SRCROOT" || exit 0
# The public repository started over on 2026-10-18 (its private history
# reached build 660), and again on 2026-10-20 (the first one reached build
# 815): its builds count on from 900, so they keep rising.
count=$(( $(git rev-list --count HEAD 2>/dev/null || echo 1) + 900 ))
commit=$(git rev-parse --short HEAD 2>/dev/null) || commit=unknown
git diff --quiet HEAD 2>/dev/null || commit="$commit+"
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $count" "$plist"
# The version: the newest release tag's, or MARKETING_VERSION when higher
# (a release passes its own): project.yml's is only a floor
# (script/release/version.sh).
version=$(/bin/bash "$SRCROOT/script/release/version.sh" current 2>/dev/null) \
    && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
for pair in "SkilliCommit:$commit" "SkilliBuildDate:$built"; do
    key=${pair%%:*}
    value=${pair#*:}
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
done
