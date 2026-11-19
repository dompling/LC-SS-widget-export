#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-ownership-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/ownership.inc" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
start=source.index('static BOOL OrbitPiPProtectedWindow(')
parts=[source[start:source.index('\n}',start)+2]]
signature='static void PiPStarting('
if signature in source:
    start=source.index(signature)
    parts.append(source[start:source.index('\n}',start)+2])
else:
    parts.append('static void PiPStarting(id manager,SEL selector,id controller) { ((void(*)(id,SEL,id))OriginalPiPStarting)(manager,selector,controller); }')
Path(sys.argv[2]).write_text('\n'.join(parts))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework Foundation -I "$WORK" "$ROOT/LCOrbit/Tests/task_ownership_tests.m" -o "$WORK/ownership-tests"
"$WORK/ownership-tests"
