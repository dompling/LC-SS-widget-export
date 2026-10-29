#import "LCOrbitGuestFullscreenProbe.h"
#import "LCOrbitHost.h"
#import "LCOrbitLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

// Purpose: determine if a player full-screen tap ever requests a new UIWindowScene
// geometry, asks UIKit to re-evaluate supported orientations, or presents a
// fullscreen controller. Only logs metadata; never changes the caller's result.
static IMP OldRequestGeometry, OldOrientationRefresh, OldPresent;
static NSUInteger EventCount;
static NSTimeInterval LastOrientationLog, LastPresentationLog;

static BOOL LiveProcessGuest(void) {
    SEL live=NSSelectorFromString(@"isLiveProcess");
    return [NSUserDefaults respondsToSelector:live] &&
        ((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,live) &&
        [LCOrbitHost guestInfo]!=nil;
}
static void Probe(NSString *name,NSDictionary *details) {
    if(EventCount>=120) return; // Cap in-memory process logs.
    EventCount++;
    NSString *guest=[LCOrbitHost guestIdentifier]?:@"unknown";
    NSMutableDictionary *record=[NSMutableDictionary dictionaryWithDictionary:details?:@{}];
    record[@"guest"]=guest;
    record[@"seq"]=@(EventCount);
    NSLog(@"[LCOrbit FullscreenProbe] %@ %@",name,record);
    [LCOrbitLog appendEvent:[@"guest-fullscreen-" stringByAppendingString:name] details:record kind:@"runtime"];
}
static BOOL HookInstance(Class type,SEL method,IMP replacement,IMP *original,unsigned int expectedArguments) {
    if(!type || !method || !replacement || !original) return NO;
    Method found=class_getInstanceMethod(type,method);
    if(!found || method_getNumberOfArguments(found)!=expectedArguments) return NO;
    char *ret=method_copyReturnType(found);
    BOOL returnsVoid=ret && strcmp(ret,@encode(void))==0;
    free(ret);
    if(!returnsVoid) return NO;
    *original=method_setImplementation(found,replacement);
    return *original!=NULL;
}
static void ProbeRequestGeometry(UIWindowScene *scene,SEL selector,id preferences,void (^onError)(NSError *)) {
    NSString *type=NSStringFromClass([preferences class])?:@"unknown";
    NSUInteger mask=0;
    SEL getter=NSSelectorFromString(@"interfaceOrientations");
    if([preferences respondsToSelector:getter])
        mask=((NSUInteger(*)(id,SEL))objc_msgSend)(preferences,getter);
    Probe(@"geometry-request",@{@"preferences":type,@"orientationMask":@(mask),
        @"sceneOrientation":@(scene.interfaceOrientation)});
    void (^wrapped)(NSError *)=^(NSError *error){
        Probe(@"geometry-error",@{@"domain":error.domain?:@"unknown",@"code":@(error.code),
            @"description":error.localizedDescription.length>240?
                [error.localizedDescription substringToIndex:240]:(error.localizedDescription?:@"")});
        if(onError) onError(error);
    };
    ((void(*)(id,SEL,id,id))OldRequestGeometry)(scene,selector,preferences,wrapped);
}
static void ProbeOrientationRefresh(UIViewController *controller,SEL selector) {
    ((void(*)(id,SEL))OldOrientationRefresh)(controller,selector);
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(now-LastOrientationLog<2.0) return;
    LastOrientationLog=now;
    Probe(@"orientation-refresh",@{@"controller":NSStringFromClass(controller.class)?:@"unknown",
        @"supportedMask":@(controller.supportedInterfaceOrientations)});
}
static void ProbePresent(UIViewController *controller,SEL selector,UIViewController *presented,BOOL animated,void (^completion)(void)) {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(now-LastPresentationLog>=0.75) {
        LastPresentationLog=now;
        Probe(@"present",@{@"controller":NSStringFromClass(controller.class)?:@"unknown",
            @"presented":NSStringFromClass(presented.class)?:@"unknown",
            @"style":@(presented.modalPresentationStyle)});
    }
    ((void(*)(id,SEL,id,BOOL,id))OldPresent)(controller,selector,presented,animated,completion);
}
@implementation LCOrbitGuestFullscreenProbe
+ (void)installIfLiveProcess {
    if(!LiveProcessGuest()) return;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        BOOL geometry=HookInstance(UIWindowScene.class,
            NSSelectorFromString(@"requestGeometryUpdateWithPreferences:errorHandler:"),
            (IMP)ProbeRequestGeometry,&OldRequestGeometry,4);
        BOOL refresh=HookInstance(UIViewController.class,
            @selector(setNeedsUpdateOfSupportedInterfaceOrientations),
            (IMP)ProbeOrientationRefresh,&OldOrientationRefresh,2);
        BOOL present=HookInstance(UIViewController.class,
            @selector(presentViewController:animated:completion:),
            (IMP)ProbePresent,&OldPresent,5);
        Probe(@"probe-loaded",@{@"geometryHook":@(geometry),@"orientationHook":@(refresh),
            @"presentationHook":@(present)});
    });
}
@end
