#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/fetch_sparkle.sh
SOKAK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
SOKAK_ARCHIVE="Sokak-$SOKAK_VERSION-universal.zip"
SOKAK_STAGE=".build/appcast-$SOKAK_VERSION"
test -f "dist/$SOKAK_ARCHIVE"
test -f "docs/releases/$SOKAK_VERSION.html"
# Signing is a maintainer operation. The private key stays in macOS Keychain.
# This command never generates or exports a key, and fails if it is unavailable.
.build/Sparkle/bin/generate_keys --account com.sokakapp.Sokak -p >/dev/null
mkdir -p "$SOKAK_STAGE"
cp "dist/$SOKAK_ARCHIVE" "$SOKAK_STAGE/"
cp "docs/releases/$SOKAK_VERSION.html" "$SOKAK_STAGE/${SOKAK_ARCHIVE%.zip}.html"
if [ -f appcast.xml ]; then cp appcast.xml "$SOKAK_STAGE/appcast.xml"; fi
.build/Sparkle/bin/generate_appcast --account com.sokakapp.Sokak --maximum-deltas 0 \
    --download-url-prefix "https://github.com/biblo454647/sokak/releases/download/v$SOKAK_VERSION/" \
    --link https://github.com/biblo454647/sokak/releases/latest \
    --embed-release-notes "$SOKAK_STAGE"
swift scripts/verify_update.swift "$SOKAK_STAGE/appcast.xml" "dist/$SOKAK_ARCHIVE"
cp "$SOKAK_STAGE/appcast.xml" appcast.xml
shasum -a 256 "dist/$SOKAK_ARCHIVE" | sed 's@dist/@@' > "dist/$SOKAK_ARCHIVE.sha256"
echo 'Signed appcast.xml and archive checksum are ready. Publish the release asset before pushing the appcast.'
