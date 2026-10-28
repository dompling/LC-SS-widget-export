#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-side-notch.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/side-notch.inc" <<'PYTEST'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCFloatingMenu/LCFloatingMenu.m').read_text()
start=source.index('static UIBezierPath *FMSideNotchPath(')
Path(sys.argv[2]).write_text(source[start:source.index('\n}',start)+2])
PYTEST
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation -framework CoreGraphics -I "$WORK" \
    "$ROOT/LCOrbit/Tests/side_notch_tests.m" -o "$WORK/side-notch-tests"
"$WORK/side-notch-tests"
