#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-bootstrap-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/entry.inc" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitCore.m').read_text()
start=source.index('extern void LCFloatingMenuRegisterWithOrbit(')
entry=source[start:].replace('__attribute__((constructor)) ', '')
Path(sys.argv[2]).write_text(entry)
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework Foundation -I "$ROOT/LCOrbit/Tests/Stubs" -I "$ROOT/LCOrbit/Core" -I "$WORK" \
    "$ROOT/LCOrbit/Tests/bootstrap_tests.m" -o "$WORK/bootstrap-tests"
"$WORK/bootstrap-tests"
