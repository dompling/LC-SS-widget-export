#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-storage-status-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
# Count entry to the production disk loader in a temporary compilation unit;
# production code has no counters or test-only API.
python3 - "$ROOT" "$WORK/storage.m" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitStorage.m').read_text()
signature='static NSDictionary *Load(NSString *root,BOOL *valid,NSError **error) {'
assert source.count(signature)==1
source=source.replace(signature,'NSUInteger OrbitTestDiskLoads;\n'+signature+'\n    OrbitTestDiskLoads++;',1)
Path(sys.argv[2]).write_text(source)
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework Foundation -I "$ROOT/LCOrbit/Tests/Stubs" -I "$ROOT/LCOrbit/Core" \
    "$ROOT/LCOrbit/Tests/storage_status_tests.m" "$WORK/storage.m" \
    "$ROOT/LCOrbit/Core/LCOrbitGuestService.m" "$ROOT/LCOrbit/Core/LCOrbitMultitask.m" \
    -o "$WORK/storage-status-tests"
"$WORK/storage-status-tests"
