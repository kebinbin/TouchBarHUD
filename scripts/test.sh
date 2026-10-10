#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchbarhud-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -arch x86_64 -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  -Wall -Wextra -Werror -I "$PROJECT_DIR/Sources" \
  -framework Cocoa -framework ApplicationServices -framework Carbon \
  -framework CoreGraphics -framework IOSurface -framework QuartzCore -framework ServiceManagement \
  "$PROJECT_DIR/Tests/Tests.m" "$PROJECT_DIR"/Sources/*.m -o "$TEST_DIR/Tests"
"$TEST_DIR/Tests" "$@"
