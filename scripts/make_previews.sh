#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOKAK_QA="${1:-docs/qa}"
command -v ffmpeg >/dev/null
test -f "$SOKAK_QA/rain-window.mp4"
test -f "$SOKAK_QA/rain-preview.wav"
test -f "$SOKAK_QA/snow-window.mp4"
mkdir -p dist/previews
ffmpeg -hide_banner -loglevel error -y -i "$SOKAK_QA/rain-window.mp4" -i "$SOKAK_QA/rain-preview.wav" \
    -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 160k -shortest dist/previews/rain-window.mp4
cp "$SOKAK_QA/snow-window.mp4" dist/previews/snow-window.mp4
ffmpeg -hide_banner -loglevel error -y -i "$SOKAK_QA/wiper-window.mp4" -i "$SOKAK_QA/wiper-preview.wav" \
    -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 160k -shortest dist/previews/wiper-window.mp4
ffmpeg -hide_banner -loglevel error -y -i dist/previews/rain-window.mp4 \
    -filter_complex '[0:v]fps=12,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full:max_colors=256[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle' \
    -loop 0 docs/rain-window.gif
ffmpeg -hide_banner -loglevel error -y -i dist/previews/wiper-window.mp4 \
    -filter_complex '[0:v]fps=15,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full:max_colors=256[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle' \
    -loop 0 docs/wiper-window.gif
echo 'Prepared rain and wiper GIFs, synchronized sound previews, and the unchanged-style snow MP4.'
