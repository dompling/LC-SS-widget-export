#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_ROOT="${ORBIT_SOURCE_ROOT:-$ROOT}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-favorite-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
# Compile exact production methods against a tiny Foundation presentation
# boundary. File scanning, filtering, preference writes and actions are real.
python3 - "$SOURCE_ROOT" "$WORK/menu.m" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCFloatingMenu/LCFloatingMenu.m').read_text()
def method(start, end):
    a=source.index(start)
    b=source.index(end,a)
    return source[a:b]
methods=[method('- (NSArray<NSDictionary*> *)visibleApps {','\n- (void)rememberCurrentApp'),
         method('- (NSArray<NSString*> *)favorites {','\n- (void)appPage:'),
         method('- (void)pinApp:(UIControl *)button {','\n- (void)promoteApp:')]
helper=''
needle='static NSString *FMAppKey('
if needle in source:
    a=source.index(needle)
    helper=source[a:source.index('\n',a)]+'\n'
header='''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
@class UIControl;
#import "LCOrbitGuestService.h"
extern NSUserDefaults *FavoriteTestDefaults(void);
extern NSString *FavoriteTestGuestID(void);
extern void FavoriteTestNotice(void);
static NSUserDefaults *HostDefaults(void) { return FavoriteTestDefaults(); }
static NSString *GuestID(void) { return FavoriteTestGuestID(); }
static NSString *Pref(NSString *key) { return [@"test." stringByAppendingString:key]; }
static void SetPref(NSString *key,id value) { [HostDefaults() setObject:value forKey:Pref(key)]; }
@interface FMManager : NSObject
@property(nonatomic,copy) NSArray<NSDictionary *> *apps;
- (NSArray<NSDictionary *> *)visibleApps;
- (NSArray<NSString *> *)favorites;
- (void)pinApp:(UIControl *)sender;
- (void)draw;
- (void)refreshUI;
- (void)showMessage:(NSString *)title details:(NSString *)details;
@end
'''
boundary='''\n- (void)draw {}
- (void)refreshUI {}
- (void)showMessage:(NSString *)title details:(NSString *)details { FavoriteTestNotice(); }
@end
'''
Path(sys.argv[2]).write_text(header+helper+'@implementation FMManager\n'+'\n'.join(methods)+boundary)
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -Wno-unused-parameter -Wno-unused-function -framework Foundation \
    -I "$ROOT/LCOrbit/Tests/Stubs" -I "$SOURCE_ROOT/LCOrbit/Core" \
    "$ROOT/LCOrbit/Tests/jit_favorites_tests.m" \
    "$SOURCE_ROOT/LCOrbit/Core/LCOrbitGuestService.m" "$WORK/menu.m" \
    "$SOURCE_ROOT/LCOrbit/Core/LCOrbitMultitask.m" \
    "$SOURCE_ROOT/LCOrbit/Core/LCOrbitStorage.m" \
    -o "$WORK/favorite-tests"
"$WORK/favorite-tests"
