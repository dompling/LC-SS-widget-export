#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-floating-launch.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCFloatingMenu/LCFloatingMenu.m').read_text()
work=Path(sys.argv[2])
def method(signature):
    start=source.index(signature+' {', source.index('@implementation FMManager'))
    return source[start:source.index('\n}',start)+2]
parts=[method('- (void)launchApp:(NSDictionary *)app'),method('- (void)detachFromScene')]
if '- (void)invalidatePendingLaunch {' in source:
    parts.insert(0,method('- (void)invalidatePendingLaunch'))
(work/'launch.inc').write_text('\n'.join(parts))
start=source.index('self.configurationObserver=[NSNotificationCenter.defaultCenter addObserverForName:')
end=source.index('\n            }];',start)+len('\n            }];')
(work/'launch-observer.inc').write_text(source[start:end])
parts=[method('- (void)orbitWillStop'),method('- (void)orbitDidReceiveLifecycleEvent:(NSString *)event scene:(UIWindowScene *)scene')]
(work/'launch-module.inc').write_text('\n'.join(parts))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework Foundation -I "$WORK" "$ROOT/LCOrbit/Tests/floating_launch_tests.m" -o "$WORK/launch-tests"
"$WORK/launch-tests"
