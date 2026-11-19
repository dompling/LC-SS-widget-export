#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-native-window-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/NativeTaskRegistry.swift" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / 'MultitaskSupport/MultitaskAppWindow.swift').read_text()
start = '// Native task identity and launch completion state.'
end = '// End native task registry.'
body = source[source.index(start):source.index(end)] if start in source and end in source else ''
Path(sys.argv[2]).write_text('import Foundation\n' + body)
PY
xcrun swiftc -warnings-as-errors "$WORK/NativeTaskRegistry.swift" "$ROOT/LCOrbit/Tests/native_window_registry_tests.swift" -o "$WORK/tests"
"$WORK/tests"
