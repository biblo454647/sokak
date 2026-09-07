#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Pin the upstream release and its published SHA-256. Never download during use.
SOKAK_SPARKLE_VERSION=2.9.6
SOKAK_SPARKLE_HASH=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
SOKAK_SPARKLE_ARCHIVE=".build/Sparkle-$SOKAK_SPARKLE_VERSION.tar.xz"
mkdir -p .build
if [ ! -f "$SOKAK_SPARKLE_ARCHIVE" ]; then
    curl --fail --location --retry 2 --proto '=https' --tlsv1.2 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SOKAK_SPARKLE_VERSION/Sparkle-$SOKAK_SPARKLE_VERSION.tar.xz" \
        --output "$SOKAK_SPARKLE_ARCHIVE"
fi
SOKAK_ACTUAL_HASH="$(shasum -a 256 "$SOKAK_SPARKLE_ARCHIVE" | cut -d ' ' -f 1)"
if [ "$SOKAK_ACTUAL_HASH" != "$SOKAK_SPARKLE_HASH" ]; then
    echo 'Sparkle archive verification failed.' >&2
    exit 1
fi
mkdir -p .build/Sparkle
tar -xf "$SOKAK_SPARKLE_ARCHIVE" -C .build/Sparkle
