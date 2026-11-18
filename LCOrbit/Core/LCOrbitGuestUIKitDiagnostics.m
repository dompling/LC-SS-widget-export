#import "LCOrbitGuestUIKitDiagnostics.h"
#import "LCOrbitHost.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>

// An opt-in diagnostic, isolated from the normal host/menu lifecycle.
// All output is geometry and UIView types. Never store texts, screenshots,
// image data, URL contents, view descriptions, or interaction payloads.
static const NSUInteger GuestLogLimit=131072;
static NSUInteger GuestSamples=0;

static NSString *GuestDiagnosticDirectory(void) {
    NSString *group=[LCOrbitHost appGroupPath];
    return group.length?[group stringByAppendingPathComponent:@"LiveContainer/LCOrbit"]:nil;
}
static NSString *GuestDiagnosticPath(void) {
    return [GuestDiagnosticDirectory() stringByAppendingPathComponent:@"GuestUIKit-runtime.json"];
}
static NSString *GuestDiagnosticEnablePath(void) {
    return [GuestDiagnosticDirectory() stringByAppendingPathComponent:@"guest-uikit.enabled"];
}
static BOOL GuestIsRegularFile(NSString *path) {
    struct stat state;
    return path.length && lstat(path.fileSystemRepresentation,&state)==0 &&
        S_ISREG(state.st_mode);
}
static BOOL GuestEnsureDirectory(void) {
    NSString *directory=GuestDiagnosticDirectory();
    if(!directory.length ||
       ![NSFileManager.defaultManager createDirectoryAtPath:directory
              withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    struct stat state;
    return lstat(directory.fileSystemRepresentation,&state)==0 && S_ISDIR(state.st_mode);
}
static int GuestLockFile(void) {
    if(!GuestEnsureDirectory()) return -1;
    NSString *path=[GuestDiagnosticPath() stringByAppendingString:@".lock"];
    int fd=open(path.fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(fd<0) return -1;
    if(flock(fd,LOCK_EX)!=0) {close(fd);return -1;}
    return fd;
}
static void GuestUnlockFile(int fd) {flock(fd,LOCK_UN);close(fd);}
static NSArray<NSDictionary *> *GuestReadEvents(void) {
    NSString *path=GuestDiagnosticPath();
    if(!GuestIsRegularFile(path)) return @[];
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if([attrs fileSize]>GuestLogLimit) return @[];
    NSData *data=[NSData dataWithContentsOfFile:path];
    NSDictionary *payload=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![payload isKindOfClass:NSDictionary.class] ||
       ![payload[@"schemaVersion"] isEqual:@1] ||
       ![payload[@"events"] isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary *> *valid=[NSMutableArray array];
    for(id item in payload[@"events"]) {
        if(![item isKindOfClass:NSDictionary.class] ||
           ![item[@"event"] isKindOfClass:NSString.class] ||
           ![item[@"timestamp"] isKindOfClass:NSString.class]) continue;
        [valid addObject:item];
    }
    return valid;
}
static NSData *GuestEncode(NSArray<NSDictionary *> *events) {
    return [NSJSONSerialization dataWithJSONObject:@{@"schemaVersion":@1,@"events":events}
        options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
}
static void GuestWriteEvent(NSString *name,NSDictionary *details) {
    if(![LCOrbitGuestUIKitDiagnostics isEnabled]) return;
    int lock=GuestLockFile();if(lock<0) return;
    @try {
        NSISO8601DateFormatter *formatter=[NSISO8601DateFormatter new];
        NSDictionary *info=[LCOrbitHost guestInfo];
        NSString *container=[info[@"LCDataUUID"] isKindOfClass:NSString.class]?
            info[@"LCDataUUID"]:@"unknown";
        NSDictionary *event=@{@"timestamp":[formatter stringFromDate:NSDate.date],
            @"event":name,@"context":@"guest-liveprocess",
            @"guestID":[LCOrbitHost guestIdentifier]?:@"unknown",
            @"guestContainer":container,@"pid":@(getpid()),
            @"details":details?:@{}};
        NSMutableArray *events=[GuestReadEvents() mutableCopy];
        [events addObject:event];
        // Favor the most recent samples; keep this export small even when
        // several Guest processes are running.
        NSData *encoded=GuestEncode(events);
        while(events.count>1 && (events.count>48 || encoded.length>GuestLogLimit)) {
            [events removeObjectAtIndex:0];
            encoded=GuestEncode(events);
        }
        if(encoded.length<=GuestLogLimit)
            [encoded writeToFile:GuestDiagnosticPath() options:NSDataWritingAtomic error:nil];
    } @finally {GuestUnlockFile(lock);}
}

// Read only onscreen UIKit controls, never the value of any control or label.
static void GuestTopControls(UIView *view,UIWindow *window,
                            NSMutableArray<NSDictionary *> *controls,
                            NSUInteger depth) {
    if(depth>8 || controls.count>=8 || view.hidden || view.alpha<.05) return;
    if(view!=window && (view.bounds.size.width<=0 || view.bounds.size.height<=0)) return;
    BOOL relevant=[view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class];
    if(relevant) {
        CGRect frame=[view convertRect:view.bounds toView:window];
        CGRect region=CGRectMake(0,0,window.bounds.size.width,160);
        if(CGRectIntersectsRect(frame,region)) {
            [controls addObject:@{@"class":NSStringFromClass(view.class),
                @"frame":NSStringFromCGRect(frame),
                @"safeAreaInsets":NSStringFromUIEdgeInsets(view.safeAreaInsets)}];
        }
    }
    for(UIView *child in view.subviews) {
        if(controls.count>=8) break;
        GuestTopControls(child,window,controls,depth+1);
    }
}
static UIWindow *GuestVisibleWindow(void) {
    UIApplication *app=UIApplication.sharedApplication;
    if(!app) return nil;
    if(@available(iOS 13.0,*)) {
        for(UIScene *scene in app.connectedScenes) {
            if(![scene isKindOfClass:UIWindowScene.class]) continue;
            for(UIWindow *window in ((UIWindowScene *)scene).windows)
                if(!window.hidden && window.alpha>.05 &&
                   window.windowLevel==UIWindowLevelNormal && window.rootViewController &&
                   window.bounds.size.width>40 && window.bounds.size.height>40) return window;
        }
    }
    for(UIWindow *window in app.windows)
        if(!window.hidden && window.alpha>.05 &&
           window.windowLevel==UIWindowLevelNormal && window.rootViewController &&
           window.bounds.size.width>40 && window.bounds.size.height>40) return window;
    return nil;
}
static void GuestTakeSnapshot(NSString *reason) {
    if(!NSThread.isMainThread || ![LCOrbitGuestUIKitDiagnostics isEnabled] ||
       ![LCOrbitHost guestInfo] || GuestSamples>=12) return;
    GuestSamples++;
    UIWindow *window=GuestVisibleWindow();
    if(!window) {
        GuestWriteEvent(@"guest-uikit-snapshot",@{@"reason":reason?:@"unknown",
            @"windowReady":@NO,@"sample":@(GuestSamples)});
        return;
    }
    UIViewController *root=window.rootViewController;
    UIView *rootView=root.viewIfLoaded;
    UIWindowScene *scene=window.windowScene;
    NSMutableArray<NSDictionary *> *topControls=[NSMutableArray array];
    if(rootView && rootView.window==window)
        GuestTopControls(rootView,window,topControls,0);
    NSMutableDictionary *details=[@{
        @"reason":reason?:@"unknown",@"sample":@(GuestSamples),
        @"windowReady":@YES,
        @"windowClass":NSStringFromClass(window.class),
        @"windowFrame":NSStringFromCGRect(window.frame),
        @"windowBounds":NSStringFromCGRect(window.bounds),
        @"windowSafeInsets":NSStringFromUIEdgeInsets(window.safeAreaInsets),
        @"windowSafeRect":NSStringFromCGRect(window.safeAreaLayoutGuide.layoutFrame),
        @"rootClass":root?NSStringFromClass(root.class):@"none",
        @"rootViewClass":rootView?NSStringFromClass(rootView.class):@"none",
        @"rootSafeInsets":rootView?NSStringFromUIEdgeInsets(rootView.safeAreaInsets):@"unloaded",
        @"rootSafeRect":rootView?NSStringFromCGRect(rootView.safeAreaLayoutGuide.layoutFrame):@"unloaded",
        @"topControls":topControls,
        @"orientation":@(scene?scene.interfaceOrientation:0),
        @"statusBarHidden":@(scene?scene.statusBarManager.statusBarHidden:YES),
        @"statusBarFrame":scene?NSStringFromCGRect(scene.statusBarManager.statusBarFrame):@"unknown"
    } mutableCopy];
    if(rootView && rootView.window==window)
        details[@"rootFrameInWindow"]=NSStringFromCGRect([rootView convertRect:rootView.bounds toView:window]);
    GuestWriteEvent(@"guest-uikit-snapshot",details);
}
@implementation LCOrbitGuestUIKitDiagnostics
+ (BOOL)isEnabled {
    return GuestIsRegularFile(GuestDiagnosticEnablePath());
}
+ (void)setEnabled:(BOOL)enabled {
    if(![LCOrbitHost isHostUI] || !GuestEnsureDirectory()) return;
    NSString *path=GuestDiagnosticEnablePath();
    if(enabled) {
        int lock=GuestLockFile();
        if(lock>=0) {
            @try {
                [GuestEncode(@[]) writeToFile:GuestDiagnosticPath()
                    options:NSDataWritingAtomic error:nil];
            } @finally {GuestUnlockFile(lock);}
        }
        [@"enabled" writeToFile:path atomically:YES
                     encoding:NSUTF8StringEncoding error:nil];
    } else {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
}
+ (NSArray<NSDictionary *> *)events {
    int lock=GuestLockFile();
    if(lock<0) return @[];
    NSArray *result=nil;
    @try {result=GuestReadEvents();}
    @finally {GuestUnlockFile(lock);}
    return result?:@[];
}
+ (void)startInLiveProcess {
    // LiveProcess intentionally never starts LCOrbitCore / FloatingMenu.
    // Only geometry diagnostics run here, and ONLY after explicit opt-in.
    SEL selector=NSSelectorFromString(@"isLiveProcess");
    if(![NSUserDefaults respondsToSelector:selector] ||
       !((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,selector) ||
       ![self isEnabled]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        GuestWriteEvent(@"guest-uikit-diagnostic-loaded",@{@"status":@"waiting-for-ui"});
        NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
        NSArray<NSString *> *notifications=@[
            UIApplicationDidBecomeActiveNotification,
            UIApplicationWillEnterForegroundNotification,
            UISceneDidActivateNotification,
            UIWindowDidBecomeVisibleNotification,
            @"UIApplicationDidChangeStatusBarOrientationNotification"
        ];
        for(NSString *name in notifications)
            [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                            usingBlock:^(NSNotification *notification) {
                GuestTakeSnapshot(name);
            }];
        // The first UIKit scene may appear after TweakLoader. Sample without
        // forcing UIKit layout or intercepting any of the Guest's callbacks.
        for(NSNumber *delay in @[@1.0,@3.0,@6.0])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),
                           dispatch_get_main_queue(),^{
                GuestTakeSnapshot([NSString stringWithFormat:@"startup+%.1fs",delay.doubleValue]);
            });
    });
}
@end
