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
  -dynamiclib \
  -framework Foundation -framework UIKit -framework CoreFoundation \
  -install_name "@rpath/SideStoreTranslator.dylib" \
  "$ROOT/SideStoreTranslator.m" -o "$OUT"

file "$OUT"
xcrun otool -hv "$OUT"
test -s "$OUT"
echo "Built $OUT"
