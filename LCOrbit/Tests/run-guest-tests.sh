#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-guest-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
# Compile the actual small menu method, not a rewritten approximation. Its
# UIKit owner is replaced by a minimal Foundation owner for this test target.
python3 - "$ROOT" "$WORK/menu.m" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
source=(root/'LCFloatingMenu/LCFloatingMenu.m').read_text()
start=source.index('- (NSArray<NSDictionary*> *)visibleApps {')
end=source.index('\n- (NSArray<NSString*> *)favorites',start)
method=source[start:end]
action_start=source.index('- (void)switchFromRow:(UIControl *)sender {')
action_end=source.index('\n@end',action_start)
action=source[action_start:action_end]
header='''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
@class UIControl;
#import "LCOrbitGuestService.h"
extern NSString *OrbitTestGuestID(void);
extern NSUserDefaults *OrbitTestDefaults(void);
static NSString *GuestID(void) { return OrbitTestGuestID(); }
static NSUserDefaults *HostDefaults(void) { return OrbitTestDefaults(); }
static NSString *Pref(NSString *key) { return [@"test." stringByAppendingString:key]; }
@interface FMManager : NSObject
@property(nonatomic,copy) NSArray<NSDictionary *> *apps;
- (NSArray<NSDictionary *> *)visibleApps;
- (void)switchFromRow:(UIControl *)sender;
@end
@interface FMManager (TestPresentationBoundary)
- (void)confirmTitle:(NSString *)title action:(void(^)(void))action;
- (void)showMessage:(NSString *)title details:(NSString *)detail;
- (void)launchApp:(NSDictionary *)app;
- (void)openBuiltinSideStore;
@end
@implementation FMManager
'''
Path(sys.argv[2]).write_text(header+method+'\n'+action+'\n@end\n')
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -Wno-unused-function -framework Foundation \
    -I "$ROOT/LCOrbit/Tests/Stubs" -I "$ROOT/LCOrbit/Core" \
    "$ROOT/LCOrbit/Tests/guest_list_tests.m" \
    "$ROOT/LCOrbit/Core/LCOrbitGuestService.m" "$WORK/menu.m" \
    "$ROOT/LCOrbit/Core/LCOrbitMultitask.m" \
    "$ROOT/LCOrbit/Core/LCOrbitStorage.m" \
    -o "$WORK/guest-tests"
"$WORK/guest-tests"
