#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Only these policy/log boundaries are replaced. The complete production
// coordinator is compiled as a separate translation unit by this runner.
@interface LCOrbitMultitask : NSObject
+ (BOOL)isEnabled;
+ (id)activeWindow;
+ (NSDictionary *)activeGuestForAutomaticPiP;
+ (BOOL)automaticPiPEnabledForGuest:(NSDictionary *)guest;
+ (void)refreshPresentation;
@end
@interface LCOrbitLog : NSObject
+ (void)appendEvent:(NSString *)event details:(id)details kind:(NSString *)kind;
@end

NSString *const UIApplicationDidBecomeActiveNotification=@"FixtureDidBecomeActive";
NSString *const UIApplicationDidEnterBackgroundNotification=@"FixtureDidEnterBackground";
NSString *const UISceneDidActivateNotification=@"FixtureSceneActive";
NSString *const UIWindowDidBecomeVisibleNotification=@"FixtureWindowVisible";
NSString *const LCOrbitMultitaskConfigurationChangedNotification=@"FixtureConfiguration";
NSString *const LCOrbitMultitaskMenuRequestedNotification=@"FixtureMenu";

@implementation OrbitPiPFixtureLayer @end
@implementation UIView
- (instancetype)init { return [self initWithFrame:CGRectMake(0,0,320,640)]; }
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super init])) {
        _frame=frame;_bounds=(CGRect){CGPointZero,frame.size};
        _layer=[OrbitPiPFixtureLayer new];_subviews=[NSMutableArray array];
    }
    return self;
}
- (void)addSubview:(UIView *)view {
    [view removeFromSuperview];[self.subviews addObject:view];
    view.superview=self;view.window=self.window;
}
- (void)removeFromSuperview { [self.superview.subviews removeObject:self];self.superview=nil; }
@end
@implementation UIViewController
- (instancetype)init { if((self=[super init])) _view=[UIView new];return self; }
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app;static dispatch_once_t once;dispatch_once(&once,^{app=[self new];});return app; }
@end

@interface FixtureScene : NSObject
@property(nonatomic,strong) UIView *view,*contentView;
@property(nonatomic) BOOL running,usesHostingControllerAPI,shouldIgnoreSceneUpdates;
- (BOOL)isAppRunning;
@end
@implementation FixtureScene
- (BOOL)isAppRunning { return self.running; }
@end
@interface FixtureWindow : NSObject
@property(nonatomic,strong) FixtureScene *appSceneVC;
@end
@implementation FixtureWindow @end

static BOOL Enabled,Supported,RejectController,NativeAutoEnd,DeferredStop;
static NSString *MissingNative,*MissingController;
static Class ControllerSubclass;
static FixtureWindow *CurrentWindow;
static NSDictionary *CurrentGuest;
static NSMutableSet<NSString *> *OptedIn;
static NSMutableArray<NSString *> *NativeEvents,*Logs;
static NSMutableArray<FixtureWindow *> *Windows;
static NSUInteger Creations,StartCalls,StopCalls,Restores,Assertions,Failures;
static NSUInteger PresentationRefreshes;
static BOOL RefreshSawProtectedContent;

@implementation LCOrbitMultitask
+ (BOOL)isEnabled { return Enabled; }
+ (id)activeWindow { return Enabled?CurrentWindow:nil; }
+ (NSDictionary *)activeGuestForAutomaticPiP {
    // This boundary models the independently tested policy contract: only
    // a valid living active guest may reach the AVKit preparation layer.
    return Enabled && CurrentWindow.appSceneVC.running && ![CurrentGuest[@"builtin"] boolValue]?CurrentGuest:nil;
}
+ (BOOL)automaticPiPEnabledForGuest:(NSDictionary *)guest {
    return guest && ![guest[@"builtin"] boolValue] && [OptedIn containsObject:guest[@"identity"]];
}
+ (void)refreshPresentation {
    PresentationRefreshes++;
    for(FixtureWindow *window in Windows)
        RefreshSawProtectedContent |= window.appSceneVC.shouldIgnoreSceneUpdates;
}
@end
@implementation LCOrbitLog
+ (void)appendEvent:(NSString *)event details:(id)details kind:(NSString *)kind { [Logs addObject:event]; }
@end

@interface NSObject (FixturePiPDelegate)
- (void)pictureInPictureControllerWillStartPictureInPicture:(id)controller;
- (void)pictureInPictureControllerDidStartPictureInPicture:(id)controller;
- (void)pictureInPictureControllerWillStopPictureInPicture:(id)controller;
- (void)pictureInPictureControllerDidStopPictureInPicture:(id)controller;
- (void)pictureInPictureController:(id)controller failedToStartPictureInPictureWithError:(NSError *)error;
@end
@interface AVPictureInPictureVideoCallViewController : UIViewController @end
@implementation AVPictureInPictureVideoCallViewController @end
@interface AVPictureInPictureControllerContentSource : NSObject
@property(nonatomic,strong) UIView *source;
@property(nonatomic,strong) UIViewController *video;
- (instancetype)initWithActiveVideoCallSourceView:(UIView *)source contentViewController:(UIViewController *)video;
@end
@implementation AVPictureInPictureControllerContentSource
- (instancetype)initWithActiveVideoCallSourceView:(UIView *)source contentViewController:(UIViewController *)video {
    if((self=[super init])) {_source=source;_video=video;}return self;
}
@end
@interface AVPictureInPictureController : NSObject
@property(nonatomic,strong) AVPictureInPictureControllerContentSource *contentSource;
@property(nonatomic,weak) id delegate;
@property(nonatomic,strong) id pendingStopDelegate;
@property(nonatomic) BOOL canStartPictureInPictureAutomaticallyFromInline,active;
@property(nonatomic) NSInteger controlsStyle;
+ (BOOL)isPictureInPictureSupported;
- (instancetype)initWithContentSource:(id)source;
- (BOOL)isPictureInPictureActive;
- (void)startPictureInPicture;
- (void)stopPictureInPicture;
- (void)finishStop;
- (void)simulateSystemStart;
- (void)simulateFailureAfterWillStart:(BOOL)moved;
@end
@implementation AVPictureInPictureController
+ (BOOL)isPictureInPictureSupported { return Supported; }
- (instancetype)initWithContentSource:(id)source {
    if(RejectController)return nil;
    if(self.class==AVPictureInPictureController.class && ControllerSubclass)
        return [[ControllerSubclass alloc] initWithContentSource:source];
    if((self=[super init])) {_contentSource=source;Creations++;}return self;
}
- (BOOL)respondsToSelector:(SEL)selector {
    if([NSStringFromSelector(selector) isEqual:MissingController])return NO;
    return [super respondsToSelector:selector];
}
- (BOOL)isPictureInPictureActive { return self.active; }
- (void)startPictureInPicture { StartCalls++;[self simulateSystemStart]; }
- (void)stopPictureInPicture {
    StopCalls++;
    if(DeferredStop) {self.pendingStopDelegate=self.delegate;return;}
    [self finishStop];
}
- (void)finishStop {
    id delegate=self.pendingStopDelegate ?: self.delegate;
    self.pendingStopDelegate=nil;
    [delegate pictureInPictureControllerWillStopPictureInPicture:self];
    self.active=NO;
    [delegate pictureInPictureControllerDidStopPictureInPicture:self];
}
- (void)simulateSystemStart {
    id delegate=self.delegate;
    [delegate pictureInPictureControllerWillStartPictureInPicture:self];
    // A cancelled WillStart synchronously detaches the delegate.
    if(self.delegate!=delegate)return;
    self.active=YES;[delegate pictureInPictureControllerDidStartPictureInPicture:self];
}
- (void)simulateFailureAfterWillStart:(BOOL)moved {
    id delegate=self.delegate;
    if(moved)[delegate pictureInPictureControllerWillStartPictureInPicture:self];
    NSError *error=[NSError errorWithDomain:@"FixtureAVKit" code:1 userInfo:nil];
    [delegate pictureInPictureController:self failedToStartPictureInPictureWithError:error];
}
@end

@interface PiPManager : NSObject
@property(nonatomic,strong) AVPictureInPictureController *pipController;
@property(nonatomic,strong) UIView *pipVideoCallContentView;
@property(nonatomic,strong) UIViewController *pipVideoCallViewController;
@property(nonatomic,strong) FixtureScene *displayingVC;
+ (instancetype)shared;
@end
@implementation PiPManager
+ (instancetype)shared { static PiPManager *manager;static dispatch_once_t once;dispatch_once(&once,^{manager=[self new];});return manager; }
- (BOOL)respondsToSelector:(SEL)selector {
    if([NSStringFromSelector(selector) isEqual:MissingNative])return NO;
    return [super respondsToSelector:selector];
}
- (void)pictureInPictureControllerWillStartPictureInPicture:(id)controller {
    [NativeEvents addObject:@"willStart"];
    if(self.displayingVC.usesHostingControllerAPI)
        [self.pipVideoCallContentView addSubview:self.displayingVC.contentView];
    [self.pipVideoCallViewController.view addSubview:self.pipVideoCallContentView];
    self.displayingVC.shouldIgnoreSceneUpdates=YES;
}
- (void)pictureInPictureControllerDidStartPictureInPicture:(id)controller { [NativeEvents addObject:@"didStart"]; }
- (void)pictureInPictureControllerWillStopPictureInPicture:(id)controller {
    [NativeEvents addObject:@"willStop"];self.displayingVC.shouldIgnoreSceneUpdates=NO;
}
- (void)pictureInPictureControllerDidStopPictureInPicture:(id)controller {
    [NativeEvents addObject:@"didStop"];
    [self.displayingVC.view addSubview:self.displayingVC.contentView];Restores++;
    if(NativeAutoEnd)self.pipController=nil;
}
- (void)pictureInPictureController:(id)controller failedToStartPictureInPictureWithError:(NSError *)error {
    [NativeEvents addObject:@"failed"];
}
@end

@interface NSObject (AutomaticPiPTest)
+ (instancetype)shared;
- (void)reconcile;
- (void)disarm;
- (void)finished:(id)controller;
@end
static id Driver;
static void Expect(BOOL condition,NSString *message) {
    Assertions++;if(!condition){Failures++;fprintf(stderr,"FAIL: %s\n",message.UTF8String);}
}
static FixtureWindow *Window(BOOL hosting) {
    FixtureScene *scene=[FixtureScene new];scene.running=YES;scene.usesHostingControllerAPI=hosting;
    scene.view=[UIView new];scene.view.window=[NSObject new];scene.contentView=[UIView new];
    [scene.view addSubview:scene.contentView];FixtureWindow *window=[FixtureWindow new];window.appSceneVC=scene;
    // LC's parent controller owns all task windows, including inactive tasks.
    [Windows addObject:window];return window;
}
static NSDictionary *Guest(NSString *identity) { return @{@"identity":identity,@"path":identity.lastPathComponent}; }
static void Reset(void) {
    MissingNative=nil;MissingController=nil;ControllerSubclass=Nil;DeferredStop=NO;
    UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
    [Driver disarm];
    PiPManager *manager=[PiPManager shared];manager.pipController=nil;manager.displayingVC=nil;
    manager.pipVideoCallContentView=nil;manager.pipVideoCallViewController=nil;
    Enabled=YES;Supported=YES;RejectController=NO;NativeAutoEnd=NO;
    OptedIn=[NSMutableSet set];NativeEvents=[NSMutableArray array];Logs=[NSMutableArray array];
    Creations=StartCalls=StopCalls=Restores=PresentationRefreshes=0;RefreshSawProtectedContent=NO;
    Windows=[NSMutableArray array];
    CurrentGuest=Guest(@"private/First.app");CurrentWindow=Window(NO);
}
static AVPictureInPictureController *Arm(BOOL hosting) {
    Reset();CurrentWindow=Window(hosting);[OptedIn addObject:CurrentGuest[@"identity"]];[Driver reconcile];
    return [PiPManager shared].pipController;
}
static BOOL NativeEmpty(void) {
    PiPManager *manager=[PiPManager shared];
    return !manager.pipController && !manager.displayingVC && !manager.pipVideoCallViewController && !manager.pipVideoCallContentView;
}
static void WrongIntegerSetter(id self,SEL selector,NSInteger value) {}
static id WrongObjectGetter(id self,SEL selector) { return nil; }
int main(void) {@autoreleasepool {
    Driver=[NSClassFromString(@"LCOrbitAutomaticPiP") shared];Expect(Driver!=nil,@"production automatic PiP coordinator exists");
    Reset();[Driver reconcile];Expect(Creations==0 && NativeEmpty(),@"default-off never creates or binds an AVKit controller");
    for(NSNumber *hosting in @[@NO,@YES]) {
        AVPictureInPictureController *controller=Arm(hosting.boolValue);PiPManager *manager=[PiPManager shared];
        FixtureScene *scene=CurrentWindow.appSceneVC;
        Expect(controller && controller.canStartPictureInPictureAutomaticallyFromInline && !controller.active,@"opt-in arms native auto-start without entering PiP");
        Expect(controller.controlsStyle==1,@"automatic PiP matches LC manual video-call controls for native close/restore");
        Expect(StartCalls==0 && NativeEvents.count==0 && scene.contentView.superview==scene.view,@"arming does not start, invoke lifecycle, or move content");
        Expect(controller.contentSource.source==scene.view && manager.displayingVC==scene,@"AVKit source belongs to exact active task");
        Expect(CGSizeEqualToSize(manager.pipVideoCallViewController.preferredContentSize,scene.view.bounds.size),@"prepared PiP preserves source aspect ratio");
        Expect(hosting.boolValue?manager.pipVideoCallContentView!=scene.contentView:manager.pipVideoCallContentView==scene.contentView,@"hosting API uses a wrapper while legacy API retains content directly");
        [Driver reconcile];Expect(Creations==1 && StartCalls==0,@"repeated foreground reconciliation is idempotent");
        [OptedIn removeAllObjects];[Driver reconcile];
        Expect(!controller.contentSource && !controller.delegate && !controller.canStartPictureInPictureAutomaticallyFromInline && NativeEmpty(),@"turning off an armed task releases source and native bindings");
    }
    AVPictureInPictureController *first=Arm(NO);id oldDelegate=first.delegate;
    FixtureWindow *secondWindow=Window(YES);NSDictionary *secondGuest=Guest(@"shared/Second.app");
    CurrentWindow=secondWindow;CurrentGuest=secondGuest;[OptedIn addObject:secondGuest[@"identity"]];[Driver reconcile];
    AVPictureInPictureController *second=[PiPManager shared].pipController;
    Expect(second && second!=first && !first.contentSource && StartCalls==0 && StopCalls==0,@"LC task switch updates preparation without starting PiP");
    Expect(second.contentSource.source==secondWindow.appSceneVC.view,@"task switch arms the new source, not the previous App");
    [oldDelegate pictureInPictureControllerDidStopPictureInPicture:first];
    [Driver finished:first];Expect([PiPManager shared].pipController==second && second.contentSource,@"stale delegate and finished calls cannot erase a new controller");
    [oldDelegate pictureInPictureController:first failedToStartPictureInPictureWithError:[NSError errorWithDomain:@"stale" code:1 userInfo:nil]];
    Expect([PiPManager shared].pipController==second && ![NativeEvents containsObject:@"failed"],@"stale failure cannot restore or clear the new task");

    first=Arm(NO);id source=first.contentSource;
    UIApplication.sharedApplication.applicationState=UIApplicationStateBackground;
    CurrentWindow=Window(NO);CurrentGuest=Guest(@"private/Other.app");[OptedIn addObject:CurrentGuest[@"identity"]];[Driver reconcile];
    Expect([PiPManager shared].pipController==first && first.contentSource==source && StartCalls==0,@"background reconciliation neither manually starts nor retargets PiP");

    for(NSNumber *hosting in @[@NO,@YES]) {
        first=Arm(hosting.boolValue);FixtureScene *scene=CurrentWindow.appSceneVC;
        [first simulateSystemStart];
        Expect(first.active && scene.shouldIgnoreSceneUpdates && scene.contentView.superview!=scene.view,@"system auto-start forwards native content migration");
        Expect([NativeEvents isEqual:@[@"willStart",@"didStart"]] && StartCalls==0,@"automatic flow uses native delegates without manual start");
        CurrentWindow=Window(NO);CurrentGuest=Guest(@"private/Other.app");[OptedIn addObject:CurrentGuest[@"identity"]];[Driver reconcile];
        Expect([PiPManager shared].pipController==first,@"live PiP keeps its original task when another task becomes active");
        [OptedIn removeAllObjects];[Driver reconcile];
        Expect(StopCalls==1 && Restores==1 && !scene.shouldIgnoreSceneUpdates && scene.contentView.superview==scene.view,@"disabling live PiP stops once and restores content through native callbacks");
        Expect([NativeEvents isEqual:@[@"willStart",@"didStart",@"willStop",@"didStop"]] && NativeEmpty() && !first.contentSource,@"native restoration completes before bindings are cleared");
        Expect(PresentationRefreshes==1 && !RefreshSawProtectedContent,@"window presentation refresh occurs after native PiP protection is removed");
    }
    first=Arm(NO);NativeAutoEnd=YES;[first simulateSystemStart];[OptedIn removeAllObjects];[Driver reconcile];
    Expect(Restores==1 && NativeEmpty(),@"native auto-end clearing the controller still permits owned-view cleanup");
    first=Arm(YES);[first simulateSystemStart];Enabled=NO;[Driver reconcile];
    Expect(NativeEmpty() && Restores==1 && PresentationRefreshes==1 && !RefreshSawProtectedContent,@"module disable restores content then refreshes the previously PiP-protected window");

    first=Arm(YES);FixtureScene *deferredScene=CurrentWindow.appSceneVC;
    [first simulateSystemStart];DeferredStop=YES;[OptedIn removeAllObjects];
    [Driver reconcile];[Driver reconcile];[Driver reconcile];
    Expect(StopCalls==1,@"asynchronous stop is requested once across repeated opt-out reconciliation");
    Expect([PiPManager shared].pipController==first && first.contentSource && first.delegate &&
           [PiPManager shared].displayingVC==deferredScene && Restores==0 &&
           deferredScene.contentView.superview!=deferredScene.view && deferredScene.shouldIgnoreSceneUpdates,
           @"pending asynchronous stop retains native bindings and protected content until real didStop");
    [first finishStop];
    Expect(Restores==1 && NativeEmpty() && !first.contentSource &&
           deferredScene.contentView.superview==deferredScene.view && !deferredScene.shouldIgnoreSceneUpdates,
           @"real asynchronous didStop restores once before releasing all native bindings");

    first=Arm(NO);UIApplication.sharedApplication.applicationState=UIApplicationStateBackground;
    [first simulateSystemStart];[first stopPictureInPicture];[Driver reconcile];
    Expect(NativeEmpty() && Creations==1,@"closing PiP while backgrounded never immediately rearms it");
    UIApplication.sharedApplication.applicationState=UIApplicationStateActive;[Driver reconcile];
    Expect([PiPManager shared].pipController && [PiPManager shared].pipController!=first && Creations==2 && StartCalls==0,@"returning to the same opted-in foreground task prepares the next automatic session");

    first=Arm(NO);[first simulateFailureAfterWillStart:NO];
    Expect([NativeEvents isEqual:@[@"failed"]] && Restores==0 && NativeEmpty() && !first.contentSource,@"failure before content movement clears preparation without fake restoration");
    first=Arm(YES);FixtureScene *failedScene=CurrentWindow.appSceneVC;[first simulateFailureAfterWillStart:YES];
    Expect([NativeEvents isEqual:@[@"willStart",@"failed",@"willStop",@"didStop"]] && Restores==1 && failedScene.contentView.superview==failedScene.view,@"failure after content movement restores native content once");
    Expect(NativeEmpty() && !failedScene.shouldIgnoreSceneUpdates,@"failed preparation leaves neither bindings nor geometry protection behind");
    Expect(PresentationRefreshes==1 && !RefreshSawProtectedContent,@"failed moved content is restored before presentation refresh");

    first=Arm(NO);FixtureWindow *oldWindow=CurrentWindow;[OptedIn removeAllObjects];[first simulateSystemStart];
    Expect(!first.active && Restores==0 && NativeEmpty() && oldWindow.appSceneVC.contentView.superview==oldWindow.appSceneVC.view,@"late system start after opt-out is cancelled before content migration");
    first=Arm(NO);CurrentWindow=Window(NO);[first simulateSystemStart];
    Expect(!first.active && NativeEmpty() && Restores==0,@"late system start for a no-longer-active task is cancelled");

    for(NSNumber *active in @[@NO,@YES]) {
        Reset();AVPictureInPictureController *manual=[[AVPictureInPictureController alloc] initWithContentSource:[NSObject new]];
        manual.active=active.boolValue;[PiPManager shared].pipController=manual;
        [OptedIn addObject:CurrentGuest[@"identity"]];NSUInteger count=Creations;[Driver reconcile];[Driver disarm];
        Expect([PiPManager shared].pipController==manual && Creations==count && StopCalls==0,@"LC-owned manual controller is never overwritten or stopped, even idle");
    }
    first=Arm(NO);AVPictureInPictureController *manual=[[AVPictureInPictureController alloc] initWithContentSource:[NSObject new]];
    [PiPManager shared].pipController=manual;[Driver reconcile];
    Expect([PiPManager shared].pipController==manual && !first.contentSource && StopCalls==0,@"external takeover releases only the plugin's old source");

    for(NSString *condition in @[@"disabled",@"builtin",@"guest-absent",@"window-absent",@"dead",@"unsupported",@"windowless",@"hidden",@"zero-size",@"nan-size",@"no-content",@"constructor-failed"]) {
        Reset();[OptedIn addObject:CurrentGuest[@"identity"]];
        if([condition isEqual:@"disabled"])Enabled=NO;
        if([condition isEqual:@"builtin"])CurrentGuest=@{@"identity":@"builtin/SideStore",@"builtin":@YES};
        if([condition isEqual:@"guest-absent"])CurrentGuest=nil;
        if([condition isEqual:@"window-absent"])CurrentWindow=nil;
        if([condition isEqual:@"dead"])CurrentWindow.appSceneVC.running=NO;
        if([condition isEqual:@"unsupported"])Supported=NO;
        if([condition isEqual:@"windowless"])CurrentWindow.appSceneVC.view.window=nil;
        if([condition isEqual:@"hidden"])CurrentWindow.appSceneVC.view.hidden=YES;
        if([condition isEqual:@"zero-size"])CurrentWindow.appSceneVC.view.bounds=CGRectZero;
        if([condition isEqual:@"nan-size"])CurrentWindow.appSceneVC.view.bounds=CGRectMake(0,0,NAN,640);
        if([condition isEqual:@"no-content"])CurrentWindow.appSceneVC.contentView=nil;
        if([condition isEqual:@"constructor-failed"])RejectController=YES;
        [Driver reconcile];Expect(NativeEmpty() && StartCalls==0,[condition stringByAppendingString:@" does not arm or alter LC"]);
    }
    first=Arm(NO);CurrentWindow.appSceneVC.running=NO;[Driver reconcile];
    Expect(!first.contentSource && NativeEmpty(),@"a terminating prepared process is disarmed");
    for(NSString *selector in @[@"pipController",@"displayingVC",@"setPipController:",@"setPipVideoCallContentView:",@"setDisplayingVC:",@"pictureInPictureControllerWillStartPictureInPicture:",@"pictureInPictureControllerDidStopPictureInPicture:"]) {
        Reset();MissingNative=selector;[OptedIn addObject:CurrentGuest[@"identity"]];[Driver reconcile];
        Expect(NativeEmpty() && StartCalls==0,[selector stringByAppendingString:@" missing leaves native state unchanged"]);
    }
    for(NSString *selector in @[@"setDelegate:",@"stopPictureInPicture",@"isPictureInPictureActive",@"setContentSource:",@"setCanStartPictureInPictureAutomaticallyFromInline:"]) {
        Reset();MissingController=selector;[OptedIn addObject:CurrentGuest[@"identity"]];[Driver reconcile];
        Expect(NativeEmpty() && StartCalls==0,[selector stringByAppendingString:@" missing prevents incomplete controller binding"]);
    }
    for(NSString *selector in @[@"setCanStartPictureInPictureAutomaticallyFromInline:",@"isPictureInPictureActive"]) {
        Reset();SEL sel=NSSelectorFromString(selector);
        NSString *className=[@"OrbitIncompatiblePiP_" stringByAppendingString:NSUUID.UUID.UUIDString];
        Class incompatible=objc_allocateClassPair(AVPictureInPictureController.class,className.UTF8String,0);
        BOOL setter=[selector hasPrefix:@"set"];
        BOOL added=class_addMethod(incompatible,sel,setter?(IMP)WrongIntegerSetter:(IMP)WrongObjectGetter,setter?"v@:q":"@@:");
        objc_registerClassPair(incompatible);ControllerSubclass=incompatible;
        [OptedIn addObject:CurrentGuest[@"identity"]];[Driver reconcile];
        Expect(added && NativeEmpty() && StartCalls==0,[selector stringByAppendingString:@" wrong ABI is rejected before native binding"]);
    }
    Reset();[Driver disarm];
    printf("Automatic PiP preparation/lifecycle: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
    return Failures?1:0;
}}
