#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUT="$(mktemp -d /tmp/sidestore-swiftui-tests.XXXXXX)"
trap 'rm -rf "$TEST_OUT"' EXIT
python3 "$ROOT/scripts/validate_and_embed.py" "$ROOT/zh-Hans.json" \
  "$ROOT/upstream-key-inventory.json" "$TEST_OUT/STEmbeddedJSON.h"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -I"$ROOT" -I"$TEST_OUT" \
  -c "$ROOT/tests/SwiftUILookupFixture.m" -o "$TEST_OUT/lookup.o"
xcrun clang -Wall -Wextra -Werror -c "$ROOT/SwiftUIImports.m" -o "$TEST_OUT/imports.o"
xcrun clang -fblocks -fvisibility=hidden -I"$ROOT/../litehook/external/include" \
  -c "$ROOT/../litehook/src/litehook.c" -o "$TEST_OUT/litehook.o"
xcrun clang -Wall -Wextra -Werror "$ROOT/tests/SwiftUILoader.c" -o "$TEST_OUT/loader"
xcrun swiftc -O -parse-as-library -import-objc-header "$ROOT/STSwiftUIBridge.h" \
  -emit-library "$ROOT/SwiftUITextBridge.swift" "$TEST_OUT/lookup.o" \
  "$TEST_OUT/imports.o" "$TEST_OUT/litehook.o" -o "$TEST_OUT/bridge.dylib"
SUBTITLE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["translations"]["Run ADI emulation directly on device instead of remote servers"])' "$ROOT/zh-Hans.json")"
mkdir -p "$TEST_OUT/SideStoreApp.framework"
for OPTIMIZATION in -Onone -O; do
  xcrun swiftc "$OPTIMIZATION" -emit-library "$ROOT/tests/SwiftUITextProbe.swift" \
    -o "$TEST_OUT/SideStoreApp.framework/SideStore"
  CLIENT="$TEST_OUT/SideStoreApp.framework/SideStore"
  # Negative control: no bridge must reproduce the reported untranslated row.
  if "$TEST_OUT/loader" /usr/lib/libSystem.B.dylib "$CLIENT" --active >"$TEST_OUT/control.log" 2>&1; then
    echo 'FAIL: missing-bridge negative control unexpectedly translated' >&2
    exit 1
  fi
  grep -q 'FAIL: Text(String) settings row' "$TEST_OUT/control.log"
  ST_TEST_SIDESTORE=0 "$TEST_OUT/loader" "$TEST_OUT/bridge.dylib" "$CLIENT"
  ST_TEST_SIDESTORE=1 ST_EXPECTED_SUBTITLE="$SUBTITLE" \
    "$TEST_OUT/loader" "$TEST_OUT/bridge.dylib" "$CLIENT" --active
  # Registering after the guest is loaded must also visit existing imports.
  ST_TEST_CLIENT_FIRST=1 ST_TEST_SIDESTORE=1 ST_EXPECTED_SUBTITLE="$SUBTITLE" \
    "$TEST_OUT/loader" "$TEST_OUT/bridge.dylib" "$CLIENT" --active
  mkdir -p "$TEST_OUT/Unrelated.framework"
  cp "$CLIENT" "$TEST_OUT/Unrelated.framework/Unrelated"
  # Even with a live dictionary, never rewrite imports from another framework.
  ST_TEST_SIDESTORE=1 "$TEST_OUT/loader" "$TEST_OUT/bridge.dylib" \
    "$TEST_OUT/Unrelated.framework/Unrelated"
done
