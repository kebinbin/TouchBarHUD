#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/build"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
mkdir -p "$BUILD_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/TouchBar HUD.app"
CONTENTS_DIR="$APP_DIR/Contents"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

# The currently tested backend targets Intel; Apple silicon compatibility is not established.
xcrun clang -arch x86_64 -mmacosx-version-min=13.0 -O2 -fobjc-arc -fblocks \
  -Wall -Wextra -Werror \
  -framework ApplicationServices -framework Cocoa -framework Carbon \
  -framework CoreGraphics -framework IOSurface -framework QuartzCore -framework ServiceManagement \
  "$PROJECT_DIR/main.m" "$PROJECT_DIR"/Sources/*.m \
  -o "$CONTENTS_DIR/MacOS/TouchBarHUD"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$PROJECT_DIR/Resources/StatusIcon.pdf" "$CONTENTS_DIR/Resources/"
plutil -lint "$CONTENTS_DIR/Info.plist"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_DIR"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi
codesign --verify --strict "$APP_DIR"

# Replace the previous bundle only after compilation and signing succeed.
rm -rf "$BUILD_DIR/TouchBar HUD.app"
mv "$APP_DIR" "$BUILD_DIR/TouchBar HUD.app"
print -r -- "$BUILD_DIR/TouchBar HUD.app"
