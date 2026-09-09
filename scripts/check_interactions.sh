#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOKAK_CHECK=".build/interaction-check/Sokak.app"
test -f dist/Sokak.app/Contents/MacOS/Sokak
mkdir -p .build/interaction-check
ditto dist/Sokak.app "$SOKAK_CHECK"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.sokakapp.Sokak.InteractionCheck' "$SOKAK_CHECK/Contents/Info.plist"
swiftc -O -swift-version 5 -D SOKAK_INTERACTION_TEST -F .build/Sparkle -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/*.swift Tests/InteractionChecks.swift Tests/NavigationChecks.swift \
    -o "$SOKAK_CHECK/Contents/MacOS/Sokak"
codesign --force --sign - --options runtime --entitlements Resources/AdHoc.entitlements --timestamp=none "$SOKAK_CHECK"
"$SOKAK_CHECK/Contents/MacOS/Sokak" --interaction-check --show "${1:-docs/qa/interactions}"
