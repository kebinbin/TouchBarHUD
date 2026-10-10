# Releasing TouchBar HUD

Public source is licensed under MIT. An explicitly labeled beta can be shared without Apple signing credentials, with the Gatekeeper limitation stated in the README. A normal trusted download requires Developer ID signing, notarization, and hardware verification.

## Free beta

Run the checks, build the default ad hoc signed app, then package it:

```sh
./build.sh
./scripts/test.sh
./scripts/analyze.sh
./scripts/package-beta.sh
```

The last command creates `build/releases/TouchBarHUD-0.5.2-beta-adhoc.zip` and its SHA-256 file. Upload both as beta assets, alongside the source. The archive includes the app, license, README, changelog, and verification notes. Mark the release as a beta and state that the only hardware verified so far is MacBookPro15,1 on macOS 15.7.9. Other models, macOS 13/14, and all physical alignment profiles need tester feedback. The README explains Apple's **Open Anyway** flow. Never ask people to turn off Gatekeeper globally.

## Before packaging

- For a trusted download, complete the manual compatibility matrix in [VERIFICATION.md](VERIFICATION.md), including a real Touch Bar and the Developer ID-signed build. Record the exact tested OS and hardware versions in release notes.
- Run `./scripts/test.sh` and `./scripts/analyze.sh`.
- Update both version fields in `Info.plist` and the changelog. Keep the bundle identifier stable so login registration and permissions survive normal updates.
- Confirm the app, license, README, and release notes are included. Avoid shipping tests, local profiling output, or signing credentials.

## Sign and notarize

Use a Developer ID Application certificate in the maintainer's Keychain:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./build.sh
```

This enables the hardened runtime and a secure timestamp. The app currently declares no runtime exceptions. Test its private framework and mouse-forwarding paths with that signed build before release. Do not disable library validation or add broad entitlements without evidence that they are needed.

Store notarization credentials using Apple's `notarytool store-credentials`, then run:

```sh
./scripts/package-release.sh YOUR_NOTARY_KEYCHAIN_PROFILE
```

The script submits to Apple, waits for acceptance, staples the ticket, verifies Gatekeeper assessment, and produces a versioned ZIP with a SHA-256 checksum under `build/releases/`. It does not upload to a public release service. Full Xcode may be needed for `notarytool` and `stapler`.

Apple's instructions: [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Signing with Developer ID](https://developer.apple.com/developer-id/).

## Installation and updates

Test installation from a downloaded, quarantined ZIP on a separate account or Mac. Confirm normal Gatekeeper launch, opt-in login startup, Accessibility authorization, and replacement of a previous version. Update by quitting the running app first, replacing the app at its existing location, and relaunching. The app has no auto-updater.

Do not tell users to disable Gatekeeper. For unsupported OS releases, publish a compatibility limitation instead of promising private API stability. Maintain source releases even if signing credentials are unavailable, and label local ad-hoc binaries clearly as development builds.
