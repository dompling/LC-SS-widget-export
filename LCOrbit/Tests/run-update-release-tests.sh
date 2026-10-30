#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-update-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -framework Foundation \
    "$ROOT/LCOrbit/Tests/update_release_tests.m" "$ROOT/LCOrbit/Core/LCOrbitUpdateRelease.m" -o "$WORK/update-tests"
"$WORK/update-tests"
