#!/bin/sh
# Build-output smoke check; behavior on a physical Guest still requires device tests.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="${1:-$ROOT/dist/LCFloatingMenu.dylib}"
test -s "$BINARY"
test "$(xcrun lipo -archs "$BINARY")" = 'arm64'
xcrun vtool -show-build "$BINARY" | grep -q 'platform IOS'
xcrun vtool -show-build "$BINARY" | grep -q 'minos 16.0'
xcrun otool -D "$BINARY" | grep -Fq '@rpath/LCFloatingMenu.dylib'
SYMBOLS="$(xcrun nm -gU "$BINARY")"
for symbol in 'OBJC_CLASS_$_LCOrbitCore' 'OBJC_CLASS_$_LCOrbitHost' \
              'OBJC_CLASS_$_LCOrbitOverlayManager' 'OBJC_CLASS_$_LCOrbitEventBus' \
              'OBJC_CLASS_$_LCOrbitGuestService' \
              'OBJC_CLASS_$_LCOrbitMultitask' \
              'OBJC_CLASS_$_LCOrbitHostSettings' \
              'OBJC_CLASS_$_LCFloatingMenuModule' '_LCFloatingMenuRegisterWithOrbit'
do
    printf '%s\n' "$SYMBOLS" | grep -Fq "$symbol"
done
# Guard existing preferences and the old Guest switch pathway from accidental deletion.
grep -Fq 'forModule:@"LCFloatingMenu"' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'launchToGuestAppWithURL:' "$ROOT/LCOrbit/Core/LCOrbitGuestService.m"
grep -Fq 'LCOpenSideStore' "$ROOT/LCOrbit/Core/LCOrbitGuestService.m"
# Assert the dangerous regression patterns from the review stay fixed.
grep -Fq 'if(created) _window.hidden=NO' "$ROOT/LCOrbit/Core/LCOrbitOverlayManager.m"
# The developer-only tweak-to-host option should display an overlay in LC UI
# without loosening the existing Guest, SideStore, or LiveProcess exclusions.
grep -Fq '+ (BOOL)isHostUI' "$ROOT/LCOrbit/Core/LCOrbitHost.m"
grep -Fq 'boolForKey:@"LCLoadTweaksToSelf"' "$ROOT/LCOrbit/Core/LCOrbitHost.m"
grep -Fq 'if(!scene || (!GuestInfo() && !FMHostUI())) return;' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'if(FMHostUI()) return;' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'lc-host-foreground' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'if(hostUI) safeBottom=MAX(safeBottom,100);' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'FMLog(@"panel-layout"' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'if(strong && FMHostUI())' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'appearancePollGeneration!=generation' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'self.overlayView.overrideUserInterfaceStyle=' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
if grep -Fq 'self.window.overrideUserInterfaceStyle=' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"; then
    echo 'Theme override escaped module layer' >&2
    exit 1
fi
# Both log sources need their own viewer, storage, and export support.
grep -Fq 'LCOrbit/Core/LCOrbitTweakAudit.m' "$ROOT/LCOrbit/Build/build.sh"
grep -Fq 'LCOrbit/Core/LCOrbitLogViewer.m' "$ROOT/LCOrbit/Build/build.sh"
grep -Fq 'event=overlay-ready' "$ROOT/LCFloatingMenu/README.md" || true
grep -Fq '@selector(openMenuLogs)' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq '@selector(openTweakLogs)' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'captureSnapshot' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'kind:@"tweaks"' "$ROOT/LCOrbit/Core/LCOrbitTweakAudit.m"
grep -Fq 'LCOrbit/Core/LCOrbitLog.m' "$ROOT/LCOrbit/Build/build.sh"
grep -Fq 'AuditSharedStorage(images,lines);' "$ROOT/LCOrbit/Core/LCOrbitTweakAudit.m"
grep -Fq 'shared-app %@ selected=%@ FloatingMenu=%@' "$ROOT/LCOrbit/Core/LCOrbitTweakAudit.m"
grep -Fq 'shared-disk scope=files-only' "$ROOT/LCOrbit/Core/LCOrbitTweakAudit.m"
grep -Fq 'initWithTweakAudit:' "$ROOT/LCOrbit/Core/LCOrbitLogViewer.m"
grep -Fq 'refreshCurrent' "$ROOT/LCOrbit/Core/LCOrbitLogViewer.m"
grep -Fq 'exportCurrent' "$ROOT/LCOrbit/Core/LCOrbitLogViewer.m"
grep -Fq 'confirmClear' "$ROOT/LCOrbit/Core/LCOrbitLogViewer.m"
# Manual sharing requires confirmation; automatic sharing requires its opt-in switch.
grep -Fq 'LCOrbit/Core/LCOrbitTweakSync.m' "$ROOT/LCOrbit/Build/build.sh"
grep -Fq 'if(![LCOrbitHost isHostUI])' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'name isEqualToString:@"TweakLoader.dylib"' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'RegularFile(privatePath)' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'contentsEqualAtPath:from andPath:temporary' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'automaticSyncEnabledForPlugin:' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'openSharedTweaks' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'manual-sync' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
# Shared tweaks must have a standalone, host-only manager with explicit batch controls.
grep -Fq 'LCOrbit/Core/LCOrbitSharedTweaksViewController.m' "$ROOT/LCOrbit/Build/build.sh"
grep -Fq 'openSharedTweaks' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'action:@selector(openSharedTweaks)' "$ROOT/LCFloatingMenu/LCFloatingMenu.m"
grep -Fq 'action:@selector(confirmTweakSync)' "$ROOT/LCFloatingMenu/LCFloatingMenu.m" && {
    echo 'Old sync action is still exposed in the diagnostic view' >&2
    exit 1
}
grep -Fq 'pluginInventory' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'applyShare:(BOOL)share names:' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'unlink(actual.fileSystemRepresentation)' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'TweakLoader.dylib' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
grep -Fq 'confirmShare:(BOOL)share' "$ROOT/LCOrbit/Core/LCOrbitSharedTweaksViewController.m"
grep -Fq '全选可共享插件' "$ROOT/LCOrbit/Core/LCOrbitSharedTweaksViewController.m"
grep -Fq '全选已共享插件' "$ROOT/LCOrbit/Core/LCOrbitSharedTweaksViewController.m"
grep -Fq '取消共享选中' "$ROOT/LCOrbit/Core/LCOrbitSharedTweaksViewController.m"
# Tweak Center 2.0: actual LC loader assignments, protected host and recoverable file operations.
grep -Fq 'LCOrbit/Core/LCOrbitTweakCenter.m' "$ROOT/LCOrbit/Build/build.sh"
grep -Fq 'LCOrbit/Core/LCOrbitTweakCenterViews.m' "$ROOT/LCOrbit/Build/build.sh"
grep -Fq 'TCManagedName' "$ROOT/LCOrbit/Core/LCOrbitTweakCenter.m"
grep -Fq 'LCTweakFolder' "$ROOT/LCOrbit/Core/LCOrbitTweakCenter.m"
grep -Fq 'originalInfo=[NSData dataWithContentsOfFile:infoFile' "$ROOT/LCOrbit/Core/LCOrbitTweakCenter.m"
grep -Fq '.rollback.tmp' "$ROOT/LCOrbit/Core/LCOrbitTweakCenter.m"
if grep -Fq 'TCAppBackupRoot' "$ROOT/LCOrbit/Core/LCOrbitTweakCenter.m" ||
   grep -Fq 'PluginBackups' "$ROOT/LCOrbit/Core/LCOrbitPluginUpdater.m"; then
    echo 'Persistent plugin backups must not return' >&2
    exit 1
fi
grep -Fq 'name isEqualToString:@"LCFloatingMenu.dylib"' "$ROOT/LCOrbit/Core/LCOrbitTweakCenter.m"
grep -Fq 'appAssignmentsWithBackground:' "$ROOT/LCOrbit/Core/LCOrbitSharedTweaksViewController.m"
grep -Fq 'pluginDetailsForName:' "$ROOT/LCOrbit/Core/LCOrbitSharedTweaksViewController.m"
grep -Fq 'sharedDisabled' "$ROOT/LCOrbit/Core/LCOrbitTweakSync.m"
echo 'LCOrbit Stage 1 static smoke checks: PASS'
