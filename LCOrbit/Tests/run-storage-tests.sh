#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-storage-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -framework Foundation -I "$ROOT/LCOrbit/Tests/Stubs" -I "$ROOT/LCOrbit/Core" \
    "$ROOT/LCOrbit/Tests/storage_tests.m" "$ROOT/LCOrbit/Core/LCOrbitStorage.m" \
    -o "$WORK/storage-tests"
"$WORK/storage-tests"
