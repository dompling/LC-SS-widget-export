#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-drawer-entry.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/entry.inc" <<'PY'
from pathlib import Path
import sys
s=(Path(sys.argv[1])/'LCFloatingMenu/LCFloatingMenu.m').read_text()
parts=[]
for signature in ['- (void)toggle {','- (void)refreshInventoryInBackground {']:
    start=s.index(signature)
    parts.append(s[start:s.index('\n}',start)+2])
Path(sys.argv[2]).write_text('\n'.join(parts))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-function \
    -framework Foundation -I "$WORK" "$ROOT/LCOrbit/Tests/drawer_entry_tests.m" -o "$WORK/entry-tests"
"$WORK/entry-tests"
