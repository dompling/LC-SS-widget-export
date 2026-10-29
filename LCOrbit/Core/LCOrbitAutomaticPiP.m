#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <math.h>
#import "LCOrbitMultitask.h"
#import "LCOrbitLog.h"

// Prepare AVKit in the foreground. AVKit, rather than a delayed background
// start call, decides when the opted-in task enters Picture in Picture.
static char PiPType(const char *type) {
    while(type && *type && strchr("rnNoORV",*type)) type++;
    return type?*type:0;
}
static BOOL PiPTypeMatches(char actual,char expected) {
    if(expected=='@') return actual=='@' || actual=='#';
    if(expected=='B') return actual=='B' || actual=='c';
    return actual==expected;
}
static BOOL PiPSignature(NSMethodSignature *signature,char result,const char *arguments) {
    NSUInteger count=strlen(arguments);
    if(!signature || signature.numberOfArguments!=count+2 ||
       !PiPTypeMatches(PiPType(signature.methodReturnType),result)) return NO;
    for(NSUInteger i=0;i<count;i++)
        if(!PiPTypeMatches(PiPType([signature getArgumentTypeAtIndex:i+2]),arguments[i])) return NO;
    return YES;
}
static BOOL PiPMethod(id target,NSString *name,char result,const char *arguments) {
    SEL selector=NSSelectorFromString(name);
    return [target respondsToSelector:selector] &&
        PiPSignature([target methodSignatureForSelector:selector],result,arguments);
}
static id PiPCall(id target,NSString *name) {
    SEL sel=NSSelectorFromString(name);
    return PiPMethod(target,name,'@',"")?((id(*)(id,SEL))objc_msgSend)(target,sel):nil;
}
static BOOL PiPFlag(id target,NSString *name) {
    SEL sel=NSSelectorFromString(name);
    return PiPMethod(target,name,'B',"") && ((BOOL(*)(id,SEL))objc_msgSend)(target,sel);
}
static void PiPObject(id target,NSString *name,id value) {
    SEL sel=NSSelectorFromString(name);
    if(PiPMethod(target,name,'v',"@")) ((void(*)(id,SEL,id))objc_msgSend)(target,sel,value);
}
static void PiPBoolean(id target,NSString *name,BOOL value) {
    SEL sel=NSSelectorFromString(name);
    if(PiPMethod(target,name,'v',"B")) ((void(*)(id,SEL,BOOL))objc_msgSend)(target,sel,value);
}
static void PiPVoid(id target,NSString *name) {
    SEL sel=NSSelectorFromString(name);
    if(PiPMethod(target,name,'v',"")) ((void(*)(id,SEL))objc_msgSend)(target,sel);
}
static void PiPLog(NSString *event,id details) { [LCOrbitLog appendEvent:event details:details kind:@"runtime"]; }
typedef id (*PiPSourceInitializer)(id __attribute__((ns_consumed)),SEL,id,id) __attribute__((ns_returns_retained));
typedef id (*PiPControllerInitializer)(id __attribute__((ns_consumed)),SEL,id) __attribute__((ns_returns_retained));

@class LCOrbitAutomaticPiP;
@interface LCOrbitAutomaticPiPDelegate : NSObject
@property(nonatomic,weak) LCOrbitAutomaticPiP *owner;
@property(nonatomic,weak) id manager;
@property(nonatomic) BOOL contentMoved;
@end

@interface LCOrbitAutomaticPiP : NSObject
@property(nonatomic,strong) id controller;
@property(nonatomic,strong) LCOrbitAutomaticPiPDelegate *forwarder;
@property(nonatomic,weak) id manager;
@property(nonatomic,weak) id scene;
@property(nonatomic,weak) id window;
@property(nonatomic,copy) NSDictionary *guest;
@property(nonatomic,strong) NSMutableArray *observers;
@property(nonatomic) BOOL refreshPending,transitioning,cancelRequested,stopRequested;
+ (void)refresh;
- (void)reconcile;
- (void)disarm;
- (void)finished:(id)controller;
- (BOOL)owns:(id)controller;
- (BOOL)allowed;
@end

@implementation LCOrbitAutomaticPiPDelegate
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.manager respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    return [self.manager respondsToSelector:selector]?self.manager:[super forwardingTargetForSelector:selector];
}
- (void)pictureInPictureControllerWillStartPictureInPicture:(id)controller {
    if(![self.owner owns:controller]) return;
    self.owner.transitioning=YES;
    if(![self.owner allowed] || [LCOrbitMultitask activeWindow]!=self.owner.window) {
        self.owner.cancelRequested=YES;
        self.owner.stopRequested=YES;
        PiPVoid(controller,@"stopPictureInPicture");
        return;
    }
    self.contentMoved=YES;
    PiPObject(self.manager,NSStringFromSelector(_cmd),controller);
    PiPLog(@"auto-pip-starting",self.owner.guest[@"identity"]);
}
- (void)pictureInPictureControllerDidStartPictureInPicture:(id)controller {
    if(![self.owner owns:controller]) return;
    self.owner.transitioning=NO;
    self.owner.stopRequested=NO;
    PiPObject(self.manager,NSStringFromSelector(_cmd),controller);
    if(self.owner.cancelRequested || ![self.owner allowed]) [self.owner disarm];
}
- (void)pictureInPictureControllerWillStopPictureInPicture:(id)controller {
    if(![self.owner owns:controller]) return;
    self.owner.transitioning=YES;
    self.owner.stopRequested=YES;
    if(self.contentMoved) PiPObject(self.manager,NSStringFromSelector(_cmd),controller);
}
- (void)pictureInPictureControllerDidStopPictureInPicture:(id)controller {
    LCOrbitAutomaticPiP *owner=self.owner;
    if(![owner owns:controller]) return;
    if(self.contentMoved) PiPObject(self.manager,NSStringFromSelector(_cmd),controller);
    [owner finished:controller];
    if(self.contentMoved && [LCOrbitMultitask respondsToSelector:@selector(refreshPresentation)])
        [LCOrbitMultitask refreshPresentation];
    PiPLog(@"auto-pip-stopped",nil);
    [LCOrbitAutomaticPiP refresh];
}
- (void)pictureInPictureController:(id)controller failedToStartPictureInPictureWithError:(NSError *)error {
    LCOrbitAutomaticPiP *owner=self.owner;
    if(![owner owns:controller]) return;
    SEL failed=NSSelectorFromString(@"pictureInPictureController:failedToStartPictureInPictureWithError:");
    if(PiPMethod(self.manager,NSStringFromSelector(failed),'v',"@@"))
        ((void(*)(id,SEL,id,id))objc_msgSend)(self.manager,failed,controller,error);
    if(self.contentMoved) {
        PiPObject(self.manager,@"pictureInPictureControllerWillStopPictureInPicture:",controller);
        PiPObject(self.manager,@"pictureInPictureControllerDidStopPictureInPicture:",controller);
    }
    [owner finished:controller];
    if(self.contentMoved && [LCOrbitMultitask respondsToSelector:@selector(refreshPresentation)])
        [LCOrbitMultitask refreshPresentation];
    PiPLog(@"auto-pip-failed",error.localizedDescription?:@"unknown");
}
@end

@implementation LCOrbitAutomaticPiP
+ (instancetype)shared {
    static LCOrbitAutomaticPiP *instance;
    static dispatch_once_t once;
    dispatch_once(&once,^{instance=[self new];});
    return instance;
}
- (instancetype)init {
    if((self=[super init])) {
        _observers=[NSMutableArray array];
        __weak typeof(self) weakSelf=self;
        for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UIApplicationDidEnterBackgroundNotification,
                                UISceneDidActivateNotification,UIWindowDidBecomeVisibleNotification,
                                LCOrbitMultitaskConfigurationChangedNotification,
                                LCOrbitMultitaskMenuRequestedNotification]) {
            id token=[NSNotificationCenter.defaultCenter addObserverForName:name object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    (void)note;
                    if(weakSelf) [LCOrbitAutomaticPiP refresh];
                }];
            [_observers addObject:token];
        }
    }
    return self;
}
+ (void)refresh {
    if(!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{[self refresh];});return; }
    LCOrbitAutomaticPiP *instance=[self shared];
    if(instance.refreshPending) return;
    instance.refreshPending=YES;
    dispatch_async(dispatch_get_main_queue(),^{
        instance.refreshPending=NO;
        [instance reconcile];
    });
}
- (BOOL)owns:(id)controller {
    return controller && self.controller==controller && PiPCall(self.manager,@"pipController")==controller;
}
- (BOOL)allowed {
    return [LCOrbitMultitask isEnabled] && [LCOrbitMultitask automaticPiPEnabledForGuest:self.guest] &&
        self.window && PiPFlag(self.scene,@"isAppRunning");
}
- (void)finished:(id)controller {
    if(self.controller!=controller) return;
    id current=PiPCall(self.manager,@"pipController");
    PiPBoolean(controller,@"setCanStartPictureInPictureAutomaticallyFromInline:",NO);
    PiPObject(controller,@"setContentSource:",nil);
    PiPObject(controller,@"setDelegate:",nil);
    if(current==controller || (!current && PiPCall(self.manager,@"displayingVC")==self.scene)) {
        PiPObject(self.manager,@"setPipController:",nil);
        PiPObject(self.manager,@"setPipVideoCallContentView:",nil);
        PiPObject(self.manager,@"setPipVideoCallViewController:",nil);
        PiPObject(self.manager,@"setDisplayingVC:",nil);
    }
    self.controller=nil;self.forwarder=nil;self.guest=nil;
    self.window=nil;self.scene=nil;self.manager=nil;
    self.transitioning=NO;self.cancelRequested=NO;self.stopRequested=NO;
}
- (void)disarm {
    id controller=self.controller;
    if(!controller) return;
    PiPBoolean(controller,@"setCanStartPictureInPictureAutomaticallyFromInline:",NO);
    if([self owns:controller] && (self.transitioning || PiPFlag(controller,@"isPictureInPictureActive"))) {
        self.cancelRequested=YES;
        if(self.stopRequested) return;
        self.stopRequested=YES;
        PiPVoid(controller,@"stopPictureInPicture");
    } else [self finished:controller];
}
- (void)reconcile {
    if(self.controller && ![self owns:self.controller]) [self finished:self.controller];
    if(self.controller && ![self allowed]) { [self disarm];return; }
    // Active PiP keeps its original task until stopped. Never replace a live
    // controller just because another LC task becomes foreground.
    if(self.controller && (self.transitioning || PiPFlag(self.controller,@"isPictureInPictureActive"))) return;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    NSDictionary *guest=[LCOrbitMultitask activeGuestForAutomaticPiP];
    id window=[LCOrbitMultitask activeWindow];
    if(!guest || ![LCOrbitMultitask automaticPiPEnabledForGuest:guest]) { [self disarm];return; }
    if(self.controller && self.window==window && [self.guest[@"identity"] isEqual:guest[@"identity"]]) return;
    [self disarm];
    if(self.controller) return;
    Class controllerClass=NSClassFromString(@"AVPictureInPictureController");
    Class sourceClass=NSClassFromString(@"AVPictureInPictureControllerContentSource");
    Class videoClass=NSClassFromString(@"AVPictureInPictureVideoCallViewController");
    Class managerClass=NSClassFromString(@"PiPManager");
    if(!controllerClass || !sourceClass || !videoClass || !PiPFlag(controllerClass,@"isPictureInPictureSupported")) return;
    id manager=PiPCall(managerClass,@"shared");
    // A manually created LC controller remains owned by LC, even when idle.
    if(!manager || PiPCall(manager,@"pipController")) return;
    for(NSString *name in @[@"pipController",@"pipVideoCallContentView",@"pipVideoCallViewController",@"displayingVC"])
        if(!PiPMethod(manager,name,'@',"")) { PiPLog(@"auto-pip-unavailable",name);return; }
    for(NSString *name in @[@"setPipController:",@"setPipVideoCallContentView:",
                            @"setPipVideoCallViewController:",@"setDisplayingVC:",
                            @"pictureInPictureControllerWillStartPictureInPicture:",
                            @"pictureInPictureControllerWillStopPictureInPicture:",
                            @"pictureInPictureControllerDidStopPictureInPicture:"]) {
        if(!PiPMethod(manager,name,'v',"@")) {
            PiPLog(@"auto-pip-unavailable",name);return;
        }
    }
    id scene=PiPCall(window,@"appSceneVC");
    UIView *source=PiPCall(scene,@"view");
    UIView *content=PiPCall(scene,@"contentView");
    CGSize size=source.bounds.size;
    if(!content || !source.window || source.hidden || !isfinite(size.width) || !isfinite(size.height) ||
       size.width<=0 || size.height<=0) return;
    UIViewController *video=[videoClass new];
    video.preferredContentSize=size;
    UIView *target=content;
    if(PiPFlag(scene,@"usesHostingControllerAPI")) {
        target=[[UIView alloc] initWithFrame:video.view.bounds];
        target.layer.anchorPoint=CGPointZero;
        target.layer.position=CGPointZero;
        [video.view addSubview:target];
    }
    SEL sourceInit=NSSelectorFromString(@"initWithActiveVideoCallSourceView:contentViewController:");
    SEL controllerInit=NSSelectorFromString(@"initWithContentSource:");
    if(!PiPSignature([sourceClass instanceMethodSignatureForSelector:sourceInit],'@',"@@") ||
       !PiPSignature([controllerClass instanceMethodSignatureForSelector:controllerInit],'@',"@")) return;
    id contentSource=((PiPSourceInitializer)objc_msgSend)([sourceClass alloc],sourceInit,source,video);
    id controller=((PiPControllerInitializer)objc_msgSend)([controllerClass alloc],controllerInit,contentSource);
    if(!controller || !PiPMethod(controller,@"setCanStartPictureInPictureAutomaticallyFromInline:",'v',"B") ||
       !PiPMethod(controller,@"setContentSource:",'v',"@") || !PiPMethod(controller,@"setDelegate:",'v',"@") ||
       !PiPMethod(controller,@"isPictureInPictureActive",'B',"") || !PiPMethod(controller,@"stopPictureInPicture",'v',"")) return;
    // Match LC's manual video-call PiP controls so AVKit can expose its
    // system close/restore affordances. This is an undocumented setting:
    // never make PiP preparation fail if iOS stops accepting it.
    @try { [controller setValue:@1 forKey:@"controlsStyle"]; }
    @catch(NSException *exception) { PiPLog(@"auto-pip-controls-unavailable",exception.name); }
    LCOrbitAutomaticPiPDelegate *forwarder=[LCOrbitAutomaticPiPDelegate new];
    forwarder.owner=self;forwarder.manager=manager;
    PiPObject(controller,@"setDelegate:",forwarder);
    PiPObject(manager,@"setDisplayingVC:",scene);
    PiPObject(manager,@"setPipVideoCallViewController:",video);
    PiPObject(manager,@"setPipVideoCallContentView:",target);
    PiPObject(manager,@"setPipController:",controller);
    self.controller=controller;self.manager=manager;self.forwarder=forwarder;
    self.scene=scene;self.window=window;self.guest=guest;
    PiPBoolean(controller,@"setCanStartPictureInPictureAutomaticallyFromInline:",YES);
    PiPLog(@"auto-pip-armed",guest[@"identity"]);
}
@end
