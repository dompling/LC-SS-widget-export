#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-github-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-incomplete-implementation \
    -framework Foundation -framework Security -I "$ROOT/LCOrbit/Tests/Stubs" \
    "$ROOT/LCOrbit/Tests/github_access_tests.m" -o "$WORK/github-tests"
"$WORK/github-tests"
