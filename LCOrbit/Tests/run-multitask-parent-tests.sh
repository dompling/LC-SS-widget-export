#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-parent-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/parent.inc" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
parts=[]
signature='static UIViewController *HostingParentController('
if signature in source:
    start=source.index(signature)
    parts.append(source[start:source.index('\n}',start)+2])
start=source.index('static id InitWindow(')
parts.append(source[start:source.index('\nstatic void Setup(',start)])
Path(sys.argv[2]).write_text('\n'.join(parts))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -Wno-unused-parameter -Wno-unused-function -framework Foundation \
    -I "$WORK" "$ROOT/LCOrbit/Tests/multitask_parent_tests.m" -o "$WORK/parent-tests"
"$WORK/parent-tests"
