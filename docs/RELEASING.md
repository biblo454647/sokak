# Releasing Sokak updates

Sokak 1.3 and later use [Sparkle](https://sparkle-project.org/documentation/) with a signed appcast and Ed25519-signed ZIP archives. Both signatures are required; archives are verified before extraction. The feed is `https://raw.githubusercontent.com/biblo454647/sokak/main/appcast.xml`. Downloads point only to this repository's GitHub Releases. Users choose when to install.

## Maintainer key

The private update key is stored in macOS Keychain under the Sparkle account `com.sokakapp.Sokak`. Only the public key is in `Resources/Info.plist`. The official `generate_appcast` tool accesses the private key for signing; macOS may request permission. Never commit or publish a private key, Keychain export, credential, or signing log containing a secret. Do not change this public key casually: strict verification is enabled, and losing the private key would require a manual reinstall for the current ad-hoc distribution.

Forks must change the bundle identifier, GitHub feed URL and public key, and use a separate signing account. Normal contributors can build and run the app without the release private key; they cannot publish trusted upstream updates.

## Release sequence

1. Increment both `CFBundleVersion` (a strictly increasing build number) and `CFBundleShortVersionString` in `Resources/Info.plist`. Add concise user-facing notes in `docs/releases/VERSION.html`.
2. Build with `bash scripts/build.sh` and complete [validation](VALIDATION.md). The first build downloads the pinned Sparkle archive from its official release and checks its SHA-256. The shipped app is self-contained.
3. Run `bash scripts/make_appcast.sh`. It stages only this version's archive, preserves previous feed entries, embeds release notes, and signs the result with Sparkle. A separate public-key-only verifier checks both the feed and ZIP. Do not edit the signed XML afterward; regenerate it if anything changes.
4. Review the source, photo licenses, distribution contents and diff. Commit the reviewed changes and tag the release. Upload the exact ZIP, its `.sha256`, and optional credited renderer previews to the matching GitHub Release.
5. Verify the released assets by anonymously downloading them and checking their hashes and Ed25519 signatures. Publish the generated `appcast.xml` on `main` only after its release URL works. Never point the feed at a draft or missing asset.
6. Check for updates in the shipped app. A development copy with an older build number can exercise the full download/install/relaunch cycle without touching an installed copy. Confirm settings survive and modified feeds and archives are rejected.

For a local public-key check from the repository root:

```sh
swift scripts/verify_update.swift appcast.xml dist/Sokak-VERSION-universal.zip
```

Apple Developer ID signing/notarization and Sparkle update signatures are separate. Current community builds are ad-hoc signed and unnotarized. The ad-hoc app has a per-app library-validation exception so it can load the bundled, upstream-signed Sparkle framework without a matching Team ID. A Developer ID release should sign the nested components correctly and remove that exception, then notarize and staple before producing and signing the final ZIP. See [Sparkle's distribution guidance](https://sparkle-project.org/documentation/).

The updater does not disable Gatekeeper, remove corporate restrictions, add a login service, or upload personal photographs. Optional automatic checks are off by default; system profiling and automatic installation are disabled.
