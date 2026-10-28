#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-host-recovery.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/host-settings-policy.inc" <<'PYTEST'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitHostSettings.m').read_text()
parts=[]
for signature in ['static BOOL IsDataManagementTitle(', 'static BOOL HostGestureAllowed(']:
    start=source.index(signature)
    parts.append(source[start:source.index('\n}',start)+2])
Path(sys.argv[2]).write_text('\n'.join(parts))
PYTEST
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -I "$WORK" \
    "$ROOT/LCOrbit/Tests/host_settings_tests.m" -o "$WORK/settings-tests"
"$WORK/settings-tests"
python3 "$ROOT/LCOrbit/Tests/check-host-gestures.py"
