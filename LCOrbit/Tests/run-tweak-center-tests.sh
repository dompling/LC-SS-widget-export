#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-tweak-center-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
# Only these two no-op libraries are loaded; user-installed dylibs are never used.
printf 'int orbit_test_a(void) { return 1; }\n' > "$WORK/a.c"
printf 'int orbit_test_b(void) { return 2; }\n' > "$WORK/b.c"
xcrun --sdk macosx clang -dynamiclib "$WORK/a.c" -o "$WORK/A.dylib"
xcrun --sdk macosx clang -dynamiclib "$WORK/b.c" -o "$WORK/B.dylib"
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -Wno-logical-op-parentheses -framework Foundation \
    -I "$ROOT/LCOrbit/Tests/Stubs" -I "$ROOT/LCOrbit/Core" \
    "$ROOT/LCOrbit/Tests/tweak_center_tests.m" \
    "$ROOT/LCOrbit/Core/LCOrbitGuestService.m" \
    "$ROOT/LCOrbit/Core/LCOrbitMultitask.m" \
    "$ROOT/LCOrbit/Core/LCOrbitStorage.m" \
    "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m" \
    "$ROOT/LCOrbit/Core/LCOrbitTweakCenter.m" \
    -o "$WORK/center-tests"
"$WORK/center-tests" "$WORK/A.dylib" "$WORK/B.dylib"
