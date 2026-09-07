# Release validation

Sokak builds for macOS 13 or later on Apple Silicon and Intel. Runtime checks have covered Apple Silicon. Cross-compilation is not a substitute for testing physical Intel hardware or every supported macOS release.

## Reproduce the checks

Run these commands from a local checkout on a Mac with Apple Command Line Tools and a recent Swift compiler:

```sh
bash scripts/build.sh
swiftc -swift-version 5 Sources/Core.swift Tests/CoreTests.swift -o .build/core-tests
.build/core-tests
swiftc -O -swift-version 5 Sources/Core.swift Sources/GlassSimulation.swift Tests/GlassTests.swift -o .build/glass-tests
.build/glass-tests
python3 scripts/verify_assets.py
dist/Sokak.app/Contents/MacOS/Sokak --self-test docs/qa --motion-preview
codesign --verify --strict --verbose=2 dist/Sokak.app
lipo -archs dist/Sokak.app/Contents/MacOS/Sokak
```

The self-test requires a macOS graphics session and Metal. Generated frames and the report are saved under the ignored `docs/qa/` directory. It uses bundled photographs only, excludes personal imports, and never captures the desktop. The report does not include the machine name, user name, or GPU model.

## What is checked

- Universal release compilation targets `arm64-apple-macosx13.0` and `x86_64-apple-macosx13.0`; `lipo` checks the packaged architectures.
- The ad-hoc hardened-runtime signature is verified for bundle integrity. This does not establish Developer ID identity or Apple notarization.
- All eleven original photograph hashes and dimensions match the manifest. Six are winter photographs. Each has author, source, and license links.
- All three 46-second stereo ambience files decode and prepare for playback.
- Core tests cover timer expiry and cancellation, rounding, no-timer sessions, corrupted preferences, nonfinite and out-of-range settings, persistence, display and timer validation, and seasonal photograph matching.
- Migration checks preserve existing 1.1 preferences while enabling window glass by default, and preserve an explicitly disabled glass setting.
- Surface-water tests cover volume conservation when beads merge, gravity and runoff, wet trails, irregular impacts, equivalent 30/60 fps stepping, bounded memory, suspended-frame recovery and weather changes.
- Integration checks exercise published-settings recovery and ensure the test library contains only the eleven bundled scenes.
- The actual Metal pipelines render rain, snow, and mist into opaque photograph frames and transparent desktop frames. Alpha-channel checks distinguish the two modes.
- Glass-on versus glass-off renders verify visible pane contact, while frames a second apart verify temporal change. The motion-preview option exports 300 consecutive frames each for rain and snow through the same renderer and simulation used by the app.
- A red reference photograph passes through the image pipeline to check color-channel preservation after explicit RGBA normalization.
- Native SwiftUI menu and library snapshots are rendered for visual inspection.

Photograph upload and test readback textures use Metal's hardware-appropriate default storage mode. Managed textures are synchronized before CPU readback in the test renderer. The reusable exterior render target uses GPU-private storage with render-target and shader-read usage. The pane samples that app-owned target in a second render pass. See [Apple's storage-mode documentation](https://developer.apple.com/documentation/metal/setting-resource-storage-modes).

## Native interaction coverage

The app has been exercised through its native interface for weather selection, desktop and photograph modes, seasonal snow matching, winter filtering, photograph selection, sound on/off, low-power mode, timer selection, starting and pausing, and Escape from an immersive session.

The 1.2 window-glass toggle was checked in both positions, including its enabled default with existing preferences. Rain and snow immersive sessions were started in the native app, the rain pane was visually inspected, and Escape returned the app to its paused menu. Rain and snow were also inspected using app-owned frame exports and consecutive-frame previews. This is visual QA, not a claim that the effect reproduces every physical property of water or snow.

Start/pause and sound shortcuts have been checked with app-targeted key events. Carbon global registration succeeds without requesting Accessibility access. Physical keyboard dispatch while another app is active still needs device testing. The menu controls remain available if a shortcut conflicts.

## Remaining checks and limitations

- Physical Intel hardware, older supported macOS releases, multiple physical monitors, display hot-plug, mixed scaling, sleep/lock/wake transitions, and protected third-party full-screen applications need further validation.
- Desktop mode is configured to pass mouse clicks through; immersive photographs catch clicks and support Escape. Some protected system surfaces may appear above the overlay.
- Battery consumption, graphics performance, and audio output vary by device. No universal performance or battery claim is made.
- The current download is ad-hoc signed and unnotarized. Gatekeeper may block it, and managed Macs may require approval. See [Apple's installation guidance](https://support.apple.com/en-gb/102445).
- Weather is rendered over still photographs; it does not reconstruct a street in 3D, accumulate snow on app windows, or refract captured desktop content. Audio is synthesized ambience, not a location recording.
