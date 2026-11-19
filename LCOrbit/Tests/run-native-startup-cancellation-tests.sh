#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-native-startup-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'MultitaskSupport/AppSceneViewController.m').read_text()
work=Path(sys.argv[2])
start=source.index('    [_extension beginExtensionRequestWithInputItems:')
end=source.index('\n    }];', start)+len('\n    }];')
(work/'begin-request.inc').write_text(source[start:end])
methods=[]
for signature in ['- (void)terminate {', '- (void)appTerminationCleanUp {',
                  '- (void)extensionRequestDidComplete:', '- (void)cancelExtensionRequest:']:
    if signature in source:
        start=source.index(signature)
        methods.append(source[start:source.index('\n}',start)+2])
(work/'startup-methods.inc').write_text('\n'.join(methods))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Wno-incomplete-implementation \
    -framework Foundation -I "$WORK" "$ROOT/LCOrbit/Tests/native_startup_cancellation_tests.m" -o "$WORK/tests"
"$WORK/tests"
