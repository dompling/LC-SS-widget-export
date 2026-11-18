#!/usr/bin/env python3
"""Source contracts for the opt-in, read-only LiveProcess UIKit diagnostic.

The full build also compiles the actual UIKit Objective-C for iPhone arm64.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
core = (root / "LCOrbit/Core/LCOrbitCore.m").read_text()
diag_file = root / "LCOrbit/Core/LCOrbitGuestUIKitDiagnostics.m"
header_file = root / "LCOrbit/Core/LCOrbitGuestUIKitDiagnostics.h"
diag = diag_file.read_text() if diag_file.exists() else ""
header = header_file.read_text() if header_file.exists() else ""
logger = (root / "LCOrbit/Core/LCOrbitLog.m").read_text()
menu = (root / "LCFloatingMenu/LCFloatingMenu.m").read_text()
build = (root / "LCOrbit/Build/build.sh").read_text()

checks = {
    "LiveProcess constructor starts diagnostics before returning":
        'NSClassFromString(@"LCOrbitGuestUIKitDiagnostics")' in core and
        core.index('NSSelectorFromString(@"startInLiveProcess")') <
        core.index("if([NSUserDefaults respondsToSelector:process]"),
    "guest diagnostics do not bootstrap the FloatingMenu UI":
        "LCFloatingMenuRegisterWithOrbit" in core and "return;" in core,
    "requires explicit user opt in":
        "+ (BOOL)isEnabled" in diag and "if(![self isEnabled]) return;" in diag,
    "only collects in an actual Guest":
        "[LCOrbitHost guestInfo]" in diag and "isLiveProcess" in diag,
    "logs only metadata and geometry":
        "guest-uikit-snapshot" in diag and "safeAreaInsets" in diag and
        "layoutFrame" in diag and "topControls" in diag,
    "top controls record types and frames not text":
        "NSStringFromCGRect" in diag and "NSStringFromClass" in diag and
        ".text" not in diag and "drawViewHierarchy" not in diag,
    "bounded synchronized output shared between processes":
        "flock(" in diag and "O_NOFOLLOW" in diag and "GuestUIKit" in diag,
    "host runtime export includes Guest measurements":
        'NSSelectorFromString(@"events")' in logger and
        'NSClassFromString(@"LCOrbitGuestUIKitDiagnostics")' in logger,
    "user can enable on host":
        "guestUIKitDiagnosticsChanged:" in menu and
        "[LCOrbitGuestUIKitDiagnostics isEnabled]" in menu,
    "compiled for iOS arm64":
        "$ROOT/LCOrbit/Core/LCOrbitGuestUIKitDiagnostics.m" in build,
    "public header exists":
        "@interface LCOrbitGuestUIKitDiagnostics" in header,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
print(f"Guest UIKit diagnostics source contract: {len(checks)-len(failed)}/{len(checks)}")
if failed:
    raise SystemExit(1)
