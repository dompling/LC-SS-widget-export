#import <Foundation/Foundation.h>

// UIKit is unavailable to this macOS runner. Keep UI objects inert while
// executing the production launch, detach, lifecycle and observer methods.
enum { UISceneActivationStateForegroundActive=0, UISceneActivationStateBackground=2,
       UIApplicationStateActive=0, UIApplicationStateBackground=2 };
static NSString *const UIApplicationDidEnterBackgroundNotification=@"background";
static NSString *const UIApplicationWillResignActiveNotification=@"inactive";
static NSString *const UIApplicationDidBecomeActiveNotification=@"active";
static NSString *const UIApplicationDidReceiveMemoryWarningNotification=@"memory";
static NSString *const UISceneWillDeactivateNotification=@"scene-inactive";
static NSString *const UISceneDidDisconnectNotification=@"scene-disconnected";
static NSString *const LCOrbitMultitaskConfigurationChangedNotification=@"configuration";
@interface UIView : NSObject
- (void)removeFromSuperview;
@end
@implementation UIView
- (void)removeFromSuperview {}
@end
@interface UIWindowScene : NSObject
@property NSInteger activationState;
- (void)unregisterForTraitChanges:(id)registration;
@end
@implementation UIWindowScene
- (void)unregisterForTraitChanges:(id)registration {}
@end
@interface UIWindow : NSObject
@property(nonatomic,strong) UIWindowScene *windowScene;
@property BOOL hidden,isKeyWindow;
@property(nonatomic,strong) id rootViewController;
- (void)makeKeyWindow;
@end
@implementation UIWindow
- (void)makeKeyWindow { self.isKeyWindow=YES; }
@end
@interface UIApplication : NSObject
@property NSInteger applicationState;
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if(!app) app=[self new];return app; }
@end
@interface LaunchEvents : NSObject
@property NSUInteger requests;
- (void)publish:(NSString *)name payload:(NSDictionary *)payload;
@end
@implementation LaunchEvents
- (void)publish:(NSString *)name payload:(NSDictionary *)payload { self.requests++; }
@end
@interface LaunchOverlays : NSObject
- (void)unmountModule:(NSString *)module;
@end
@implementation LaunchOverlays
- (void)unmountModule:(NSString *)module {}
@end
@interface LCOrbitContext : NSObject
@property(nonatomic,strong) LaunchEvents *events;
@property(nonatomic,strong) LaunchOverlays *overlays;
@end
@implementation LCOrbitContext @end
static BOOL ModuleEnabled,MultitaskEnabled,SystemMenu,HostUI,RejectLaunch,SyncImmediately;
static NSString *CurrentGuest;
static __weak UIWindowScene *FMStyleScene;
static NSUInteger Attempts,ClassicLaunches,MultitaskLaunches,Warnings,Assertions,Failures;
static NSMutableArray<void (^)(void)> *SyncCompletions;
static NSString *FMAppKey(NSDictionary *app) { return app[@"identity"]?:app[@"path"]?:@""; }
// Recency persistence is separately tested by the UIKit drawer fixture.
static void FMRememberOpenedApp(NSDictionary *app) { (void)app; }
static NSString *GuestID(void) { return CurrentGuest; }
static BOOL FMHostUI(void) { return HostUI; }
static void FMLog(NSString *event,NSString *detail) {}
static void FMSyncSharedTweaks(void (^completion)(void)) {
    if(!completion) return;
    if(SyncImmediately) completion(); else [SyncCompletions addObject:[completion copy]];
}
@interface LCOrbitCore : NSObject
+ (instancetype)sharedCore;
- (BOOL)isModuleEnabled:(NSString *)module;
@end
@implementation LCOrbitCore
+ (instancetype)sharedCore { static LCOrbitCore *core; if(!core) core=[self new];return core; }
- (BOOL)isModuleEnabled:(NSString *)module { return ModuleEnabled; }
@end
@interface LCOrbitMultitask : NSObject
+ (BOOL)isEnabled;
+ (BOOL)usesSystemMenu;
+ (BOOL)shouldShowFloatingMenu;
+ (void)refreshPresentation;
+ (void)forgetWindow:(id)window;
+ (BOOL)installHooksWithError:(NSError **)error;
@end
@implementation LCOrbitMultitask
+ (BOOL)isEnabled { return MultitaskEnabled && ModuleEnabled && HostUI; }
+ (BOOL)usesSystemMenu { return SystemMenu; }
+ (BOOL)shouldShowFloatingMenu { return ModuleEnabled && !SystemMenu; }
+ (void)refreshPresentation {}
+ (void)forgetWindow:(id)window {}
+ (BOOL)installHooksWithError:(NSError **)error { return YES; }
@end
@interface LCOrbitStorage : NSObject
+ (BOOL)reloadWithError:(NSError **)error;
@end
@implementation LCOrbitStorage
+ (BOOL)reloadWithError:(NSError **)error { return YES; }
@end
@interface LCOrbitGuestService : NSObject
+ (BOOL)launchGuest:(NSDictionary *)app error:(NSError **)error;
@end
@implementation LCOrbitGuestService
+ (BOOL)launchGuest:(NSDictionary *)app error:(NSError **)error {
    Attempts++;
    if(RejectLaunch) {
        if(error) *error=[NSError errorWithDomain:@"launch-test" code:1 userInfo:nil];
        return NO;
    }
    if([LCOrbitMultitask isEnabled]) MultitaskLaunches++; else ClassicLaunches++;
    return YES;
}
@end
@interface FMManager : NSObject
@property(nonatomic,strong) UIWindow *window,*settingsWindow,*previousKeyWindow;
@property(nonatomic,strong) UIView *orbPreviewHost;
@property(nonatomic,strong) LCOrbitContext *orbitContext;
@property(nonatomic,strong) UIWindowScene *appearanceScene;
@property(nonatomic,strong) id appearanceRegistration,settingsNavigation,settingsScreen,settingsScroll;
@property(nonatomic,strong) id appsScroll,overlayView,orb,panel,dismissLayer;
@property(nonatomic,strong) NSTimer *orbUpdateTimer;
@property(nonatomic,weak) id orbUpdateLine;
@property BOOL appsScrollRestorePending,isOpen,launchPending,launchMultitaskMode,launchSystemMenuMode;
@property NSUInteger launchGeneration;
+ (instancetype)shared;
- (void)launchApp:(NSDictionary *)app;
- (void)detachFromScene;
- (void)persistAppsScroll;
- (void)cancelAppearanceCheck;
- (void)draw;
- (void)refreshUI;
- (void)requestAppsRefresh;
- (void)installIfPossible;
- (void)checkOrbUpdateIfNeeded;
- (void)showMessage:(NSString *)title details:(NSString *)detail;
@end
@interface FMManager (LaunchInvalidation)
- (void)invalidatePendingLaunch;
@end
static FMManager *Manager;
@implementation FMManager
+ (instancetype)shared { return Manager; }
- (void)persistAppsScroll {}
- (void)cancelAppearanceCheck {}
- (void)draw {}
- (void)refreshUI {}
- (void)requestAppsRefresh {}
- (void)installIfPossible {}
- (void)checkOrbUpdateIfNeeded {}
- (void)showMessage:(NSString *)title details:(NSString *)detail { Warnings++; }
#include "launch.inc"
@end
@interface LCFloatingMenuModule : NSObject
@property(nonatomic,strong) id configurationObserver,configurationFailureObserver,taskMenuObserver,launchFailureObserver;
- (void)installConfigurationObserver;
- (void)orbitWillStop;
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event scene:(UIWindowScene *)scene;
@end
@implementation LCFloatingMenuModule
- (void)installConfigurationObserver {
    FMManager *manager=Manager;
#include "launch-observer.inc"
}
#include "launch-module.inc"
@end
static void Expect(BOOL result,NSString *message) {
    Assertions++;if(!result) { Failures++;fprintf(stderr,"FAIL: %s\n",message.UTF8String); }
}
static FMManager *NewManager(void) {
    ModuleEnabled=YES;MultitaskEnabled=YES;SystemMenu=NO;HostUI=YES;RejectLaunch=NO;SyncImmediately=NO;CurrentGuest=@"host";
    Attempts=ClassicLaunches=MultitaskLaunches=Warnings=0;
    SyncCompletions=[NSMutableArray array];
    UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
    Manager=[FMManager new];Manager.window=[UIWindow new];Manager.window.windowScene=[UIWindowScene new];
    Manager.orbitContext=[LCOrbitContext new];Manager.orbitContext.events=[LaunchEvents new];
    Manager.orbitContext.overlays=[LaunchOverlays new];
    return Manager;
}
static void CompleteSync(void) {
    NSArray *pending=[SyncCompletions copy];[SyncCompletions removeAllObjects];
    for(void (^completion)(void) in pending) completion();
}
static NSDictionary *Target(void) {
    return @{@"identity":@"private/one.app",@"path":@"one.app",@"uuid":@"container-one",@"folder":@"/Applications/one.app",@"launchable":@YES};
}
int main(void) {
    @autoreleasepool {
        FMManager *manager=NewManager();NSDictionary *target=Target();
        [manager launchApp:target];[manager launchApp:target];
        Expect(SyncCompletions.count==1 && manager.orbitContext.events.requests==1,
            @"repeated taps reserve one request before asynchronous sharing");
        CompleteSync();Expect(MultitaskLaunches==1 && ClassicLaunches==0,@"one unchanged multitask request launches once");

        manager=NewManager();[manager launchApp:target];MultitaskEnabled=NO;CompleteSync();
        Expect(Attempts==0,@"disabling multitask during sharing cancels instead of falling back to classic");

        manager=NewManager();MultitaskEnabled=NO;[manager launchApp:target];MultitaskEnabled=YES;CompleteSync();
        Expect(Attempts==0,@"enabling multitask during sharing cannot change a classic request's backend");

        manager=NewManager();[manager launchApp:target];ModuleEnabled=NO;CompleteSync();
        Expect(Attempts==0,@"disabled module cannot launch from an already queued completion");

        manager=NewManager();LCFloatingMenuModule *module=[LCFloatingMenuModule new];[module installConfigurationObserver];
        [manager launchApp:target];MultitaskEnabled=NO;
        [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskConfigurationChangedNotification object:nil];
        MultitaskEnabled=YES;
        [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskConfigurationChangedNotification object:nil];
        CompleteSync();Expect(Attempts==0,@"mode change and change back still cancels the old request");
        [module orbitWillStop];

        manager=NewManager();module=[LCFloatingMenuModule new];[module installConfigurationObserver];
        [manager launchApp:target];
        [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskConfigurationChangedNotification object:nil];
        CompleteSync();Expect(MultitaskLaunches==1,@"ordinary task refresh preserves the pending request in an unchanged mode");
        [module orbitWillStop];

        manager=NewManager();[manager launchApp:target];SystemMenu=YES;CompleteSync();
        Expect(Attempts==0,@"switching multitask presentation cancels the pending request");

        manager=NewManager();UIWindow *oldWindow=manager.window;[manager launchApp:target];
        [manager detachFromScene];manager.window=oldWindow;[manager launchApp:target];
        void (^oldCompletion)(void)=SyncCompletions.firstObject;[SyncCompletions removeObjectAtIndex:0];oldCompletion();
        [manager launchApp:target];
        Expect(SyncCompletions.count==1,@"old completion cannot release a new generation's reservation");
        CompleteSync();
        Expect(MultitaskLaunches==1,@"detaching invalidates old generation even when the same scene is reattached");

        manager=NewManager();[manager launchApp:target];manager.window.windowScene=[UIWindowScene new];CompleteSync();
        Expect(Attempts==0,@"scene replacement cancels the old request");

        manager=NewManager();[manager launchApp:target];manager.window.windowScene.activationState=UISceneActivationStateBackground;CompleteSync();
        Expect(Attempts==0,@"inactive source scene cannot launch");

        manager=NewManager();[manager launchApp:target];module=[LCFloatingMenuModule new];
        [module orbitDidReceiveLifecycleEvent:UISceneWillDeactivateNotification scene:manager.window.windowScene];
        CompleteSync();Expect(Attempts==0,@"scene deactivation cancels even if activation state already changed back");

        manager=NewManager();[manager launchApp:target];UIApplication.sharedApplication.applicationState=UIApplicationStateBackground;
        CompleteSync();Expect(Attempts==0,@"background application cannot launch even while scene state lags");

        manager=NewManager();[manager launchApp:target];module=[LCFloatingMenuModule new];
        [module orbitDidReceiveLifecycleEvent:UISceneWillDeactivateNotification scene:[UIWindowScene new]];
        CompleteSync();Expect(MultitaskLaunches==1,@"unrelated scene deactivation preserves the request's active source scene");

        manager=NewManager();manager.settingsWindow=[UIWindow new];manager.settingsWindow.windowScene=manager.window.windowScene;manager.window=nil;
        [manager launchApp:target];
        [module orbitDidReceiveLifecycleEvent:UISceneWillDeactivateNotification scene:manager.settingsWindow.windowScene];
        CompleteSync();Expect(Attempts==0,@"settings-only source scene deactivation also invalidates the request");

        manager=NewManager();[manager launchApp:target];manager.orbitContext=[LCOrbitContext new];CompleteSync();
        Expect(Attempts==0,@"replacement Orbit context cannot consume an old request");

        manager=NewManager();[manager launchApp:target];CurrentGuest=@"other-guest";CompleteSync();
        Expect(Attempts==0,@"changed guest context cannot consume a host request");

        manager=NewManager();[manager launchApp:target];HostUI=NO;CompleteSync();
        Expect(Attempts==0,@"changed host context cannot change the launch backend");

        manager=NewManager();manager.settingsWindow=[UIWindow new];manager.settingsWindow.windowScene=manager.window.windowScene;
        [manager launchApp:target];manager.settingsWindow=nil;CompleteSync();
        Expect(MultitaskLaunches==1,@"closing settings within the same scene preserves an unchanged request");

        manager=NewManager();module=[LCFloatingMenuModule new];[manager launchApp:target];
        LCOrbitContext *context=manager.orbitContext;oldWindow=manager.window;[module orbitWillStop];
        manager.orbitContext=context;manager.window=oldWindow;CompleteSync();
        Expect(Attempts==0,@"module stop cancels old work even if restarted with the same context and scene");

        manager=NewManager();RejectLaunch=YES;[manager launchApp:target];CompleteSync();
        RejectLaunch=NO;[manager launchApp:target];CompleteSync();
        Expect(Attempts==2 && MultitaskLaunches==1 && Warnings==1,@"launch rejection releases the reservation for retry");

        manager=NewManager();MultitaskEnabled=NO;[manager launchApp:target];CompleteSync();
        Expect(ClassicLaunches==1 && MultitaskLaunches==0,@"unchanged classic request still launches normally");

        manager=NewManager();SyncImmediately=YES;[manager launchApp:target];
        Expect(MultitaskLaunches==1 && !manager.launchPending,@"synchronous sharing path completes and releases its reservation");

        manager=NewManager();[manager launchApp:target];__weak FMManager *released=manager;manager=nil;Manager=nil;
        Expect(released==nil,@"queued sharing completion does not retain the manager's lifetime");
        CompleteSync();Expect(Attempts==0,@"released manager cannot launch from a queued completion");

        manager=NewManager();ModuleEnabled=NO;[manager launchApp:target];CompleteSync();
        Expect(Attempts==0 && SyncCompletions.count==0,@"disabled module never starts sharing or launch");

        fprintf(stdout,"Floating launch lifecycle: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
