#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-restore-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
source=(root/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
start=source.index('static void RestoreAppearance(')
end=source.index('\nstatic void SetVisible(',start)
(work/'restore.inc').write_text(source[start:end])
native=(root/'MultitaskSupport/DecoratedAppSceneViewController.m').read_text()
methods=[]
for signature in ['- (void)updateOriginalFrame {','- (void)updateWindowedFrameWithSettings:', '- (void)appSceneVC:(AppSceneViewController*)vc didUpdateFromSettings:', '- (void)appSceneVCWillActivateScene:']:
    start=native.index(signature)
    end=native.index('\n}',start)+2
    methods.append(native[start:end])
(work/'native.inc').write_text('\n'.join(methods))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -framework Foundation -framework CoreGraphics -framework QuartzCore \
    -I "$WORK" "$ROOT/LCOrbit/Tests/multitask_restore_tests.m" -o "$WORK/restore-tests"
"$WORK/restore-tests"
