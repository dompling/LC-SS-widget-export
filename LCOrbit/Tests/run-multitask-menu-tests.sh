#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-menu-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/menu.inc" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
parts=[]
for signature in ['static BOOL BeadMenu(', 'static void ShowDock(', 'static void ShowHidden(', 'static void ToggleDock(', 'static void HostingBringToFront(', 'static void Minimize(']:
    if signature not in source:
        continue
    start=source.index(signature)
    parts.append(source[start:source.index('\n}',start)+2])
if 'static void HostingBringToFront(' not in source:
    parts.append('static void HostingBringToFront(id host,SEL selector,id view) { ((void(*)(id,SEL,id))OriginalBringToFront)(host,selector,view); }')
if 'static void Minimize(' not in source:
    parts.append('static void Minimize(UIViewController *window,SEL selector) { ((void(*)(id,SEL))OriginalMinimize)(window,selector); }')
Path(sys.argv[2]).write_text('\n'.join(parts))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-function \
    -framework Foundation -I "$WORK" "$ROOT/LCOrbit/Tests/multitask_menu_tests.m" -o "$WORK/menu-tests"
"$WORK/menu-tests"
