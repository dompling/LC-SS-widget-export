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
ui = (root / "LCOrbit/Core/LCOrbitMultitaskUI.m").read_text()

checks = {
    "LiveProcess constructor starts diagnostics before returning":
        'NSClassFromString(@"LCOrbitGuestUIKitDiagnostics")' in core and
        core.index('NSSelectorFromString(@"startInLiveProcess")') <
        core.index("if([NSUserDefaults respondsToSelector:process]"),
    "guest diagnostics do not bootstrap the FloatingMenu UI":
        "LCFloatingMenuRegisterWithOrbit" in core and "return;" in core,
    "diagnostic snapshots require explicit user opt in":
        "+ (BOOL)isEnabled" in diag and "if(diagnostics) GuestTakeSnapshot" in diag and
        "if(![LCOrbitGuestUIKitDiagnostics isEnabled]) return;" in diag,
    "only collects in an actual Guest":
        "[LCOrbitHost guestInfo]" in diag and "isLiveProcess" in diag,
    "logs only metadata and geometry":
        "guest-uikit-snapshot" in diag and "safeAreaInsets" in diag and
        "layoutFrame" in diag and "topControls" in diag,
    "top controls record types and frames not text":
        "NSStringFromCGRect" in diag and "NSStringFromClass" in diag and
        ".text" not in diag and "drawViewHierarchy" not in diag,
    "safe-area repair uses installed App folder after selected is removed":
        "NSBundle.mainBundle.bundlePath.lastPathComponent" in diag and
        'objectForKey:@"selected"' not in diag and
        'uikitTopInset.' in diag and 'guestOwnTopInset.' in diag and
        "GuestRelayoutEnabled=GuestUIKitModeSelected()" in diag,
    "host synchronizes enabled UIKit App modes to LiveProcess":
        "synchronizeUIKitModesToGuests" in diag and
        "synchronizeUIKitModesToGuests" in core and
        "synchronizeUIKitModesToGuests" in ui and
        "enabledPaths" in diag and
        "GuestUIKitModeFile()" in diag,

    "repair only after window and root report real insets":
        "if(!isfinite(top) || !isfinite(rootTop) || top<1 || rootTop<1" in diag and
        "fabs(top-rootTop)>2" in diag and
        "GuestRepairedTop=top" in diag,
    "no window shrinking, additional safe inset, or permanent scene hook":
        "GuestSafeAreaRepairTick" in diag and
        "[view setNeedsLayout]" in diag and
        "additionalSafeAreaInsets" not in diag and
        "setFrame:" not in diag and
        "method_exchangeImplementations" not in diag,
    "Baidu top-only fix is opt-in, class-scoped and not a window resize":
        'GuestInstallPath() isEqualToString:@"com.bd.iphone.super.app"' in diag and
        'isEqualToString:@"BDSNavigationController"' in diag and
        'isEqualToString:@"BDSSlideMenuMain"' in diag and
        'GuestIsBaiduTopRepair' in diag and
        'GuestCorrectTopSurface' in diag and
        'GuestRepairBaiduTopSurfaces' in diag and
        'CGRectGetHeight(before)<=85' in diag and
        'CGRectGetWidth(before)>=window.bounds.size.width*.85' in diag,
    "top-only transforms restore on rotation, view replacement and native geometry":
        'GuestRestoreBaiduSurfaces' in diag and
        'GuestRestoreTopSurface(slot)' in diag and
        'CGAffineTransformEqualToTransform' in diag and
        'UIView performWithoutAnimation' in diag and
        'UIInterfaceOrientationIsPortrait(scene.interfaceOrientation)' in diag and
        'fabs(saved.applied-offset)<.5' in diag,
    "local corrections are logged and bounded to the Guest startup/foreground window":
        'guest-uikit-top-surfaces-corrected' in diag and
        'GuestRepairBaiduTopSurfaces(strongWindow,root,top)' in diag and
        'GuestRepairBaiduTopSurfaces(window,root,top)' in diag and
        '@5.0' in diag and
        'method_exchangeImplementations' not in diag,
    "Instagram correction is app-scoped to the inner vertical feed only":
        'com.burbn.instagram.app' in diag and
        'IGRootViewController' in diag and
        'IGHomeFeedHeader.IGHomeFeedHeaderView' in diag and
        'IGGestureCoordinatingCollectionView' in diag and
        'GuestIsVerticalInstagramScroll' in diag and
        'GuestInstagramInnerScroll' in diag and
        'GuestRepairInstagramInnerScroll' in diag and
        'scroll.dragging' in diag and
        'scroll.decelerating' in diag and
        'GuestRestoreInstagramInset' in diag and
        'guest-uikit-instagram-inner-scroll-corrected' in diag and
        'homeHeaderAncestors' in diag and
        'GuestFindInstagramStoryTray' in diag and
        'storyTrayAncestors' in diag and
        'no-vertical-story-ancestor' in diag and
        'GuestCorrectTopSurface(header,window,top' in diag and
        'story-did-not-follow-feed-scroll' in diag and
        'saved.header=header' in diag and
        'GuestRestoreTopSurface(&GuestInstagramHeaderOffset)' in diag and
        'GuestInstagramInnerScroll(story,window)' in diag,
    "Instagram keeps its app-owned 50pt header spacing and restores it":
        'fabs(original.top-headerHeight)<=5' in diag and
        'fabs(storyY-original.top)<=1' in diag and
        'fabs(adjusted.top-original.top)<=4' in diag and
        'fabs(originalOffset.y+adjusted.top)<=0.75' in diag and
        'changed.top+=delta' in diag and
        'originalOffset.y-delta' in diag and
        'saved.originalTop=original.top' in diag and
        'saved.originalOffsetY=originalOffset.y' in diag and
        'story-did-not-follow-feed-scroll' in diag and
        'app-header-inset-or-geometry-mismatch' in diag and
        'scroll.contentInset=inset' in diag,
    "Instagram post-refresh layout is rechecked without touching live drags":
        'GuestStartInstagramWatch' in diag and
        'GuestStopInstagramWatch' in diag and
        'timerWithTimeInterval:0.75 repeats:YES' in diag and
        'forMode:NSDefaultRunLoopMode' in diag and
        'UIApplicationDidEnterBackgroundNotification' in diag and
        'scroll.dragging || scroll.tracking || scroll.decelerating' in diag and
        'fabs(originalOffset.y+adjusted.top)<=0.75' in diag and
        'fabs(y)<=0.75' in diag and
        'guest-uikit-instagram-layout-reset' in diag and
        'fabs(scroll.contentOffset.y+scroll.adjustedContentInset.top)>1' in diag and
        'GuestInstagramNoScrollReported=NO' in diag and
        'GuestSafeAreaRepairTick();' in diag,
    "records actual navigation and upper subview geometry":
        "GuestNavigationGeometry" in diag and
        "GuestTopViews" in diag and
        '@"navigationBefore"' in diag and
        '@"navigationAfter"' in diag,
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
