# Contributing to Sokak

Issues and pull requests are welcome. Keep Sokak small, offline, and easy to pause. Avoid adding services, accounts, screen capture, or permissions without a clear product need and discussion.

For bug reports, include the Sokak version, macOS version, processor architecture, and steps to reproduce. Crop screenshots to the app and remove personal details. Never attach credentials, private photographs, or desktop captures containing confidential information.

Build with `bash scripts/build.sh` and follow the checks in [Validation](docs/VALIDATION.md). Test changed interactions in the native app. Note device coverage honestly; cross-compilation alone does not verify behavior on another Mac.

New photographs need a clear redistribution license, original source and author, original dimensions, and a SHA-256 entry in `Resources/scenes.json`. Preserve the applicable license in `Resources/PHOTO-CREDITS.md`. Do not add images from personal imports or unverified image-search results.

By contributing original code or audio, you agree to distribute that contribution under the project's MIT license. Separately licensed assets must keep their license and attribution.
