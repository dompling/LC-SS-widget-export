#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-dock-surface.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/dock-surface.inc" <<'PYTEST'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
start=source.find('static BOOL OrbitDockShouldSuppress(')
if start<0:
    raise SystemExit('FAIL: native dock suppression policy missing')
Path(sys.argv[2]).write_text(source[start:source.index('\n}',start)+2])
PYTEST
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation -I "$WORK" "$ROOT/LCOrbit/Tests/dock_surface_tests.m" -o "$WORK/dock-tests"
"$WORK/dock-tests"
python3 "$ROOT/LCOrbit/Tests/check-dock-surface.py"
