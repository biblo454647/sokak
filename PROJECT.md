# Sokak

- Purpose: Offline native macOS menu bar relaxation app with weather overlays, ambient sound, and an Istanbul photograph library.
- Lifecycle: active
- Maintainers: Sokak contributors
- GitHub: https://github.com/biblo454647/sokak
- Distribution: Public GitHub Releases, universal Mac app ZIP.
- License: MIT for source, icon, and original synthesized audio. Photographs retain their separate Creative Commons licenses.
- Local checkout: any directory chosen by the contributor; commands run from the repository root.
- Minimum target: macOS 13; universal arm64 and x86_64; Metal required.
- Application identifier: `com.sokakapp.Sokak`.
- Signing: current releases are ad-hoc signed and unnotarized.
- Run: open `dist/Sokak.app`; click the menu-bar cloud.
- Build: `bash scripts/build.sh` using Apple Command Line Tools and a recent Swift compiler.
- Test: compile and run `Tests/CoreTests.swift`, run the app with `--self-test docs/qa`, then `python3 scripts/verify_assets.py`. See [Validation](docs/VALIDATION.md) for exact commands and device coverage.
- Release: build and validate the reviewed source, tag it, and upload the matching ZIP and SHA-256 to GitHub Releases. Download the uploaded asset and verify its checksum. Identify signing and device-testing limitations in the release notes.
- Hosted services / Cloudflare resources: none.
- Scheduled tasks / LaunchAgents / login items: none.
- User data: standard preferences and `~/Library/Application Support/Sokak/Imports`, local to each user. Personal imports are excluded from build and test artifacts.
- Retire: quit and remove the app. Personal imports and preferences can be kept or removed separately. There are no cloud services to decommission.
