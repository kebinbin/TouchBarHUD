#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/build/TouchBar HUD.app"
if [[ ! -d "$APP_DIR" ]]; then
  print -u2 'Build the app with ./build.sh first.'
  exit 1
fi

SIGNATURE="$(codesign --display --verbose=2 "$APP_DIR" 2>&1)"
if [[ "$SIGNATURE" != *'Signature=adhoc'* ]]; then
  print -u2 'The free beta package expects the default ad hoc signed build.'
  exit 1
fi
codesign --verify --strict "$APP_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 'Expected a three-part numeric app version.'
  exit 1
fi

RELEASE_DIR="$PROJECT_DIR/build/releases"
ARCHIVE_NAME="TouchBarHUD-$VERSION-beta-adhoc.zip"
mkdir -p "$RELEASE_DIR"
if [[ -e "$RELEASE_DIR/$ARCHIVE_NAME" || -e "$RELEASE_DIR/$ARCHIVE_NAME.sha256" ]]; then
  print -u2 'This beta archive already exists; refusing to replace it.'
  exit 1
fi

STAGING_DIR="$(mktemp -d "$RELEASE_DIR/.beta.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$STAGING_DIR/payload"
ditto --norsrc --noextattr --noqtn --noacl "$APP_DIR" "$STAGING_DIR/payload/TouchBar HUD.app"
cp "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/README.md" "$PROJECT_DIR/CHANGELOG.md" \
  "$STAGING_DIR/payload/"
ditto "$PROJECT_DIR/docs" "$STAGING_DIR/payload/docs"
ditto --norsrc --noextattr --noqtn --noacl -c -k "$STAGING_DIR/payload" "$STAGING_DIR/$ARCHIVE_NAME"
(cd "$STAGING_DIR" && shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256")
mv "$STAGING_DIR/$ARCHIVE_NAME" "$STAGING_DIR/$ARCHIVE_NAME.sha256" "$RELEASE_DIR/"
print -r -- "$RELEASE_DIR/$ARCHIVE_NAME"
