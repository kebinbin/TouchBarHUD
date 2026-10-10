#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TOOL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchbarhud-stress.XXXXXX")"
STRESS_PID=''
cleanup() {
  if [[ -n "$STRESS_PID" ]] && kill -0 "$STRESS_PID" 2>/dev/null; then
    kill "$STRESS_PID"
    wait "$STRESS_PID" || true
  fi
  rm -rf "$TOOL_DIR"
}
trap cleanup EXIT INT TERM
xcrun clang -arch x86_64 -mmacosx-version-min=13.0 -O2 -fobjc-arc -fblocks -Wall -Wextra -Werror -I "$PROJECT_DIR/Sources" \
  -framework Cocoa -framework CoreGraphics -framework IOSurface -framework QuartzCore \
  "$PROJECT_DIR/Tests/ResourceStress.m" "$PROJECT_DIR/Sources/TBHTouchBarController.m" \
  "$PROJECT_DIR/Sources/TBHSurfaceView.m" "$PROJECT_DIR/Sources/TBHGeometry.m" -o "$TOOL_DIR/Stress"
"$TOOL_DIR/Stress" &
STRESS_PID=$!
sleep 3
"$PROJECT_DIR/scripts/measure-resources.sh" "$STRESS_PID" 35
wait "$STRESS_PID"
STRESS_PID=''
