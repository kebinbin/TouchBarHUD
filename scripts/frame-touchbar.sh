#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchbarhud-frame.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
xcrun clang -O2 -fobjc-arc -Wall -Wextra -Werror -framework AppKit \
  "$PROJECT_DIR/scripts/frame-touchbar.m" -o "$STAGING_DIR/frame-touchbar"
"$STAGING_DIR/frame-touchbar" "$PROJECT_DIR/docs/TouchBar-screenshot.png" \
  "$PROJECT_DIR/docs/TouchBar-framed.png"
print 'Generated docs/TouchBar-framed.png.'
