#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build dist
APP="$PWD/dist/Sokak.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SOKAK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
for ARCH in arm64 x86_64; do
    swiftc -O -whole-module-optimization -module-name Sokak -swift-version 5 -sdk "$SDK" -target "$ARCH-apple-macosx13.0" Sources/*.swift -o ".build/Sokak-$ARCH"
done
lipo -create .build/Sokak-arm64 .build/Sokak-x86_64 -output "$APP/Contents/MacOS/Sokak"
cp -R Resources/. "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make_icon.swift "$APP/Contents/Resources"
codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "dist/Sokak-$SOKAK_VERSION-universal.zip"
echo "Built dist/Sokak.app and dist/Sokak-$SOKAK_VERSION-universal.zip"
