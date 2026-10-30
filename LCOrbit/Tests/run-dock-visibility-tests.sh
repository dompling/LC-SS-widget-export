#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-dock-visibility.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/visibility.inc" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
start=source.find('static void ApplyDockSurfaceVisibility(')
part=source[start:source.index('\n}',start)+2] if start>=0 else 'static void ApplyDockSurfaceVisibility(UIView *view,BOOL suppress) {}'
Path(sys.argv[2]).write_text(part)
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-variable \
    -framework Foundation -I "$WORK" "$ROOT/LCOrbit/Tests/dock_visibility_tests.m" -o "$WORK/visibility-tests"
"$WORK/visibility-tests"
