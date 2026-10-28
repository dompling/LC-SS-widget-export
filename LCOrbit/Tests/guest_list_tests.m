#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "LCOrbitGuestService.h"
#import "LCOrbitHost.h"
#import "LCOrbitStorage.h"

// Boundary doubles replace only the LC runtime and launcher. All scanning,
// plist parsing, list filtering and launch eligibility use production code.
static NSString *Group, *Home, *GuestID;
static NSDictionary *GuestInfo;
static BOOL SharedGuest;
static NSUserDefaults *Defaults;
static NSUInteger Failures, Assertions, Launches, Confirmations, Notices;
static NSUInteger MultitaskLaunches;
static NSURL *LaunchedURL;

@implementation LCOrbitHost
+ (NSString *)appGroupPath { return Group; }
+ (NSUserDefaults *)hostDefaults { return Defaults; }
+ (NSDictionary *)guestInfo { return GuestInfo; }
+ (NSString *)guestIdentifier { return GuestID ?: @"test.host"; }
+ (BOOL)isHostUI { return GuestInfo == nil; }
+ (BOOL)isSupportedGuest { return GuestInfo != nil; }
+ (UIWindowScene *)activeScene { return nil; }
@end
@implementation NSUserDefaults (OrbitTestHost)
+ (NSString *)lcAppUrlScheme { return @"livecontainer"; }
+ (NSBundle *)lcMainBundle { return nil; }
+ (BOOL)isSharedApp { return SharedGuest; }
+ (NSUserDefaults *)lcSharedDefaults { return Defaults; }
@end
@interface LCUtils : NSObject @end
@implementation LCUtils
+ (NSString *)liveProcessBundleIdentifier { return @"test.LiveProcess"; }
+ (void)launchMultitaskGuestApp:(NSString *)name completionHandler:(void (^)(NSNumber *,NSError *))completion {
    MultitaskLaunches++;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selectedContainer"];
    completion(@123,nil);
}
@end
@interface LCSharedUtils : NSObject @end
@implementation LCSharedUtils
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url { Launches++; LaunchedURL=url; return YES; }
+ (NSString *)getContainerUsingLCSchemeWithFolderName:(NSString *)folder { return nil; }
@end

// The runner compiles the exact production visibleApps method in isolation.
@interface FMManager : NSObject
@property(nonatomic,copy) NSArray<NSDictionary *> *apps;
- (NSArray<NSDictionary *> *)visibleApps;
- (void)switchFromRow:(id)sender;
@end
@interface FMManager (TestPresentationBoundary)
- (void)confirmTitle:(NSString *)title action:(void(^)(void))action;
- (void)showMessage:(NSString *)title details:(NSString *)detail;
- (void)launchApp:(NSDictionary *)app;
- (void)openBuiltinSideStore;
@end
@implementation FMManager (TestPresentationBoundary)
- (void)confirmTitle:(NSString *)title action:(void(^)(void))action { Confirmations++; action(); }
- (void)showMessage:(NSString *)title details:(NSString *)detail { Notices++; }
- (void)launchApp:(NSDictionary *)app { [LCOrbitGuestService launchGuest:app error:nil]; }
- (void)openBuiltinSideStore { Launches++; }
@end
NSString *OrbitTestGuestID(void) { return GuestID ?: @"test.host"; }
NSUserDefaults *OrbitTestDefaults(void) { return Defaults; }

static void Expect(BOOL ok, NSString *name) {
    Assertions++;
    if(!ok) { Failures++; fprintf(stderr,"FAIL: %s\n",name.UTF8String); }
}
static NSString *Root(BOOL shared) {
    return [shared?Group:Home stringByAppendingPathComponent:
        shared?@"LiveContainer/Applications":@"Documents/Applications"];
}
static void App(BOOL shared, NSString *name, NSDictionary *changes, NSDictionary *infoChanges) {
    NSString *folder=[Root(shared) stringByAppendingPathComponent:name];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSCAssert([fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil],@"fixture mkdir");
    NSMutableDictionary *lc=[@{@"LCPatchRevision":@7,@"LCDataUUID":name,
        @"LCContainers":@[@{@"folderName":name}]} mutableCopy];
    for(NSString *key in changes) {
        if(changes[key]==NSNull.null) [lc removeObjectForKey:key]; else lc[key]=changes[key];
    }
    NSMutableDictionary *info=[@{@"CFBundleExecutable":@"AppBinary",@"CFBundleName":name,
        @"CFBundleIdentifier":[@"test." stringByAppendingString:name]} mutableCopy];
    [info addEntriesFromDictionary:infoChanges?:@{}];
    NSCAssert([lc writeToFile:[folder stringByAppendingPathComponent:@"LCAppInfo.plist"] atomically:YES],@"fixture LC plist");
    NSCAssert([info writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES],@"fixture Info plist");
    NSCAssert([[@"fixture" dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:[folder stringByAppendingPathComponent:@"AppBinary"] atomically:YES],@"fixture executable");
}
static NSDictionary *Find(NSArray *apps, BOOL shared, NSString *name) {
    NSString *folder=[Root(shared) stringByAppendingPathComponent:name];
    for(NSDictionary *app in apps) if([app[@"folder"] isEqualToString:folder]) return app;
    return nil;
}
static void Clear(void) {
    [NSFileManager.defaultManager removeItemAtPath:Root(NO) error:nil];
    [NSFileManager.defaultManager removeItemAtPath:Root(YES) error:nil];
    GuestID=nil; GuestInfo=nil; SharedGuest=NO; LaunchedURL=nil; Launches=0; Confirmations=0; Notices=0;
}
static void TestDiscoveryAndSafety(void) {
    Clear();
    App(NO,@"Private.app",@{},nil); App(YES,@"Shared.app",@{},nil);
    App(YES,@"Manual.app",@{@"dontSign":@YES},nil);
    App(YES,@"JIT.app",@{@"isJITNeeded":@YES},nil);
    App(YES,@"Patch.app",@{@"LCPatchRevision":@6},nil);
    App(YES,@"NoLoader.app",@{@"dontLoadTweakLoader":@YES},nil);
    App(YES,@"Hidden.app",@{@"isHidden":@YES},nil);
    App(NO,@"Locked.app",@{@"isLocked":@YES},nil);
    NSArray *list=[LCOrbitGuestService installedApps];
    Expect(Find(list,NO,@"Private.app")!=nil,@"private guest remains visible");
    Expect(Find(list,YES,@"Shared.app")!=nil,@"shared guest is discovered");
    Expect(Find(list,YES,@"Manual.app")!=nil,@"dontSign must not silently hide an installed shared guest");
    Expect(Find(list,YES,@"JIT.app")!=nil,@"JIT guest remains visible for status display");
    Expect(Find(list,YES,@"Patch.app")!=nil,@"outdated patch remains visible for status display");
    Expect(Find(list,YES,@"NoLoader.app")!=nil,@"disabled loader must not erase app from inventory");
    Expect(Find(list,YES,@"Hidden.app")!=nil,@"explicit all-app inventory includes hidden guest");
    Expect(Find(list,NO,@"Locked.app")!=nil,@"explicit all-app inventory includes locked guest");
    Expect([Find(list,YES,@"Hidden.app")[@"hidden"] boolValue],@"hidden state is reported without modifying it");
    Expect([Find(list,NO,@"Locked.app")[@"locked"] boolValue],@"locked state is reported without modifying it");
    Expect([LCOrbitGuestService isEligibleGuestPath:@"Shared.app" uuid:@"Shared.app"],@"ordinary shared guest remains launchable");
    for(NSString *name in @[@"Manual.app",@"JIT.app",@"Patch.app",@"NoLoader.app",@"Hidden.app",@"Locked.app"]) {
        NSError *error=nil;
        Expect(![LCOrbitGuestService launchGuestPath:name uuid:name error:&error],
               [@"launch protection retained: " stringByAppendingString:name]);
        Expect(error!=nil,[@"blocked launch supplies error: " stringByAppendingString:name]);
    }
    Expect(Launches==0,@"blocked guests never reach host launcher");
}
static void TestContainerSelection(void) {
    Clear();
    App(YES,@"Single.app",@{@"LCDataUUID":NSNull.null,
        @"LCContainers":@[@{@"folderName":@"one-container"}]},nil);
    App(YES,@"Ambiguous.app",@{@"LCDataUUID":NSNull.null,
        @"LCContainers":@[@{@"folderName":@"first"},@{@"folderName":@"second"}]},nil);
    NSArray *list=[LCOrbitGuestService installedApps];
    NSDictionary *single=Find(list,YES,@"Single.app");
    Expect(single!=nil,@"single-container shared guest is not dropped without LCDataUUID");
    Expect([single[@"uuid"] isEqualToString:@"one-container"],@"unambiguous LCContainers supplies container");
    Expect(Find(list,YES,@"Ambiguous.app")!=nil,@"ambiguous container guest is visible, not erased");
    Expect(![LCOrbitGuestService isEligibleGuestPath:@"Ambiguous.app" uuid:@"first"],@"never silently choose first of several containers");
    NSError *error=nil;
    Expect([LCOrbitGuestService launchGuestPath:@"Single.app" uuid:@"one-container" error:&error],@"single-container shared guest uses validated native launch");
    NSURLComponents *parts=LaunchedURL?[NSURLComponents componentsWithURL:LaunchedURL resolvingAgainstBaseURL:NO]:nil;
    NSMutableDictionary *query=[NSMutableDictionary dictionary];
    for(NSURLQueryItem *item in parts.queryItems) query[item.name]=item.value?:@"";
    Expect([query[@"bundle-name"] isEqualToString:@"Single.app"],@"launch preserves selected app name");
    Expect([query[@"container-folder-name"] isEqualToString:@"one-container"],@"launch supplies correct selected container");
}
static void TestDuplicateRoots(void) {
    Clear();
    App(NO,@"Duplicate.app",@{@"dontSign":@YES,@"LCDataUUID":@"private-id"},nil);
    App(YES,@"Duplicate.app",@{@"LCDataUUID":@"shared-id"},nil);
    NSArray *list=[LCOrbitGuestService installedApps];
    Expect(Find(list,NO,@"Duplicate.app")!=nil,@"private duplicate is represented separately");
    Expect(Find(list,YES,@"Duplicate.app")!=nil,@"rejected private duplicate cannot consume shared listing");
    Expect(![LCOrbitGuestService isEligibleGuestPath:@"Duplicate.app" uuid:@"shared-id"],@"shadowed shared guest cannot accidentally launch private namesake");
    [NSFileManager.defaultManager removeItemAtPath:[Root(NO) stringByAppendingPathComponent:@"Duplicate.app"] error:nil];
    Expect([LCOrbitGuestService isEligibleGuestPath:@"Duplicate.app" uuid:@"shared-id"],@"shared guest becomes launchable once actual private shadow is removed");
    App(NO,@"Duplicate.app",@{@"LCDataUUID":@"shared-id"},nil);
    Expect(![LCOrbitGuestService isEligibleGuestPath:@"Duplicate.app" uuid:@"shared-id"],@"legacy path+uuid API rejects indistinguishable copies");
}
static void TestCurrentAndOriginalIdentity(void) {
    Clear();
    App(YES,@"Current.app",@{@"doUseLCBundleId":@YES,@"LCOrignalBundleIdentifier":@"test.original"},
        @{@"CFBundleIdentifier":@"com.kdt.livecontainer.team"});
    NSDictionary *current=Find([LCOrbitGuestService installedApps],YES,@"Current.app");
    Expect([current[@"bundle"] isEqualToString:@"test.original"],@"LC bundle-id substitution preserves original guest identity");
    GuestID=@"test.original";GuestInfo=@{@"LCDataUUID":@"Current.app"};SharedGuest=YES;
    current=Find([LCOrbitGuestService installedApps],YES,@"Current.app");
    Expect([LCOrbitGuestService isCurrentGuest:current],@"shared current app identity is recognized");
    NSMutableDictionary *privateCopy=[current mutableCopy];privateCopy[@"shared"]=@NO;
    Expect(![LCOrbitGuestService isCurrentGuest:privateCopy],@"same bundle ID in private scope is not the current shared app");
    FMManager *menu=[FMManager new];
    menu.apps=@[@{@"path":@"Current.app",@"bundle":@"test.original",@"title":@"Current"},
                @{@"path":@"Other.app",@"bundle":@"test.other",@"title":@"Other"}];
    Expect(menu.visibleApps.count==2,@"real menu keeps currently running app rather than hiding it");
}
static void Tap(FMManager *menu, NSDictionary *app) {
    NSObject *sender=[NSObject new];
    objc_setAssociatedObject(sender,@selector(switchFromRow:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [menu switchFromRow:sender];
}
static void TestMenuActions(void) {
    Clear();
    App(YES,@"Current.app",@{},nil);App(YES,@"Next.app",@{},nil);
    App(YES,@"JIT.app",@{@"isJITNeeded":@YES},nil);
    App(NO,@"Locked.app",@{@"isLocked":@YES},nil);
    App(YES,@"Hidden.app",@{@"isHidden":@YES},nil);
    GuestID=@"test.Current.app";GuestInfo=@{@"LCDataUUID":@"Current.app"};SharedGuest=YES;
    FMManager *menu=[FMManager new];menu.apps=[LCOrbitGuestService installedApps];
    Tap(menu,Find(menu.apps,YES,@"Current.app"));
    Expect(Launches==0 && Confirmations==0,@"current app tap does not restart itself or ask to switch");
    Tap(menu,Find(menu.apps,YES,@"JIT.app"));
    Expect(Launches==0 && Confirmations==0 && Notices==1,@"visible JIT entry reports state without launch confirmation");
    Tap(menu,Find(menu.apps,NO,@"Locked.app"));
    Tap(menu,Find(menu.apps,YES,@"Hidden.app"));
    Expect(Launches==0 && Confirmations==0 && Notices==3,@"visible locked and hidden entries do not bypass LC authentication");
    Tap(menu,Find(menu.apps,YES,@"Next.app"));
    Expect(Launches==1 && Confirmations==1,@"ready shared app tap follows normal confirmation and native launch");
    App(NO,@"Next.app",@{},nil);
    menu.apps=[LCOrbitGuestService installedApps];
    Tap(menu,Find(menu.apps,YES,@"Next.app"));
    Expect(Launches==1,@"shared namesake tap cannot launch private copy");
    Tap(menu,Find(menu.apps,NO,@"Next.app"));
    Expect(Launches==2,@"explicit private identity still launches when path+uuid is duplicated");
    NSArray *roots=@[@{@"identity":@"private/Same.app",@"path":@"Same.app",@"title":@"Same"},
                     @{@"identity":@"shared/Same.app",@"path":@"Same.app",@"title":@"Same"}];
    menu.apps=roots;[Defaults setObject:@[@"shared/Same.app",@"private/Same.app"] forKey:@"test.menuOrder"];
    Expect([menu.visibleApps[0][@"identity"] isEqualToString:@"shared/Same.app"],@"scope-aware sort distinguishes same folder names");
    [Defaults setObject:@[@"Second.app",@"First.app"] forKey:@"test.menuOrder"];
    menu.apps=@[@{@"identity":@"private/First.app",@"path":@"First.app",@"title":@"First"},
                @{@"identity":@"shared/Second.app",@"path":@"Second.app",@"title":@"Second"}];
    Expect([menu.visibleApps[0][@"path"] isEqualToString:@"Second.app"],@"legacy sort preferences remain readable");
    [Defaults removeObjectForKey:@"test.menuOrder"];
}
static void TestMalformedAndReadOnly(void) {
    Clear();
    App(YES,@"Malformed.app",@{@"LCDataUUID":@42},nil);
    App(YES,@"Traversal.app",@{@"LCDataUUID":@"../outside"},nil);
    App(YES,@"Good.app",@{},nil);
    NSString *plist=[[Root(YES) stringByAppendingPathComponent:@"Good.app"] stringByAppendingPathComponent:@"LCAppInfo.plist"];
    NSData *before=[NSData dataWithContentsOfFile:plist];
    @try {
        NSArray *list=[LCOrbitGuestService installedApps];
        Expect(Find(list,YES,@"Good.app")!=nil,@"one malformed plist cannot erase other shared guests");
        Expect(![LCOrbitGuestService isEligibleGuestPath:@"Traversal.app" uuid:@"../outside"],@"container path traversal is rejected");
    } @catch(NSException *ex) { Expect(NO,[@"malformed metadata must not crash scan: " stringByAppendingString:ex.name]); }
    Expect([[NSData dataWithContentsOfFile:plist] isEqualToData:before],@"inventory is read-only");
    NSError *error=nil;
    Expect(![LCOrbitGuestService launchGuestPath:@"../Good.app" uuid:@"Good.app" error:&error],@"application path traversal cannot reach launcher");
    Expect(Launches==0,@"invalid paths cannot execute a launch");
    NSDictionary *snapshot=Find([LCOrbitGuestService installedApps],YES,@"Good.app");
    Expect([LCOrbitGuestService launchGuest:snapshot error:&error],@"identity-aware selection launches the intended shared app");
    App(YES,@"Good.app",@{@"isLocked":@YES},nil);
    NSUInteger beforeLaunches=Launches;
    Expect(![LCOrbitGuestService launchGuest:snapshot error:&error],@"selection is revalidated after app becomes locked");
    Expect(Launches==beforeLaunches,@"stale unlocked snapshot cannot bypass the lock");
}
static void TestHostMultitaskRouting(void) {
    Clear();
    App(NO,@"Fullscreen.app",@{},nil);
    App(NO,@"Classic.app",@{@"classicMode":@YES,@"LCClassicModeCache":@{@"defaultClassicMode":@1}},nil);
    App(NO,@"UncachedClassic.app",@{@"classicMode":@YES},nil);
    App(NO,@"StaleClassic.app",@{@"classicMode":@YES,@"LCClassicModeCache":@{@"defaultClassicMode":@0,@"systemMajorVersion":@1}},nil);
    [[LCOrbitStorage preferences] setBool:YES forKey:@"LCFloatingMenu.fullscreenMultitask"];
    NSError *error=nil;
    NSDictionary *target=Find([LCOrbitGuestService installedApps],NO,@"Fullscreen.app");
    Expect([LCOrbitGuestService launchGuest:target error:&error],@"enabled host menu can start fullscreen multitask");
    Expect(MultitaskLaunches==1 && Launches==0,@"host selection uses multitask instead of killing host");
    target=Find([LCOrbitGuestService installedApps],NO,@"Classic.app");
    Expect(![LCOrbitGuestService launchGuest:target error:&error],@"classic-only app cannot enter multitask renderer");
    Expect(MultitaskLaunches==1 && Launches==0,@"classic-only rejection never silently restarts host");
    for(NSString *name in @[@"UncachedClassic.app",@"StaleClassic.app"]) {
        target=Find([LCOrbitGuestService installedApps],NO,name);
        Expect(![LCOrbitGuestService launchGuest:target error:&error],@"unknown or stale compatibility mode must use LC original launch");
    }
    target=Find([LCOrbitGuestService installedApps],NO,@"Fullscreen.app");
    App(NO,@"Fullscreen.app",@{@"isLocked":@YES},nil);
    Expect(![LCOrbitGuestService launchGuest:target error:&error] && MultitaskLaunches==1,@"multitask route rechecks stale app lock");
    [[LCOrbitStorage preferences] removeObjectForKey:@"LCFloatingMenu.fullscreenMultitask"];
}
static void TestHostDoesNotRequireGuestPlugin(void) {
    Clear();
    NSUInteger before=MultitaskLaunches;
    App(NO,@"NoLoader.app",@{@"dontLoadTweakLoader":@YES},nil);
    App(YES,@"NoInjection.app",@{@"dontInjectTweakLoader":@YES},nil);
    App(NO,@"CannotInject.app",@{@"LCTweakLoaderCantInject":@YES},nil);
    [[LCOrbitStorage preferences] setBool:YES forKey:@"LCFloatingMenu.fullscreenMultitask"];
    NSArray *list=[LCOrbitGuestService installedApps];
    for(NSDictionary *entry in @[@{@"name":@"NoLoader.app",@"shared":@NO},
                                  @{@"name":@"NoInjection.app",@"shared":@YES},
                                  @{@"name":@"CannotInject.app",@"shared":@NO}]) {
        NSDictionary *target=Find(list,[entry[@"shared"] boolValue],entry[@"name"]);
        NSError *error=nil;
        Expect([target[@"launchable"] boolValue],@"host multitask inventory does not require Guest plugin injection");
        Expect([LCOrbitGuestService launchGuest:target error:&error],@"host multitask starts Guest without enabling its TweakLoader");
    }
    Expect(MultitaskLaunches==before+3 && Launches==0,@"loader-independent Guest launches stay in host multitask path");
    for(NSDictionary *flags in @[@{@"dontLoadTweakLoader":@YES,@"isJITNeeded":@YES},
                                @{@"dontLoadTweakLoader":@YES,@"dontSign":@YES},
                                @{@"dontLoadTweakLoader":@YES,@"isLocked":@YES},
                                @{@"dontLoadTweakLoader":@YES,@"isHidden":@YES},
                                @{@"dontLoadTweakLoader":@YES,@"LCPatchRevision":@6},
                                @{@"dontLoadTweakLoader":@YES,@"LCDataUUID":@"../outside"}]) {
        App(NO,@"Protected.app",flags,nil);
        NSDictionary *target=Find([LCOrbitGuestService installedApps],NO,@"Protected.app");
        Expect(![LCOrbitGuestService launchGuest:target error:nil],@"host-only plugin policy retains JIT, signing, lock, hidden, patch and container checks");
    }
    Expect(MultitaskLaunches==before+3,@"relaxing Guest plugin requirements never bypasses other launch protections");
    GuestInfo=@{@"LCDataUUID":@"classic"};
    Expect(![LCOrbitGuestService isEligibleGuestPath:@"NoLoader.app" uuid:@"NoLoader.app"],@"host preference never relaxes classic Guest loader eligibility");
    GuestInfo=nil;
    [[LCOrbitStorage preferences] removeObjectForKey:@"LCFloatingMenu.fullscreenMultitask"];
    Expect(![LCOrbitGuestService isEligibleGuestPath:@"NoLoader.app" uuid:@"NoLoader.app"],@"disabled host multitasking preserves classic loader restriction");
}
int main(void) {
    @autoreleasepool {
        NSString *sandbox=[NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"orbit-guest-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        Home=[sandbox stringByAppendingPathComponent:@"host"];
        Group=[sandbox stringByAppendingPathComponent:@"group"];
        NSString *suite=[@"orbit.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        Defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        setenv("LC_HOME_PATH",Home.UTF8String,1);
        @try {
            TestDiscoveryAndSafety(); TestContainerSelection(); TestDuplicateRoots();
            TestCurrentAndOriginalIdentity(); TestMenuActions(); TestMalformedAndReadOnly();
            TestHostMultitaskRouting();
            TestHostDoesNotRequireGuestPlugin();
        } @catch(NSException *ex) { Expect(NO,[@"unexpected test exception: " stringByAppendingString:ex.description]); }
        @finally { [NSFileManager.defaultManager removeItemAtPath:sandbox error:nil]; [Defaults removePersistentDomainForName:suite]; }
        fprintf(stdout,"Guest behavior tests: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
