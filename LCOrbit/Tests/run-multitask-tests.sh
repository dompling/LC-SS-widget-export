#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-multitask-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
set -- "$ROOT/LCOrbit/Tests/multitask_tests.m"
if test -f "$ROOT/LCOrbit/Core/LCOrbitMultitask.m"; then
    set -- "$@" "$ROOT/LCOrbit/Core/LCOrbitMultitask.m"
fi
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -framework Foundation -I "$ROOT/LCOrbit/Tests/Stubs" -I "$ROOT/LCOrbit/Core" \
    "$@" "$ROOT/LCOrbit/Core/LCOrbitStorage.m" -o "$WORK/multitask-tests"
LC_HOME_PATH="$WORK/host" "$WORK/multitask-tests"
