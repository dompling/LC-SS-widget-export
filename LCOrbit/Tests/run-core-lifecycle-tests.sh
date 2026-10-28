#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-core-lifecycle.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/core.inc" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitCore.m').read_text()
parts=[]
for method in ['- (void)synchronizeModuleStates {','- (BOOL)registerModule:', '- (BOOL)isModuleEnabled:', '- (void)setModule:', '- (void)notifyModules:']:
    if method in source:
        start=source.index(method)
        parts.append(source[start:source.index('\n}',start)+2])
Path(sys.argv[2]).write_text('\n'.join(parts))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework Foundation -I "$WORK" "$ROOT/LCOrbit/Tests/core_lifecycle_tests.m" -o "$WORK/core-tests"
"$WORK/core-tests"
