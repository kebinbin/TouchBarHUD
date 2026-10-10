#!/bin/zsh
set -euo pipefail
if (( $# != 1 )); then
  print -u2 'Usage: ./scripts/package-release.sh NOTARY_KEYCHAIN_PROFILE'
  exit 64
fi
PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/build/TouchBar HUD.app"
PROFILE_NAME="$1"
SIGNATURE="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
if [[ "$SIGNATURE" != *'Authority=Developer ID Application:'* || "$SIGNATURE" != *'runtime'* ]]; then
  print -u2 'Build with a Developer ID Application identity and hardened runtime first.'
  exit 1
fi
codesign --verify --strict "$APP_DIR"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 'Expected a three-part numeric release version.'
  exit 1
fi
RELEASE_DIR="$PROJECT_DIR/build/releases"
mkdir -p "$RELEASE_DIR"
STAGING_DIR="$(mktemp -d "$RELEASE_DIR/.staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto -c -k --keepParent "$APP_DIR" "$STAGING_DIR/notarization.zip"
xcrun notarytool submit "$STAGING_DIR/notarization.zip" --keychain-profile "$PROFILE_NAME" --wait \
  --output-format json > "$STAGING_DIR/notarization-result.json"
python3 - "$STAGING_DIR/notarization-result.json" <<'PYNOTARY'
import json
import sys
with open(sys.argv[1]) as report:
    result = json.load(report)
if result.get('status') != 'Accepted':
    print(f"Notarization was not accepted: {result.get('status')} (id: {result.get('id')})", file=sys.stderr)
    sys.exit(1)
PYNOTARY
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR"
mkdir -p "$STAGING_DIR/payload"
ditto "$APP_DIR" "$STAGING_DIR/payload/TouchBar HUD.app"
cp "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/README.md" "$PROJECT_DIR/CHANGELOG.md" "$PROJECT_DIR/CONTRIBUTING.md" "$STAGING_DIR/payload/"
ditto "$PROJECT_DIR/docs" "$STAGING_DIR/payload/docs"
ditto -c -k "$STAGING_DIR/payload" "$STAGING_DIR/TouchBarHUD-$VERSION.zip"
mv "$STAGING_DIR/TouchBarHUD-$VERSION.zip" "$RELEASE_DIR/TouchBarHUD-$VERSION.zip"
(cd "$RELEASE_DIR" && shasum -a 256 "TouchBarHUD-$VERSION.zip" > "TouchBarHUD-$VERSION.zip.sha256")
print -r -- "$RELEASE_DIR/TouchBarHUD-$VERSION.zip"
