#import <Foundation/Foundation.h>
#import "LCOrbitMultitask.h"
#import "LCOrbitHost.h"
#import "LCOrbitStorage.h"

static NSUserDefaults *Defaults;
static BOOL Host=YES, Hooks=YES;
static NSString *Extension=@"test.LiveProcess";
static NSUInteger Assertions, Failures, Launches, Notices, ConfigRefreshes;
static NSString *Selected, *Container;
static NSString *ContainerOwner;
static NSArray *Inventory;
static NSUInteger AutomaticRefreshes;
static BOOL NativeSupported;
static NSMutableDictionary *NativeTask;
static NSUInteger NativeLaunches, NativeActivations, NativeCloses, NativeHomes;
@interface MultitaskWindowManager : NSObject @end
@implementation MultitaskWindowManager
+ (BOOL)orbitSupportsNativeTaskWindows { return NativeSupported; }
+ (NSArray *)orbitRunningTasks { return NativeTask?@[NativeTask]:@[]; }
+ (BOOL)orbitShowHome { NativeHomes++;return YES; }
+ (NSDictionary *)orbitTaskForBundleId:(NSString *)bundle dataUUID:(NSString *)container {
    return [NativeTask[@"bundle"] isEqual:bundle] && [NativeTask[@"container"] isEqual:container]?NativeTask:nil;
}
+ (void)orbitOpenAppWindowWithDisplayName:(NSString *)name bundleId:(NSString *)bundle dataUUID:(NSString *)container completionHandler:(void (^)(NSNumber *,NSError *))completion {
    NativeLaunches++;
    NativeTask=[@{@"bundle":bundle,@"container":container,@"folder":[@"/fixture/" stringByAppendingString:bundle],
        @"title":name,@"running":@YES,@"active":@YES,@"token":NSUUID.UUID.UUIDString} mutableCopy];
    completion(@789,nil);
}
+ (BOOL)orbitActivateTaskWithBundleId:(NSString *)bundle dataUUID:(NSString *)container {
    if(![self orbitTaskForBundleId:bundle dataUUID:container]) return NO;
    NativeActivations++;NativeTask[@"active"]=@YES;return YES;
}
+ (BOOL)orbitCloseTaskWithBundleId:(NSString *)bundle dataUUID:(NSString *)container {
    if(![self orbitTaskForBundleId:bundle dataUUID:container]) return NO;
    NativeCloses++;NativeTask=nil;return YES;
}
@end
@interface LCOrbitAutomaticPiP : NSObject @end
@implementation LCOrbitAutomaticPiP
+ (void)refresh { AutomaticRefreshes++; }
@end
static void (^Pending)(NSNumber *,NSError *);
@interface PiPManager : NSObject
@property(nonatomic) BOOL active;
@property(nonatomic) NSUInteger stops;
+ (instancetype)shared;
- (BOOL)isPiP;
- (void)stopPiP;
@end
@implementation PiPManager
+ (instancetype)shared { static PiPManager *manager;static dispatch_once_t once;dispatch_once(&once,^{manager=[self new];});return manager; }
- (BOOL)isPiP { return self.active; }
- (void)stopPiP { self.stops++;self.active=NO; }
@end

@implementation LCOrbitHost
+ (NSUserDefaults *)hostDefaults { return Defaults; }
+ (BOOL)isHostUI { return Host; }
+ (NSString *)appGroupPath { return nil; }
+ (NSDictionary *)guestInfo { return nil; }
+ (NSString *)guestIdentifier { return @"test.host"; }
+ (UIWindowScene *)activeScene { return nil; }
+ (BOOL)isSupportedGuest { return NO; }
@end
@interface LCSharedUtils : NSObject @end
@interface ResolvedBundle : NSObject
@property(nonatomic,copy) NSString *bundlePath;
@end
@implementation ResolvedBundle @end
@implementation LCSharedUtils
+ (NSString *)getContainerUsingLCSchemeWithFolderName:(NSString *)folder { return ContainerOwner; }
+ (id)findBundleWithBundleId:(NSString *)bundle isSharedAppOut:(bool *)shared {
    ResolvedBundle *resolved=[ResolvedBundle new];resolved.bundlePath=[@"/fixture/" stringByAppendingString:bundle];return resolved;
}
@end
@interface LCOrbitGuestService : NSObject @end
@implementation LCOrbitGuestService
+ (NSArray *)installedApps { return Inventory; }
@end
@implementation NSUserDefaults (TestHost)
+ (NSUserDefaults *)lcSharedDefaults { return Defaults; }
@end
@interface LCUtils : NSObject @end
@implementation LCUtils
+ (NSString *)liveProcessBundleIdentifier { return Extension; }
+ (void)launchMultitaskGuestApp:(NSString *)name completionHandler:(void (^)(NSNumber *,NSError *))completion {
    Launches++;
    Selected=[NSUserDefaults.standardUserDefaults stringForKey:@"selected"];
    Container=[NSUserDefaults.standardUserDefaults stringForKey:@"selectedContainer"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selectedContainer"];
    Pending=[completion copy];
}
@end
@interface OrbitWindow : NSObject
@property BOOL hidden, running, defersClose;
@end
@implementation OrbitWindow
- (id)appSceneVC { return self; }
- (BOOL)isAppRunning { return self.running; }
- (void)orbit_setVisible:(BOOL)visible { self.hidden=!visible; }
- (void)orbit_activate {
    self.hidden=NO;
    [(id)NSClassFromString(@"LCOrbitMultitask") didActivateWindow:self];
}
- (void)closeWindow {
    if(self.defersClose)return;
    self.running=NO;
    [(id)NSClassFromString(@"LCOrbitMultitask") forgetWindow:self];
}
@end
// The iOS presentation boundary is the only part unavailable to Foundation tests.
@implementation NSObject (OrbitPresentationTest)
+ (BOOL)installHooksWithError:(NSError **)error { return Hooks; }
+ (void)refreshPresentation { }
@end
@interface LCOrbitMultitask (TaskCloseContract)
+ (BOOL)isRunningGuest:(NSDictionary *)guest;
+ (BOOL)isManagingWindows;
+ (BOOL)closeGuest:(NSDictionary *)guest error:(NSError **)error;
+ (BOOL)usesAdaptiveSwitcher;
+ (BOOL)setUseAdaptiveSwitcher:(BOOL)enabled error:(NSError **)error;
+ (BOOL)usesNativeTaskWindows;
+ (NSInteger)taskSwitcherPresentation;
+ (BOOL)setTaskSwitcherPresentation:(NSInteger)presentation error:(NSError **)error;
+ (NSArray *)runningTasks;
+ (BOOL)activateTask:(NSDictionary *)task error:(NSError **)error;
+ (BOOL)closeTask:(NSDictionary *)task error:(NSError **)error;
+ (NSArray *)runningTasksForApps:(NSArray *)apps;
@end
static void Expect(BOOL ok, NSString *message) {
    Assertions++; if(!ok) { Failures++; fprintf(stderr,"FAIL: %s\n",message.UTF8String); }
}
static NSDictionary *Guest(NSString *name,NSString *uuid) {
    return @{ @"path":name,@"uuid":uuid,@"identity":[@"private/" stringByAppendingString:name],
        @"folder":[@"/fixture/" stringByAppendingString:name],@"title":name,@"launchable":@YES };
}
int main(void) {
    @autoreleasepool {
        NSString *suite=[@"orbit.multitask.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        Defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        id bridge=NSClassFromString(@"LCOrbitMultitask");
        Expect(bridge!=nil,@"plugin provides host multitask adapter");
        if(!bridge) return 1;
        id refreshObserver=[NSNotificationCenter.defaultCenter addObserverForName:LCOrbitMultitaskConfigurationChangedNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) { ConfigRefreshes++; }];
        NSDictionary *a=Guest(@"A.app",@"a"), *b=Guest(@"B.app",@"b");
        Inventory=@[a,b];
        NSError *error=nil;
        BOOL automatic=[bridge respondsToSelector:@selector(setAutomaticPiPEnabled:forGuest:error:)];
        Expect(automatic,@"automatic PiP has per-app opt-in configuration");
        if(automatic) {
            NSMutableDictionary *shared=[a mutableCopy];shared[@"identity"]=@"shared/A.app";
            Expect(![bridge automaticPiPEnabledForGuest:a],@"automatic PiP defaults off");
            Expect([bridge setAutomaticPiPEnabled:YES forGuest:a error:&error] && [bridge automaticPiPEnabledForGuest:a],@"actual app can opt in before multitask starts");
            Expect(![bridge automaticPiPEnabledForGuest:shared] && ![bridge automaticPiPEnabledForGuest:b],@"namesake shared app and other apps remain independent");
            Expect(![bridge setAutomaticPiPEnabled:YES forGuest:@{@"identity":@"builtin/SideStore",@"builtin":@YES} error:&error],@"builtin is not an automatic guest target");
            Expect(![bridge setAutomaticPiPEnabled:YES forGuest:@{@"identity":@"private/../A.app",@"path":@"A.app"} error:&error],@"invalid app identity is rejected");
            Host=NO;
            Expect(![bridge setAutomaticPiPEnabled:NO forGuest:a error:&error] && [bridge automaticPiPEnabledForGuest:a],@"guest cannot rewrite host auto-PiP choices");
            Host=YES;
            Expect([bridge setAutomaticPiPEnabled:NO forGuest:a error:&error] && ![bridge automaticPiPEnabledForGuest:a],@"disabling removes only the selected app choice");
            [[LCOrbitStorage preferences] setObject:@"invalid" forKey:@"LCFloatingMenu.autoPiPApps"];
            Expect([LCOrbitStorage lastError]!=nil,@"auto-PiP list requires string array JSON type");
        }
        Expect(![bridge isEnabled],@"fullscreen mode starts disabled");
        [Defaults setInteger:1 forKey:@"LCMultitaskMode"];
        Hooks=NO;
        Expect(![bridge setEnabled:YES error:&error] && ![bridge isEnabled],@"missing UI hooks cannot enable mode");
        Hooks=YES;
        Expect([bridge setEnabled:YES error:&error] && [bridge isEnabled],@"host can persist fullscreen mode");
        Expect([Defaults integerForKey:@"LCMultitaskMode"]==1,@"enabling plugin never overwrites LC native-window preference");
        PiPManager *pip=[PiPManager shared];
        Expect(![bridge isPiPActive] && ![bridge stopPiPIfActive:&error] && pip.stops==0,
            @"PiP close rejects idle state without affecting a Guest");
        pip.active=YES;
        Expect([bridge isPiPActive] && [bridge stopPiPIfActive:&error] && !pip.active && pip.stops==1,
            @"host close stops only the currently active AVKit PiP session");
        pip.active=YES;Host=NO;
        Expect(![bridge isPiPActive] && ![bridge stopPiPIfActive:&error] && pip.active && pip.stops==1,
            @"Guest overlay cannot stop the host's active PiP");
        Host=YES;pip.active=NO;
        [bridge setEnabled:YES error:&error];
        Expect([Defaults integerForKey:@"LCMultitaskMode"]==1,@"startup reactivation never overwrites user preference");
        [Defaults setInteger:0 forKey:@"LCMultitaskMode"];
        BOOL hasMenuChoice=[bridge respondsToSelector:@selector(setUseSystemMenu:error:)];
        Expect(hasMenuChoice,@"menu choice is independent of engine enablement");
        if(hasMenuChoice) {
            Expect(![bridge usesSystemMenu] && [bridge shouldShowFloatingMenu],@"existing multitask users retain bead menu by default");
            [bridge setUseSystemMenu:YES error:&error];
            Expect([bridge isEnabled] && [Defaults integerForKey:@"LCMultitaskMode"]==0,
                @"system menu selection preserves current LC backend");
            BOOL hasBoundary=[bridge respondsToSelector:@selector(isManagingWindows)];
            Expect(hasBoundary && ![bridge isManagingWindows],@"system menu leaves native window layout untouched");
            [Defaults setInteger:1 forKey:@"LCMultitaskMode"];
            [bridge setEnabled:YES error:&error];
            Expect([Defaults integerForKey:@"LCMultitaskMode"]==1,@"system startup does not force virtual backend");
            [Defaults setInteger:0 forKey:@"LCMultitaskMode"];
            Expect(![bridge shouldShowFloatingMenu],@"native task menu hides bead overlay");
            [bridge setUseSystemMenu:NO error:&error];
        }
        __block NSUInteger menuRequests=0;
        id menuObserver=[NSNotificationCenter.defaultCenter addObserverForName:@"LCOrbitMultitaskMenuRequested"
            object:nil queue:nil usingBlock:^(NSNotification *note) {if([note.userInfo[@"expanded"] boolValue]) menuRequests++;}];
        if([bridge respondsToSelector:@selector(requestMenu)]) [bridge requestMenu];
        Expect(menuRequests==1,@"LC menu requests reach the injected host through an in-process event");
        Host=NO;
        if([bridge respondsToSelector:@selector(requestMenu)]) [bridge requestMenu];
        Expect(menuRequests==1,@"child context cannot request host menu presentation");
        Expect(![bridge launchGuest:a error:&error] && Launches==0,@"guest context cannot launch host multitask processes");
        Host=YES;
        Expect(![bridge launchGuest:@{} error:&error] && Launches==0,@"malformed targets cannot reach LC");
        NSMutableDictionary *ineligible=[a mutableCopy]; ineligible[@"launchable"]=@NO;
        Expect(![bridge launchGuest:ineligible error:&error],@"ineligible target cannot reach LC");
        Extension=nil;
        Expect(![bridge launchGuest:a error:&error] && Launches==0,@"missing extension rejects without classic restart");
        Extension=@"test.LiveProcess";
        ContainerOwner=@"livecontainer2.liveprocess";
        Expect(![bridge launchGuest:a error:&error] && Launches==0,@"container owned by another process cannot be launched twice");
        ContainerOwner=nil;
        [Defaults setInteger:1 forKey:@"LCMultitaskMode"];
        Expect(![bridge launchGuest:a error:&error],@"native windows cannot silently replace fullscreen mode");
        [Defaults setInteger:0 forKey:@"LCMultitaskMode"];
        id observer=[NSNotificationCenter.defaultCenter addObserverForName:@"LCOrbitMultitaskLaunchFailed"
            object:nil queue:nil usingBlock:^(NSNotification *note) { if(note.userInfo[@"error"]) Notices++; }];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"LCOpenSideStore"];
        Expect([bridge launchGuest:a error:&error],@"ready guest reaches native multitask launcher");
        Expect(Launches==1 && [Selected isEqualToString:@"A.app"] && [Container isEqualToString:@"a"],@"LC receives selected app and exact container");
        Expect(![NSUserDefaults.standardUserDefaults boolForKey:@"LCOpenSideStore"],@"guest launch clears stale SideStore flag");
        Expect(![bridge launchGuest:b error:&error] && Launches==1,@"pending launch cannot be overwritten by second app");
        Pending(nil,[NSError errorWithDomain:@"test" code:9 userInfo:nil]); Pending=nil;
        Expect(Notices==1,@"asynchronous failure reaches menu notification");
        Expect([NSUserDefaults.standardUserDefaults objectForKey:@"selected"]==nil &&
            [NSUserDefaults.standardUserDefaults objectForKey:@"selectedContainer"]==nil,@"failed launch leaves no restart selection");
        Expect([bridge launchGuest:a error:&error] && Launches==2,@"failure releases pending launch guard");
        OrbitWindow *wa=[OrbitWindow new]; wa.running=YES;
        [bridge recordWindow:wa bundle:@"A.app" container:@"a"];
        [bridge recordWindow:wa bundle:@"A.app" container:@"a"];
        [bridge didActivateWindow:wa];
        Pending(@123,nil); Pending=nil;
        Expect([[bridge windows] count]==1 && [bridge isCurrentGuest:a],@"window registry deduplicates and identifies current guest");
        if(automatic) {
            NSUInteger beforeRefresh=AutomaticRefreshes;
            [bridge forgetWindow:nil];
            Expect(AutomaticRefreshes>beforeRefresh,@"module stop refreshes PiP even with a live current window and no stale registry entry");
            Expect([[bridge activeGuestForAutomaticPiP][@"identity"] isEqual:a[@"identity"]],@"automatic PiP resolves the exact running guest");
            NSMutableDictionary *otherDefault=[a mutableCopy];otherDefault[@"uuid"]=@"another-default-container";
            Inventory=@[otherDefault,b];
            Expect([[bridge activeGuestForAutomaticPiP][@"uuid"] isEqual:a[@"uuid"]],@"per-app PiP uses the live container rather than another configured default");
            Inventory=@[a,b];
            wa.running=NO;
            Expect([bridge activeGuestForAutomaticPiP]==nil,@"dead scene cannot be armed for PiP");
            wa.running=YES;
            Inventory=@[b];
            Expect([bridge activeGuestForAutomaticPiP]==nil,@"removed guest cannot be armed from a stale registry entry");
            Inventory=@[a,b];
        }
        NSMutableDictionary *namesake=[a mutableCopy];
        namesake[@"identity"]=@"shared/A.app";namesake[@"folder"]=@"/other-scope/A.app";
        Expect(![bridge isCurrentGuest:namesake],@"same bundle and container in another scope is not the active guest");
        Expect(![bridge launchGuest:namesake error:&error] && Launches==2,@"same-name scope conflict cannot reuse the wrong guest process");
        Expect([bridge launchGuest:b error:&error] && Launches==3,@"next app can start without terminating current");
        OrbitWindow *wb=[OrbitWindow new]; wb.running=YES;
        [bridge recordWindow:wb bundle:@"B.app" container:@"b"];
        [bridge didActivateWindow:wb]; Pending(@456,nil); Pending=nil;
        Expect([bridge launchGuest:a error:&error] && Launches==3,@"switching running app reuses existing process");
        if(hasMenuChoice) {
            [bridge setUseSystemMenu:YES error:&error];
            NSUInteger before=menuRequests;
            [bridge requestMenu];
            Expect(menuRequests==before,@"native menu mode does not open a hidden bead menu");
            Expect([bridge launchGuest:b error:&error] && Launches==3 && [bridge isCurrentGuest:b],
                @"native menu mode reuses running tasks without classic restart");
            Expect(wa.running && wb.running,@"menu changes keep every guest process alive");
            BOOL tracksHide=[bridge respondsToSelector:@selector(didHideWindow:)];
            Expect(tracksHide,@"LC native minimize can clear the current task without terminating it");
            if(tracksHide) {
                [bridge didHideWindow:wa];
                Expect([bridge isCurrentGuest:b],@"hiding a background task cannot clear the foreground task");
                [bridge didHideWindow:wb];
                Expect([bridge activeWindow]==nil && wb.running,@"LC native home clears current task and keeps process alive");
                [bridge launchGuest:b error:&error];
            }
            [bridge setUseSystemMenu:NO error:&error];
            [bridge launchGuest:a error:&error];
            [[LCOrbitStorage preferences] setBool:NO forKey:@"LCOrbit.module.FloatingMenu.enabled"];
            Expect(![bridge isEnabled] && ![bridge shouldShowFloatingMenu],@"disabled plugin cannot intercept tasks or show bead");
            [[LCOrbitStorage preferences] setBool:YES forKey:@"LCOrbit.module.FloatingMenu.enabled"];
            Expect([bridge isEnabled] && [bridge shouldShowFloatingMenu],@"re-enabling plugin preserves multitask and menu preferences");
        }
        Expect(!wa.hidden && wb.hidden && wa.running && wb.running,@"switch shows one window and preserves both processes");
        Expect([bridge isCurrentGuest:a] && ![bridge isCurrentGuest:b],@"active identity follows switched task");
        // A's running scene must survive closing background B. Use exact scope+container,
        // not the currently active window and not the app basename alone.
        BOOL hasTargetAPI=[bridge respondsToSelector:@selector(isRunningGuest:)] &&
            [bridge respondsToSelector:@selector(closeGuest:error:)];
        Expect(hasTargetAPI,@"running task has exact-target close API");
        if(hasTargetAPI) {
            Expect([bridge isRunningGuest:a] && [bridge isRunningGuest:b],@"foreground and background tasks both eligible for close icon");
            Expect(![bridge isRunningGuest:namesake],@"wrong app scope never gets a close icon");
            Expect(![bridge isRunningGuest:Guest(@"C.app",@"c")],@"installed but not running app never gets a close icon");
            Expect(![bridge closeGuest:namesake error:&error] && wa.running && wb.running,
                @"close rejects different-scope name collision");
            NSUInteger refreshBeforeClose=ConfigRefreshes;
            Expect([bridge closeGuest:b error:&error] && !wb.running && wa.running && [bridge isCurrentGuest:a],
                @"close background B does not switch or terminate active A");
            Expect(![bridge closeGuest:b error:&error],@"stale close cannot target another window");
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
            Expect(ConfigRefreshes>refreshBeforeClose,@"task termination refreshes running-app close badges without switching");
            wb.running=YES;[bridge recordWindow:wb bundle:@"B.app" container:@"b"];
            [bridge didActivateWindow:wa];
        }

        Expect([bridge respondsToSelector:@selector(closeCurrentGuest)] && [bridge closeCurrentGuest] && !wa.running && wb.running,@"close current uses LC lifecycle and preserves other tasks");
        [bridge showHome];
        Expect(wb.hidden && wb.running && [bridge activeWindow]==nil,@"home hides remaining windows without ending guest state");
        wa.running=NO;
        [bridge forgetWindow:wa];
        Expect([[bridge windows] count]==1,@"terminated windows leave the registry");
        Expect([bridge setEnabled:NO error:&error] && ![bridge isEnabled],@"mode can be disabled");
        Expect([Defaults integerForKey:@"LCMultitaskMode"]==0,@"native mode restoration waits for running virtual windows to close");
        Expect([bridge setEnabled:YES error:&error] && [bridge setEnabled:NO error:&error],@"mode can toggle while virtual tasks remain alive");
        [bridge forgetWindow:wb];
        Expect([Defaults integerForKey:@"LCMultitaskMode"]==0,@"disable does not restore stale LC settings");
        [Defaults setInteger:1 forKey:@"LCMultitaskMode"];
        [Defaults setInteger:0 forKey:@"LCFloatingMenu.previousMultitaskMode"];
        [bridge setEnabled:YES error:&error];[bridge setEnabled:NO error:&error];
        Expect([Defaults integerForKey:@"LCMultitaskMode"]==1,@"legacy recovery snapshot cannot overwrite the user's latest backend");
        Expect(![bridge launchGuest:a error:&error] && Launches==3,@"disabled mode cannot launch extra guests");
        if([bridge respondsToSelector:@selector(requestMenu)]) [bridge requestMenu];
        Expect(menuRequests==1,@"system menu selection does not open bead task UI");
        [bridge setEnabled:YES error:&error];
        BOOL adaptive=[bridge respondsToSelector:@selector(setUseAdaptiveSwitcher:error:)];
        Expect(adaptive,@"adaptive switching provides real task routing rather than a decorative menu");
        if(adaptive) {
            Expect([bridge setUseAdaptiveSwitcher:YES error:&error] && [bridge usesAdaptiveSwitcher],@"adaptive selection persists independently of legacy choices");
            Expect([bridge respondsToSelector:@selector(setTaskSwitcherPresentation:error:)],
                @"adaptive mode exposes an explicit iPhone/iPad presentation choice");
            if([bridge respondsToSelector:@selector(setTaskSwitcherPresentation:error:)]) {
                NativeSupported=YES;
                Expect([bridge setTaskSwitcherPresentation:0 error:&error] &&
                    [bridge usesAdaptiveSwitcher] && ![bridge usesNativeTaskWindows],
                    @"iPhone presentation remains selectable on the current device");
                Expect([bridge setTaskSwitcherPresentation:1 error:&error] &&
                    [bridge usesAdaptiveSwitcher] && [bridge usesNativeTaskWindows],
                    @"iPad presentation can be selected from iPhone without becoming unavailable");
                NativeSupported=NO;
                Expect([bridge taskSwitcherPresentation]==1&&![bridge usesNativeTaskWindows]&&[bridge isManagingWindows],
                    @"iPad choice remains selected and uses LC live tasks on a single-window phone host");
            }
            Expect([bridge setTaskSwitcherPresentation:0 error:&error],@"iPhone presentation can be restored before card-flow checks");
            [Defaults setInteger:1 forKey:@"LCMultitaskMode"];
            Expect(![bridge usesNativeTaskWindows] && [bridge isManagingWindows],@"phone adaptive path remains fullscreen even with stale native LC setting");
            Expect([Defaults integerForKey:@"LCMultitaskMode"]==1,@"adaptive routing never rewrites LC settings");
            Expect([bridge launchGuest:a error:&error],@"phone adaptive route starts actual LiveProcess task");
            wa.running=YES;[bridge recordWindow:wa bundle:@"A.app" container:@"a"];
            [bridge didActivateWindow:wa];Pending(@321,nil);Pending=nil;
            NSArray *tasks=[bridge runningTasks];
            NSDictionary *card=tasks.firstObject;
            Expect(tasks.count==1 && card[@"window"]==wa && [card[@"uuid"] isEqual:@"a"] && [card[@"folder"] isEqual:@"/fixture/A.app"],@"card exposes actual running window and exact identity");
            BOOL cachedInventory=[bridge respondsToSelector:@selector(runningTasksForApps:)];
            Expect(cachedInventory,@"presentation can enumerate live tasks without rescanning drawer inventory");
            if(cachedInventory) {
                Inventory=@[];
                Expect([[bridge runningTasksForApps:@[a,b]] count]==1,@"presentation reuses supplied inventory with actual live task identities");
                Expect([[bridge runningTasksForApps:@[]] count]==0,@"empty presentation inventory never invents task cards");
                Inventory=@[a,b];
            }
            wb.running=YES;[bridge recordWindow:wb bundle:@"B.app" container:@"b"];
            [bridge didActivateWindow:wb];
            NSArray *openedOrder=[bridge runningTasksForApps:@[b,a]];
            Expect(openedOrder.count==2 && openedOrder[0][@"window"]==wa && openedOrder[1][@"window"]==wb,
                @"active B keeps its first-open slot after A even when inventory order differs");
            Expect(openedOrder.count==2 && ![openedOrder[0][@"active"] boolValue] && [openedOrder[1][@"active"] boolValue],
                @"active task is identified at its original position rather than moved to the front");
            [bridge recordWindow:wb bundle:@"B.app" container:@"b"];
            [bridge recordWindow:wa bundle:@"A.app" container:@"a"];
            NSArray *rerecorded=[bridge runningTasks];
            Expect(rerecorded.count==2 && rerecorded[0][@"window"]==wa && rerecorded[1][@"window"]==wb &&
                [rerecorded[0][@"token"] isEqual:card[@"token"]],
                @"recording existing windows again preserves first-open order and exact task generation");
            [bridge didActivateWindow:wa];
            NSArray *switchedBack=[bridge runningTasks];
            Expect(switchedBack.count==2 && switchedBack[0][@"window"]==wa && switchedBack[1][@"window"]==wb &&
                [switchedBack[0][@"active"] boolValue] && ![switchedBack[1][@"active"] boolValue],
                @"switching active task only changes active flags and preserves card order");
            NSDictionary *backgroundHandle=nil;
            for(NSDictionary *task in switchedBack)if(task[@"window"]==wb)backgroundHandle=task;
            wb.defersClose=YES;
            Expect([bridge closeTask:backgroundHandle error:&error] && wa.running && wb.running &&
                [bridge runningTasks].count==1 && [bridge runningTasks].firstObject[@"window"]==wa,
                @"closing a background task removes its card before the process exits");
            Expect(![bridge activateTask:backgroundHandle error:&error]&&![bridge launchGuest:b error:&error],
                @"a task terminating in the background cannot be resumed from the deck or Dock");
            wb.defersClose=NO;[wb closeWindow];
            Expect([bridge activateTask:card error:&error] && [bridge isCurrentGuest:a],@"card selection reuses original running task");
            NSMutableDictionary *forged=[card mutableCopy];forged[@"folder"]=@"/other-scope/A.app";
            Expect(![bridge closeTask:forged error:&error] && wa.running,@"card close rejects forged scope");
            wa.running=NO;
            Expect([bridge runningTasks].count==0 && ![bridge activateTask:card error:&error],@"exited tasks are removed from overview and stale selection rejected");
            [bridge forgetWindow:wa];
            Expect([bridge launchGuest:a error:&error],@"same task identity can restart after exit");
            wa.running=YES;[bridge recordWindow:wa bundle:@"A.app" container:@"a"];Pending(@322,nil);Pending=nil;
            Expect(![bridge closeTask:card error:&error] && wa.running,@"old card cannot close restarted task with same identity and controller");
            Expect([bridge closeTask:[bridge runningTasks].firstObject error:&error] && !wa.running,@"fresh card closes its exact process");
            NativeSupported=YES;
            Expect([bridge setTaskSwitcherPresentation:1 error:&error],@"iPad presentation is selected for native-window checks");
            Expect([bridge usesNativeTaskWindows] && ![bridge isManagingWindows],@"supported iPad leaves native scene geometry to system");
            NSUInteger oldVirtualLaunches=Launches;
            Expect(![bridge launchGuest:namesake error:&error] && NativeLaunches==0,@"new native launch rejects same-name app when LC resolves another scope");
            Expect([bridge launchGuest:a error:&error] && NativeLaunches==1 && Launches==oldVirtualLaunches,@"iPad adaptive launch uses native-window bridge without virtual fallback");
            Expect([bridge isRunningGuest:a] && [bridge isCurrentGuest:a],@"native window participates in exact running/current identity");
            Expect([bridge launchGuest:a error:&error] && NativeLaunches==1 && NativeActivations==1,@"native relaunch activates existing window");
            [bridge showHome];
            Expect(NativeHomes==1 && [NativeTask[@"running"] boolValue],@"native Home activates LC main scene without ending task");
            Expect(![bridge closeGuest:namesake error:&error] && NativeCloses==0,@"native close rejects different-scope namesake");
            NSDictionary *nativeCard=[bridge runningTasks].firstObject;
            Expect([nativeCard[@"native"] boolValue] && !nativeCard[@"window"] && [nativeCard[@"token"] isEqual:NativeTask[@"token"]],@"native descriptor retains token without virtual-view placeholder");
            Expect([bridge closeTask:nativeCard error:&error] && NativeCloses==1,@"exact native close reaches matching system scene");
            Expect(![bridge closeTask:nativeCard error:&error] && NativeCloses==1,@"stale native close cannot reach another task");
            [bridge setUseSystemMenu:NO error:&error];
            Expect(![bridge usesAdaptiveSwitcher] && ![bridge usesSystemMenu],@"selecting legacy bead mode exits adaptive routing");
            NativeSupported=NO;[Defaults setInteger:0 forKey:@"LCMultitaskMode"];
        }
        NSString *config=[[LCOrbitStorage rootPath] stringByAppendingPathComponent:@"config.json"];
        NSData *savedConfig=[NSData dataWithContentsOfFile:config];
        [@"invalid JSON" writeToFile:config atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Expect(![bridge setUseSystemMenu:YES error:&error] && error!=nil && ![bridge usesSystemMenu],@"failed menu save reports error and retains effective choice");
        Expect(![bridge setEnabled:NO error:&error] && [bridge isEnabled],@"failed mode save cannot report success or disable effective mode");
        if(automatic) Expect(![bridge setAutomaticPiPEnabled:YES forGuest:a error:&error] && ![bridge automaticPiPEnabledForGuest:a],@"failed JSON save cannot enable auto-PiP");
        [savedConfig writeToFile:config atomically:YES];[bridge setEnabled:NO error:nil];
        [NSNotificationCenter.defaultCenter removeObserver:refreshObserver];
        [NSNotificationCenter.defaultCenter removeObserver:menuObserver];
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [Defaults removePersistentDomainForName:suite];
        fprintf(stdout,"Multitask behavior tests: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
