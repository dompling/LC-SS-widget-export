#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "LCOrbitGuestService.h"
#import "LCOrbitHost.h"

static NSString *Home, *Group, *CurrentID;
static NSUserDefaults *Defaults;
static NSUInteger Failures, Assertions, Notices;
@implementation LCOrbitHost
+ (NSString *)appGroupPath { return Group; }
+ (NSUserDefaults *)hostDefaults { return Defaults; }
+ (NSDictionary *)guestInfo { return nil; }
+ (NSString *)guestIdentifier { return CurrentID ?: @"test.host"; }
+ (BOOL)isHostUI { return YES; }
+ (BOOL)isSupportedGuest { return NO; }
+ (UIWindowScene *)activeScene { return nil; }
@end
@implementation NSUserDefaults (FavoriteTestBoundary)
+ (NSBundle *)lcMainBundle { return nil; }
+ (NSString *)lcAppUrlScheme { return @"livecontainer"; }
@end
// Only presentation is replaced. The runner compiles the actual production
// visibleApps, favorites and pinApp implementations, plus the real scanner.
@interface FMManager : NSObject
@property(nonatomic,copy) NSArray<NSDictionary *> *apps;
- (NSArray<NSDictionary *> *)visibleApps;
- (NSArray<NSString *> *)favorites;
- (void)pinApp:(id)sender;
@end
NSUserDefaults *FavoriteTestDefaults(void) { return Defaults; }
NSString *FavoriteTestGuestID(void) { return CurrentID ?: @"test.host"; }
void FavoriteTestNotice(void) { Notices++; }
static void Check(BOOL ok, NSString *label) {
    Assertions++;
    if(!ok) { Failures++; fprintf(stderr,"FAIL: %s\n",label.UTF8String); }
}
static NSString *Root(BOOL shared) {
    return [(shared?Group:Home) stringByAppendingPathComponent:
        shared?@"LiveContainer/Applications":@"Documents/Applications"];
}
static void Install(BOOL shared,NSString *name,NSDictionary *flags) {
    NSString *folder=[Root(shared) stringByAppendingPathComponent:name];
    NSCAssert([NSFileManager.defaultManager createDirectoryAtPath:folder
        withIntermediateDirectories:YES attributes:nil error:nil],@"fixture directory");
    NSMutableDictionary *info=[@{@"LCPatchRevision":@7,@"LCDataUUID":name,
        @"LCContainers":@[@{@"folderName":name}]} mutableCopy];
    [info addEntriesFromDictionary:flags];
    NSCAssert([info writeToFile:[folder stringByAppendingPathComponent:@"LCAppInfo.plist"] atomically:YES],@"fixture metadata");
    NSDictionary *bundle=@{@"CFBundleIdentifier":[@"test." stringByAppendingString:name],
        @"CFBundleName":name,@"CFBundleExecutable":@"Binary"};
    NSCAssert([bundle writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES],@"fixture bundle");
    NSCAssert([[@"test" dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:[folder stringByAppendingPathComponent:@"Binary"] atomically:YES],@"fixture binary");
}
static NSDictionary *Find(NSArray *list,BOOL shared,NSString *name) {
    NSString *folder=[Root(shared) stringByAppendingPathComponent:name];
    for(NSDictionary *item in list) if([item[@"folder"] isEqualToString:folder]) return item;
    return nil;
}
static void Pin(FMManager *manager,NSDictionary *app) {
    if(!app) return;
    NSObject *button=[NSObject new];
    objc_setAssociatedObject(button,@selector(pinApp:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [manager pinApp:button];
}
int main(void) {
    @autoreleasepool {
        NSString *temp=[NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"orbit-favorites-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        Home=[temp stringByAppendingPathComponent:@"host"];
        Group=[temp stringByAppendingPathComponent:@"group"];
        NSString *suite=[@"orbit.favorites.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        Defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        setenv("LC_HOME_PATH",Home.UTF8String,1);
        @try {
            Install(NO,@"PrivateJIT.app",@{@"isJITNeeded":@YES});
            Install(YES,@"SharedJIT.app",@{@"isJITNeeded":@YES});
            Install(NO,@"Same.app",@{});Install(YES,@"Same.app",@{});
            Install(NO,@"Hidden.app",@{@"isHidden":@YES,@"isJITNeeded":@YES});
            Install(YES,@"Locked.app",@{@"isLocked":@YES,@"isJITNeeded":@YES});
            FMManager *menu=[FMManager new];menu.apps=[LCOrbitGuestService installedApps];
            NSDictionary *privateJIT=Find(menu.visibleApps,NO,@"PrivateJIT.app");
            NSDictionary *sharedJIT=Find(menu.visibleApps,YES,@"SharedJIT.app");
            Check(privateJIT!=nil,@"private JIT app appears in management inventory");
            Check(sharedJIT!=nil,@"shared JIT app appears in management inventory");
            Check(Find(menu.visibleApps,NO,@"Hidden.app")!=nil,@"hidden JIT app remains in all-app inventory");
            Check(Find(menu.visibleApps,YES,@"Locked.app")!=nil,@"locked JIT app remains in all-app inventory");
            Check(![LCOrbitGuestService isEligibleGuestPath:@"SharedJIT.app" uuid:@"SharedJIT.app"],@"listing JIT app does not bypass launch checks");
            Pin(menu,privateJIT);Pin(menu,sharedJIT);
            Check(menu.favorites.count==2,@"both private and shared JIT apps can be favorited");
            Check([menu.favorites containsObject:@"private/PrivateJIT.app"],@"private JIT favorite has stable scoped identity");
            Check([menu.favorites containsObject:@"shared/SharedJIT.app"],@"shared JIT favorite has stable scoped identity");
            FMManager *reopened=[FMManager new];reopened.apps=[LCOrbitGuestService installedApps];
            Check(reopened.favorites.count==2,@"JIT favorites persist across menu instances");
            Pin(reopened,sharedJIT);
            Check(reopened.favorites.count==1,@"unfavoriting shared JIT leaves private favorite unchanged");
            Pin(reopened,privateJIT);
            Check(reopened.favorites.count==0,@"JIT favorites can be removed normally");
            NSDictionary *privateSame=Find(menu.apps,NO,@"Same.app");
            NSDictionary *sharedSame=Find(menu.apps,YES,@"Same.app");
            Check(privateSame!=nil && sharedSame!=nil,@"same filename in two scopes remains discoverable");
            Pin(menu,privateSame);Pin(menu,sharedSame);
            Check(menu.favorites.count==2,@"same-name private and shared apps can be favorited independently");
            Pin(menu,sharedSame);
            Check([menu.favorites containsObject:@"private/Same.app"] && ![menu.favorites containsObject:@"shared/Same.app"],@"removing shared favorite does not remove private namesake");
            [Defaults setObject:@[@"PrivateJIT.app"] forKey:@"test.favoritePaths"];
            Pin(menu,privateJIT);
            Check(menu.favorites.count==0,@"legacy JIT favorite can be removed after upgrade");
            [Defaults setObject:@[@"a",@"b",@"c",@"d"] forKey:@"test.favoritePaths"];
            Pin(menu,sharedJIT);
            Check(menu.favorites.count==4 && Notices==1,@"existing four-favorite limit stays enforced");
            CurrentID=@"test.PrivateJIT.app";
            Check(Find(menu.visibleApps,NO,@"PrivateJIT.app")!=nil,@"current JIT app stays in management list");
            [Defaults setObject:@[] forKey:@"test.favoritePaths"];
            Pin(menu,Find(menu.visibleApps,NO,@"Hidden.app"));
            Pin(menu,Find(menu.visibleApps,YES,@"Locked.app"));
            Pin(menu,privateJIT);
            Check([menu.favorites containsObject:@"private/Hidden.app"],@"hidden app can be favorited without changing its hidden flag");
            Check([menu.favorites containsObject:@"shared/Locked.app"],@"locked app can be favorited without unlocking it");
            Check([menu.favorites containsObject:@"private/PrivateJIT.app"],@"currently running app can be favorited");
            Check(menu.favorites.count==3,@"all three states are saved independently");
            Check(![LCOrbitGuestService isEligibleGuestPath:@"Locked.app" uuid:@"Locked.app"],@"favoriting a locked app never grants launch permission");
        } @catch(NSException *error) {
            Check(NO,[@"unexpected exception: " stringByAppendingString:error.name]);
        } @finally {
            [NSFileManager.defaultManager removeItemAtPath:temp error:nil];
            [Defaults removePersistentDomainForName:suite];
        }
        printf("JIT/favorites behavior: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
