#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-viewport-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/viewport.inc" <<'PY'
from pathlib import Path
import sys

root=Path(sys.argv[1])
source=(root/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
native=(root/'MultitaskSupport/UIKitHooks.m').read_text()
parts=[]
for text,signature in [
    (source,'static BOOL OrbitValidFrame('),
    (source,'static BOOL PhysicalTopAvoidanceEnabled('),
    (source,'static BOOL GuestOwnsTopInset('),
    (source,'static CGRect GuestViewport('),
    (source,'static BOOL OrbitInsetsInViewport('),
    (source,'static UIEdgeInsets PortraitInsets('),
    (native,'UIEdgeInsets LCUIEdgeInsetsRotateToOrientation('),
]:
    if signature not in text:
        raise SystemExit(f'Missing production helper: {signature}')
    start=text.index(signature)
    parts.append(text[start:text.index('\n}',start)+2])
Path(sys.argv[2]).write_text('\n'.join(parts))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -Wno-unused-function -framework Foundation -framework CoreGraphics \
    -I "$WORK" "$ROOT/LCOrbit/Tests/multitask_viewport_tests.m" -o "$WORK/viewport-tests"
"$WORK/viewport-tests"
