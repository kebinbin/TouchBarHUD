#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
ANALYSIS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touchbarhud-analysis.XXXXXX")"
trap 'rm -rf "$ANALYSIS_DIR"' EXIT
for SOURCE_FILE in "$PROJECT_DIR/main.m" "$PROJECT_DIR"/Sources/*.m; do
  REPORT_FILE="$ANALYSIS_DIR/${SOURCE_FILE:t}.plist"
  xcrun clang --analyze -arch x86_64 -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
    -Wall -Wextra -Werror -Xanalyzer -analyzer-output=plist "$SOURCE_FILE" -o "$REPORT_FILE"
  if [[ -f "$REPORT_FILE" ]]; then
    python3 - "$REPORT_FILE" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as report:
    diagnostics = plistlib.load(report).get('diagnostics', [])
if diagnostics:
    for item in diagnostics:
        print(item.get('description', item), file=sys.stderr)
    sys.exit(1)
PY
  fi
done
print 'Static analysis passed.'
