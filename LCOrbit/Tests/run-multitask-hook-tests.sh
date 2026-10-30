#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-hook-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/guard.m" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
start=source.index('BOOL OrbitMethodMatches(')
end=source.index('\n// End of Foundation-only ABI guard.',start)
Path(sys.argv[2]).write_text('#import <Foundation/Foundation.h>\n#import <objc/runtime.h>\n#import <string.h>\n'+source[start:end]+'\n')
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -framework Foundation "$ROOT/LCOrbit/Tests/multitask_hook_tests.m" \
    "$WORK/guard.m" -o "$WORK/hook-tests"
"$WORK/hook-tests"
