#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchbarhud-icons.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$STAGING_DIR/AppIcon.iconset" "$STAGING_DIR/Resources" "$PROJECT_DIR/Resources"
xcrun clang -O2 -fobjc-arc -Wall -Wextra -Werror \
  -framework Foundation -framework CoreGraphics -framework ImageIO \
  "$PROJECT_DIR/scripts/generate-icons.m" -o "$STAGING_DIR/generate-icons"
"$STAGING_DIR/generate-icons" "$STAGING_DIR/Resources" "$STAGING_DIR/AppIcon.iconset"
iconutil -c icns "$STAGING_DIR/AppIcon.iconset" -o "$STAGING_DIR/Resources/AppIcon.icns"
cp "$STAGING_DIR"/Resources/* "$PROJECT_DIR/Resources/"
print 'Generated app icon, menu-bar mark, and SVG/PNG logo in Resources/.'
