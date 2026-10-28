#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-json-log-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
set -- "$ROOT/LCOrbit/Tests/json_log_tests.m"
if test -f "$ROOT/LCOrbit/Core/LCOrbitLog.m"; then
    set -- "$@" "$ROOT/LCOrbit/Core/LCOrbitLog.m"
fi
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-incomplete-implementation \
    -framework Foundation -I "$ROOT/LCOrbit/Tests/Stubs" -I "$ROOT/LCOrbit/Core" \
    "$@" -o "$WORK/log-tests"
"$WORK/log-tests"
