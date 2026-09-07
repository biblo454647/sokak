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
codesign --verify --deep --strict --verbose=2 dist/Sokak.app
lipo -archs dist/Sokak.app/Contents/MacOS/Sokak
```

The self-test requires a macOS graphics session and Metal. Generated frames and the report are saved under the ignored `docs/qa/` directory. It uses bundled photographs only, excludes personal imports, and never captures the desktop. The report does not include the machine name, user name, or GPU model.

## What is checked

- Universal release compilation targets `arm64-apple-macosx13.0` and `x86_64-apple-macosx13.0`; `lipo` checks the packaged architectures.
- The ad-hoc hardened-runtime signature is verified for bundle integrity. This does not establish Developer ID identity or Apple notarization.
- All fifteen original photograph hashes and dimensions match the manifest. Six are winter photographs; five are explicitly suitable for rain. Each has author, source, and license links.
- All three 46-second stereo ambience files decode and prepare for playback.
- Core tests cover timer expiry and cancellation, rounding, no-timer sessions, corrupted preferences, nonfinite and out-of-range settings, persistence, display and timer validation, and weather-aware matching. Sunny rain selections migrate to Galata; suitable explicit choices remain selected.
- Migration checks preserve existing preferences, supply defaults for the glass and focus controls, and preserve an explicitly disabled glass setting.
- Surface-water tests cover volume conservation, small merged beads remaining pinned, slow heavy-drop runoff, wet trails, irregular impacts, equivalent 30/60 fps stepping, distinct session patterns, bounded memory, suspended-frame recovery and weather changes. More than 90% of beads remain pinned in the tested calm scene; runoff is capped at 24 logical points per second.
- Live intensity tests raise an existing light-rain session to heavy rain. The same beads and elapsed time survive the change; the count of clearly sized beads more than doubles within ten seconds. Lowering intensity leaves existing water in place instead of resetting the pane.
- Integration checks exercise published-settings recovery and exclude personal imports from the bundled test library.
- The actual Metal pipelines render rain, snow, and mist into opaque photograph frames and transparent desktop frames. Alpha-channel checks distinguish the two modes.
- Glass-on versus glass-off renders verify visible pane contact, while frames a second apart verify temporal change. The motion-preview option exports 300 consecutive frames each for rain and snow through the same renderer and simulation used by the app.
- A red reference photograph passes through the image pipeline to check color-channel preservation after explicit RGBA normalization.
- PNG and JPEG primary-colour/detail charts pass through the rain renderer at default and maximum softness. The 24-point detail pattern retains over 75% of its contrast; red, green and blue channels remain separate. A 2880 × 1800 snow render checks opacity, colour and detail at Retina scale.
- The falling-rain layer is tested independently of glass beads. Maximum intensity must have measurable coverage and more than six times the mean opacity of 10% intensity. This checks width and contrast as well as particle count. App-owned light and heavy rain frames are exported for visual comparison.
- Native SwiftUI menu and library snapshots are rendered for visual inspection.

Photograph upload and test readback textures use Metal's hardware-appropriate default storage mode. Managed textures are synchronized before CPU readback in the test renderer. The reusable exterior render target uses GPU-private storage with render-target and shader-read usage. The pane samples that app-owned target in a second render pass. See [Apple's storage-mode documentation](https://developer.apple.com/documentation/metal/setting-resource-storage-modes).

## Native interaction coverage

The app has been exercised through its native interface for weather selection, desktop and photograph modes, seasonal snow matching, winter filtering, photograph selection, sound on/off, low-power mode, timer selection, starting and pausing, and Escape from an immersive session.

Window glass, rain and snow immersive sessions, and Escape back to a paused menu have been exercised. Version 1.3.1 corrects excessive background blur and faint rain, with app-owned frame and consecutive-frame inspection for recognizable streets, visible rainfall and calm glass motion. This is visual QA, not a claim that the effect reproduces every physical property of water or snow.

## Updater validation

An isolated development app with a separate bundle identifier and an older build number was updated through the native Sparkle interface, using a loopback fixture server. A modified signed feed was rejected; a one-byte-modified ZIP was rejected before extraction. The valid ZIP reached Install and Relaunch, replaced build 4 with build 5, and relaunched automatically. A changed volume preference survived. Checking again reported that 1.3.0 was current. The loopback feed and its HTTP testing exception are confined to ignored QA copies; the shipped feed uses HTTPS.

The release script verifies feed and archive signatures using CryptoKit and only the public key. It does not need Keychain access for verification. Update source, key, strict signature requirements, disabled system profiling, and manual installation defaults are recorded in the shipped Info.plist. See [Releasing updates](RELEASING.md).

Start/pause and sound shortcuts have been checked with app-targeted key events. Carbon global registration succeeds without requesting Accessibility access. Physical keyboard dispatch while another app is active still needs device testing. The menu controls remain available if a shortcut conflicts.

## Remaining checks and limitations

- Physical Intel hardware, older supported macOS releases, multiple physical monitors, display hot-plug, mixed scaling, sleep/lock/wake transitions, and protected third-party full-screen applications need further validation.
- Desktop mode is configured to pass mouse clicks through; immersive photographs catch clicks and support Escape. Some protected system surfaces may appear above the overlay.
- Battery consumption, graphics performance, and audio output vary by device. No universal performance or battery claim is made.
- The current download is ad-hoc signed and unnotarized. Gatekeeper may block it, and managed Macs may require approval. See [Apple's installation guidance](https://support.apple.com/en-gb/102445).
- Weather is rendered over still photographs; it does not reconstruct a street in 3D, accumulate snow on app windows, or refract captured desktop content. Audio is synthesized ambience, not a location recording.
