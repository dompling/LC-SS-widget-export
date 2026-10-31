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
end=source.index('\n}',start)+2
# Pure geometry only: skip UIKit mask/shadow implementation. This covers the
# style settings, the notch family and the handle metrics.
style=source[source.index('static NSArray<NSDictionary *> *FMOrbStyleOptions'):source.index('// A mirrored, gently concave')]
# The drawer morph is a self-contained block between two markers.
begin_motion=source.index('// FMDrawerMotion:begin')
end_motion=source.index('// FMDrawerMotion:end')
Path(sys.argv[2]).write_text(style+'\n'+source[start:end]+'\n'+source[begin_motion:end_motion])
PYTEST
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation -framework CoreGraphics -framework ImageIO -I "$WORK" \
    "$ROOT/LCOrbit/Tests/side_notch_tests.m" -o "$WORK/side-notch-tests"
"$WORK/side-notch-tests"
