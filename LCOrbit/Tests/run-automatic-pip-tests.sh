#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-auto-pip-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -framework Foundation -framework CoreGraphics \
    -I "$ROOT/LCOrbit/Tests/AutoPiPUIKit" -I "$ROOT/LCOrbit/Core" \
    "$ROOT/LCOrbit/Tests/automatic_pip_tests.m" \
    "$ROOT/LCOrbit/Core/LCOrbitAutomaticPiP.m" -o "$WORK/automatic-pip-tests"
"$WORK/automatic-pip-tests"
