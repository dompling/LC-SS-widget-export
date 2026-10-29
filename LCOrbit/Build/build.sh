#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="${1:-$ROOT/dist/LCFloatingMenu.dylib}"
# Embed the source commit so Settings can compare against GitHub accurately.
BUILD_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
case "$BUILD_COMMIT" in
    *[!0-9a-f]*|"") BUILD_COMMIT="unknown" ;;
esac
BUILD_COMMIT_FLAG="-DFM_BUILD_COMMIT=@\"$BUILD_COMMIT\""

# Exercise production scanning, menu selection, favorite persistence and the
# complete plugin-management flow. A failed regression stops this build.
sh "$ROOT/LCOrbit/Tests/run-core-lifecycle-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-storage-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-json-log-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-dock-visibility-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-guest-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-jit-favorites-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-tweak-center-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-multitask-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-automatic-pip-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-side-notch-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-floating-launch-tests.sh"
python3 "$ROOT/LCOrbit/Tests/check-running-close-controls.py"
sh "$ROOT/LCOrbit/Tests/run-multitask-hook-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-dock-surface-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-multitask-restore-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-multitask-parent-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-bootstrap-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-multitask-scene-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-multitask-menu-tests.sh"
sh "$ROOT/LCOrbit/Tests/run-host-settings-tests.sh"
python3 "$ROOT/LCOrbit/Tests/check-host-gestures.py"
mkdir -p "$(dirname "$OUT")"
xcrun clang "$BUILD_COMMIT_FLAG" -arch arm64 -isysroot "$SDK" -miphoneos-version-min=16.0 -fobjc-arc -O2 \
    -dynamiclib -framework Foundation -framework UIKit -framework QuartzCore \
    -framework CoreGraphics -install_name '@rpath/LCFloatingMenu.dylib' \
    "$ROOT/LCOrbit/Core/LCOrbitCore.m" \
    "$ROOT/LCOrbit/Core/LCOrbitHost.m" \
    "$ROOT/LCOrbit/Core/LCOrbitGuestService.m" \
    "$ROOT/LCOrbit/Core/LCOrbitMultitask.m" \
    "$ROOT/LCOrbit/Core/LCOrbitAutomaticPiP.m" \
    "$ROOT/LCOrbit/Core/LCOrbitMultitaskUI.m" \
    "$ROOT/LCOrbit/Core/LCOrbitHostSettings.m" \
    "$ROOT/LCOrbit/Core/LCOrbitEventBus.m" \
    "$ROOT/LCOrbit/Core/LCOrbitOverlayManager.m" \
    "$ROOT/LCOrbit/Core/LCOrbitStorage.m" \
    "$ROOT/LCOrbit/Core/LCOrbitLog.m" \
    "$ROOT/LCOrbit/Core/LCOrbitTweakAudit.m" \
    "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m" \
    "$ROOT/LCOrbit/Core/LCOrbitTweakCenter.m" \
    "$ROOT/LCOrbit/Core/LCOrbitPluginUpdater.m" \
    "$ROOT/LCOrbit/Core/LCOrbitTweakCenterViews.m" \
    "$ROOT/LCOrbit/Core/LCOrbitSharedTweaksViewController.m" \
    "$ROOT/LCOrbit/Core/LCOrbitLogViewer.m" \
    "$ROOT/LCFloatingMenu/LCFloatingMenu.m" \
    -o "$OUT"
file "$OUT"
xcrun lipo -info "$OUT"
sh "$ROOT/LCOrbit/Tests/verify.sh" "$OUT"
