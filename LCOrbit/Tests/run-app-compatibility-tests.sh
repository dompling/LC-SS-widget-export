#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-compatibility-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK" <<'EXTRACT'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
source=(root/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
parts=[]
for signature in ['static BOOL PhysicalTopAvoidanceEnabled(', 'static BOOL GuestOwnsTopInset(', '+ (BOOL)usesAppTopInsetForBundle:', '+ (void)setUsesAppTopInset:']:
    if signature not in source:
        raise SystemExit('Missing compatibility API: '+signature)
    start=source.index(signature)
    end=source.index('}',start)+1 if signature.startswith('+ (BOOL)') else source.index('\n}',start)+2
    parts.append(source[start:end])
(work/'compatibility.inc').write_text('\n'.join(parts[:2])+'\n@implementation LCOrbitMultitask (Compatibility)\n'+'\n'.join(parts[2:])+'\n@end\n')
menu=(root/'LCFloatingMenu/LCFloatingMenu.m').read_text()
start=menu.index('- (void)compatibilityPage:(UIStackView *)stack {')
page=menu[start:menu.index('\n}',start)+2]
assert 'InstalledApps()' in page and 'iconViewForApp:app' in page and 'app[@"title"]' in page
assert 'app[@"path"]' in page and 'app[@"bundle"]' not in page, 'Scene bundleId is the relative install path'
for gate in ['activeWindow', 'isManagingWindows', 'isEnabled', 'visibleApps', 'launchable', 'hidden', 'locked']:
    assert gate not in page, 'Compatibility inventory must not be gated by '+gate
assert 'usesAppTopInsetForBundle:' in page and 'guestTopInsetChanged:' in page
assert '@"应用兼容性"' in menu and '@selector(openCompatibility)' in menu
assert '@"compatibility":@"应用兼容性"' in menu
assert '当前 App 顶部布局' not in menu
print('Compatibility settings source contracts: passed')
EXTRACT
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -framework Foundation \
    -I "$WORK" "$ROOT/LCOrbit/Tests/app_compatibility_tests.m" -o "$WORK/compatibility-tests"
"$WORK/compatibility-tests"
