#import "LCOrbitGuestUIKitDiagnostics.h"
#import "LCOrbitHost.h"
#import "LCOrbitStorage.h"
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
// Reflow is opt-in per Guest. Never move/resize the remote scene and never
// add a second safe-area inset on top of UIKit's already-correct value.
static BOOL GuestRelayoutEnabled=NO;
static BOOL GuestRelayoutPolling=NO;
static __weak UIWindow *GuestRelayoutWindow;
static __weak UIViewController *GuestRelayoutRoot;
static CGFloat GuestRepairedTop=-1;

// LC removes the one-shot "selected" default before shared tweaks load.
// The installed app folder remains available after NSBundle is replaced.
static NSString *GuestInstallPath(void) {
    NSString *name=NSBundle.mainBundle.bundlePath.lastPathComponent;
    return [name isKindOfClass:NSString.class] && [name hasSuffix:@".app"]?name:nil;
}
static NSString *GuestUIKitModeFile(void) {
    NSString *group=[LCOrbitHost appGroupPath];
    return group.length?[[group stringByAppendingPathComponent:@"LiveContainer/LCOrbit"]
        stringByAppendingPathComponent:@"guest-uikit-modes.json"]:nil;
}
static BOOL GuestUIKitModeSelected(void) {
    if(![LCOrbitHost guestInfo]) return NO;
    NSString *path=GuestInstallPath();
    if(!path.length) return NO;
    // A LiveProcess sandbox must not read the host's private Documents.
    // Only opt-in installation names are mirrored into the shared App Group.
    NSString *file=GuestUIKitModeFile();
    struct stat state;
    if(file.length && lstat(file.fileSystemRepresentation,&state)==0 &&
       S_ISREG(state.st_mode) && state.st_size>0 && state.st_size<=65536) {
        NSData *data=[NSData dataWithContentsOfFile:file];
        NSDictionary *doc=data?[NSJSONSerialization JSONObjectWithData:data
            options:0 error:nil]:nil;
        if([doc isKindOfClass:NSDictionary.class] &&
           [doc[@"schemaVersion"] isEqual:@1] &&
           [doc[@"enabledPaths"] isKindOfClass:NSDictionary.class]) {
            id enabled=doc[@"enabledPaths"][path];
            return [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        }
        return NO;
    }
    // Older installations without the mirror can still read a shared host
    // configuration if their container permissions happen to allow it.
    id physical=[LCOrbitStorage objectForKey:
        [@"guestOwnTopInset." stringByAppendingString:path] module:@"LCFloatingMenu"];
    id uikit=[LCOrbitStorage objectForKey:
        [@"uikitTopInset." stringByAppendingString:path] module:@"LCFloatingMenu"];
    return !([physical isKindOfClass:NSNumber.class] && [physical boolValue]) &&
        [uikit isKindOfClass:NSNumber.class] && [uikit boolValue];
}

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
// Diagnostic geometry only: include container and navigation-bar frames even
// when an app uses custom UIView subclasses rather than UILabel / UIControl.
static void GuestTopViews(UIView *view,UIWindow *window,
                          NSMutableArray<NSDictionary *> *views,NSUInteger depth) {
    if(depth>12 || views.count>=24 || view.hidden || view.alpha<.05 ||
       view.bounds.size.width<=0 || view.bounds.size.height<=0) return;
    CGRect frame=[view convertRect:view.bounds toView:window];
    CGRect region=CGRectMake(0,0,window.bounds.size.width,160);
    if(!CGRectIntersectsRect(frame,region)) return;
    BOOL useful=depth>0 && (depth<=3 || CGRectGetHeight(frame)<140 ||
        [view isKindOfClass:UINavigationBar.class] ||
        [view isKindOfClass:UIControl.class]);
    if(useful) [views addObject:@{@"class":NSStringFromClass(view.class),
        @"frame":NSStringFromCGRect(frame),@"depth":@(depth),
        @"safeAreaInsets":NSStringFromUIEdgeInsets(view.safeAreaInsets)}];
    for(UIView *child in view.subviews) {
        if(views.count>=24) break;
        GuestTopViews(child,window,views,depth+1);
    }
}
static NSDictionary *GuestNavigationGeometry(UIWindow *window) {
    UIViewController *root=window.rootViewController;
    UINavigationController *nav=[root isKindOfClass:UINavigationController.class]?
        (UINavigationController *)root:root.navigationController;
    if(!nav) return @{};
    NSMutableDictionary *info=[@{@"navigationClass":NSStringFromClass(nav.class),
        @"navigationBarHidden":@(nav.navigationBarHidden)} mutableCopy];
    UIView *bar=nav.navigationBar;
    if(bar && bar.window==window)
        info[@"navigationBarFrame"]=NSStringFromCGRect([bar convertRect:bar.bounds toView:window]);
    UIViewController *visible=nav.visibleViewController;
    if(visible) {
        info[@"visibleClass"]=NSStringFromClass(visible.class);
        UIView *view=visible.viewIfLoaded;
        if(view && view.window==window) {
            info[@"visibleFrame"]=NSStringFromCGRect([view convertRect:view.bounds toView:window]);
            info[@"visibleSafeInsets"]=NSStringFromUIEdgeInsets(view.safeAreaInsets);
        }
    }
    return info;
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
// A remote scene can be activated with 0pt insets and acquire its real
// Dynamic-Island safe area one UIKit pass later. Some custom navigation
// controllers retain the first geometry. Re-request layout once the Guest's
// OWN UIWindow and root view report a nonzero inset. Never fake insets.
static void GuestSafeAreaRepairTick(void) {
    if(!GuestRelayoutEnabled || !NSThread.isMainThread) return;
    UIApplication *app=UIApplication.sharedApplication;
    if(!app || app.applicationState!=UIApplicationStateActive) return;
    UIWindow *window=GuestVisibleWindow();
    UIViewController *root=window.rootViewController;
    UIView *view=root.viewIfLoaded;
    if(!window || !root || !view || view.window!=window) return;
    UIWindowScene *scene=window.windowScene;
    if(!scene || !UIInterfaceOrientationIsPortrait(scene.interfaceOrientation)) return;
    if(GuestRelayoutWindow!=window || GuestRelayoutRoot!=root) {
        GuestRelayoutWindow=window;GuestRelayoutRoot=root;GuestRepairedTop=-1;
    }
    CGFloat top=window.safeAreaInsets.top;
    CGFloat rootTop=view.safeAreaInsets.top;
    if(!isfinite(top) || !isfinite(rootTop) || top<1 || rootTop<1 ||
       fabs(top-rootTop)>2 || fabs(top-GuestRepairedTop)<.5) return;
    GuestRepairedTop=top;
    __weak UIWindow *weakWindow=window;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *strongWindow=weakWindow;
        if(!strongWindow || strongWindow!=GuestRelayoutWindow ||
           strongWindow.rootViewController!=root || view.window!=strongWindow ||
           fabs(view.safeAreaInsets.top-top)>2) return;
        UINavigationController *nav=[root isKindOfClass:UINavigationController.class]?
            (UINavigationController *)root:root.navigationController;
        UIView *bar=nav.navigationBar;
        UIView *visible=nav.visibleViewController.viewIfLoaded;
        NSDictionary *before=GuestNavigationGeometry(strongWindow);
        [view setNeedsUpdateConstraints];
        [view setNeedsLayout];
        if(bar && bar.window==strongWindow) {
            [bar setNeedsUpdateConstraints];
            [bar setNeedsLayout];
        }
        if(visible && visible.window==strongWindow) {
            [visible setNeedsUpdateConstraints];
            [visible setNeedsLayout];
        }
        [view layoutIfNeeded];
        if([LCOrbitGuestUIKitDiagnostics isEnabled])
            GuestWriteEvent(@"guest-uikit-safe-area-relayout",@{
                @"windowSafeInsets":NSStringFromUIEdgeInsets(strongWindow.safeAreaInsets),
                @"rootSafeInsets":NSStringFromUIEdgeInsets(view.safeAreaInsets),
                @"navigationBefore":before,
                @"navigationAfter":GuestNavigationGeometry(strongWindow)});
    });
}
static void GuestScheduleSafeAreaRepair(void) {
    if(!GuestRelayoutEnabled || GuestRelayoutPolling) return;
    GuestRelayoutPolling=YES;
    // Bounded startup/foreground probes. No permanent timer or global hook.
    NSArray<NSNumber *> *delays=@[@0.0,@0.2,@0.5,@1.0,@1.8,@3.0];
    for(NSUInteger index=0;index<delays.count;index++) {
        NSNumber *delay=delays[index];
        BOOL last=index==delays.count-1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            GuestSafeAreaRepairTick();
            if(last) GuestRelayoutPolling=NO;
        });
    }
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
    NSMutableArray<NSDictionary *> *topViews=[NSMutableArray array];
    if(rootView && rootView.window==window) {
        GuestTopControls(rootView,window,topControls,0);
        GuestTopViews(rootView,window,topViews,0);
    }
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
        @"topViews":topViews,
        @"navigation":GuestNavigationGeometry(window),
        @"uikitRelayoutEnabled":@(GuestRelayoutEnabled),
        @"installPath":GuestInstallPath()?:@"unknown",
        @"orientation":@(scene?scene.interfaceOrientation:0),
        @"statusBarHidden":@(scene?scene.statusBarManager.statusBarHidden:YES),
        @"statusBarFrame":scene?NSStringFromCGRect(scene.statusBarManager.statusBarFrame):@"unknown"
    } mutableCopy];
    if(rootView && rootView.window==window)
        details[@"rootFrameInWindow"]=NSStringFromCGRect([rootView convertRect:rootView.bounds toView:window]);
    GuestWriteEvent(@"guest-uikit-snapshot",details);
}
@implementation LCOrbitGuestUIKitDiagnostics
+ (void)synchronizeUIKitModesToGuests {
    if(![LCOrbitHost isHostUI] || !GuestEnsureDirectory()) return;
    NSDictionary *prefs=[[LCOrbitStorage preferences] dictionaryRepresentation];
    NSString *prefix=@"LCFloatingMenu.uikitTopInset.";
    NSMutableDictionary<NSString *,NSNumber *> *enabled=[NSMutableDictionary dictionary];
    for(id key in prefs) {
        if(![key isKindOfClass:NSString.class] || ![key hasPrefix:prefix]) continue;
        NSString *path=[key substringFromIndex:prefix.length];
        id value=prefs[key];
        if(!path.length || ![path hasSuffix:@".app"] ||
           ![value isKindOfClass:NSNumber.class] || ![value boolValue]) continue;
        id physical=prefs[ [@"LCFloatingMenu.guestOwnTopInset." stringByAppendingString:path] ];
        if(!([physical isKindOfClass:NSNumber.class] && [physical boolValue]))
            enabled[path]=@YES;
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:
        @{@"schemaVersion":@1,@"enabledPaths":enabled}
        options:NSJSONWritingSortedKeys error:nil];
    if(data.length && data.length<=65536)
        [data writeToFile:GuestUIKitModeFile()
            options:NSDataWritingAtomic error:nil];
}
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
    // The repair is gated by this Guest's per-App UIKit selection; independent
    // geometry logging still requires the explicit diagnostic switch.
    SEL selector=NSSelectorFromString(@"isLiveProcess");
    if(![NSUserDefaults respondsToSelector:selector] ||
       !((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,selector)) return;
    GuestRelayoutEnabled=GuestUIKitModeSelected();
    BOOL diagnostics=[self isEnabled];
    if(!GuestRelayoutEnabled && !diagnostics) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(diagnostics) GuestWriteEvent(@"guest-uikit-diagnostic-loaded",
            @{@"status":@"waiting-for-ui",
              @"uikitRelayoutEnabled":@(GuestRelayoutEnabled)});
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
                if(diagnostics) GuestTakeSnapshot(name);
                if(GuestRelayoutEnabled) {
                    // Recheck foreground transitions even if the next app
                    // window reuses its previous UIWindow instance.
                    if([name isEqualToString:UIApplicationWillEnterForegroundNotification])
                        GuestRepairedTop=-1;
                    GuestScheduleSafeAreaRepair();
                }
            }];
        if(GuestRelayoutEnabled) GuestScheduleSafeAreaRepair();
        if(diagnostics) for(NSNumber *delay in @[@1.0,@3.0,@6.0])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),
                           dispatch_get_main_queue(),^{
                GuestTakeSnapshot([NSString stringWithFormat:@"startup+%.1fs",delay.doubleValue]);
            });
    });
}
@end
