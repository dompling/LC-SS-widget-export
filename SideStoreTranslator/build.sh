#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/../dist/SideStoreTranslator.dylib}"
mkdir -p "$(dirname "$OUT")" "$ROOT/.generated"

python3 "$ROOT/scripts/validate_and_embed.py" \
  "$ROOT/zh-Hans.json" "$ROOT/upstream-key-inventory.json" \
  "$ROOT/.generated/STEmbeddedJSON.h"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun clang -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=15.0 -fobjc-arc \
  -Wall -Wextra -Werror \
  -I"$ROOT/.generated" \
  -c "$ROOT/SideStoreTranslator.m" -o "$ROOT/.generated/SideStoreTranslator.o"
xcrun clang -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=15.0 -Wall -Wextra -Werror \
  -c "$ROOT/SwiftUIImports.m" -o "$ROOT/.generated/SwiftUIImports.o"
# Reuse the repository's existing rebinder, keeping its symbols private so it
# cannot collide with LC's separate litehook copy when preloaded before LC.
xcrun clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -fvisibility=hidden -I"$ROOT/../litehook/external/include" \
  -c "$ROOT/../litehook/src/litehook.c" -o "$ROOT/.generated/STLitehook.o"
xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -sdk "$SDK" -O \
  -parse-as-library -import-objc-header "$ROOT/STSwiftUIBridge.h" \
  -emit-object "$ROOT/SwiftUITextBridge.swift" -o "$ROOT/.generated/SwiftUITextBridge.o"
xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -sdk "$SDK" -emit-library \
  -framework Foundation -framework UIKit -framework CoreFoundation \
  -framework SwiftUI \
  -Xlinker -install_name -Xlinker "@rpath/SideStoreTranslator.dylib" \
  "$ROOT/.generated/SideStoreTranslator.o" \
  "$ROOT/.generated/SwiftUIImports.o" "$ROOT/.generated/STLitehook.o" \
  "$ROOT/.generated/SwiftUITextBridge.o" -o "$OUT"

file "$OUT"
xcrun otool -hv "$OUT"
test -s "$OUT"
echo "Built $OUT"
