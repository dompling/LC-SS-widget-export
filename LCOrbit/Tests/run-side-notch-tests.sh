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
begin_capsule=source.index('static UIBezierPath *FMOrbDragPath(')
end_capsule=source.index('\n}',begin_capsule)+2
begin_drop=source.index('static UIBezierPath *FMDropletPath(')
end_drop=source.index('\n}',begin_drop)+2
# Pure geometry only: skip UIKit mask/shadow implementation.
style=source[source.index('static NSArray<NSDictionary *> *FMOrbStyleOptions'):source.index('// A mirrored, gently concave')]
Path(sys.argv[2]).write_text(style+'\n'+source[start:end]+'\n'+source[begin_capsule:end_capsule]+'\n'+source[begin_drop:end_drop])
PYTEST
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation -framework CoreGraphics -framework ImageIO -I "$WORK" \
    "$ROOT/LCOrbit/Tests/side_notch_tests.m" -o "$WORK/side-notch-tests"
"$WORK/side-notch-tests"
