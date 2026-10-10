#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/TouchBar HUD.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$MACOS_DIR"

xcrun clang \
  -arch x86_64 \
  -mmacosx-version-min=13.0 \
  -fobjc-arc \
  -fblocks \
  -Wall \
  -Wextra \
  -Werror \
  -framework ApplicationServices \
  -framework Cocoa \
  -framework Carbon \
  -framework CoreGraphics \
  -framework IOSurface \
  -framework QuartzCore \
  "$PROJECT_DIR/main.m" \
  -o "$MACOS_DIR/TouchBarHUD"

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
