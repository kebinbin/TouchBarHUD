#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchbarhud-preview.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
xcrun clang -O2 -fobjc-arc -Wall -Wextra -Werror -framework AppKit \
  "$PROJECT_DIR/scripts/generate-preview.m" -o "$STAGING_DIR/generate-preview"
"$STAGING_DIR/generate-preview" "$PROJECT_DIR/docs/TouchBar-preview.png"
print 'Generated docs/TouchBar-preview.png.'
