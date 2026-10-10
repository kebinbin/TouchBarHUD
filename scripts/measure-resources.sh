#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TOOL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchbarhud-resources.XXXXXX")"
trap 'rm -rf "$TOOL_DIR"' EXIT
xcrun clang -O2 -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
  "$PROJECT_DIR/scripts/measure-resources.m" -o "$TOOL_DIR/measure-resources"
"$TOOL_DIR/measure-resources" "$@"
