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

// Per-Guest, per-visible-view corrections. Keep weak references so navigation
// transitions can discard their views. The original transforms are restored
// on rotation, replacement, or when UIKit itself starts honoring safe areas.
@interface LCOrbitTopSurfaceOffset : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic,assign) CGFloat applied;
@end
@implementation LCOrbitTopSurfaceOffset
@end
static LCOrbitTopSurfaceOffset *GuestHeaderOffset;
static LCOrbitTopSurfaceOffset *GuestNavigationOffset;
static LCOrbitTopSurfaceOffset *GuestInstagramHeaderOffset;
// Per-visible-controller workaround for a 44pt nav bar that sits below the
// system safe top, while UIKit still reports only the 59pt system inset.
@interface LCOrbitBaiduContentSafeState : NSObject
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,assign) CGFloat originalTop;
@property(nonatomic,assign) CGFloat addedTop;
@end
@implementation LCOrbitBaiduContentSafeState
@end
static LCOrbitBaiduContentSafeState *GuestBaiduContentSafe;
static NSTimer *GuestBaiduContentWatchTimer;
@interface LCOrbitInstagramInsetState : NSObject
@property(nonatomic,weak) UIScrollView *scroll;
@property(nonatomic,assign) CGFloat originalTop;
@property(nonatomic,assign) CGFloat appliedTop;
@property(nonatomic,assign) CGFloat originalOffsetY;
@property(nonatomic,weak) UIView *header;
@end
@implementation LCOrbitInstagramInsetState
@end
static LCOrbitInstagramInsetState *GuestInstagramInset;
static BOOL GuestInstagramNoScrollReported=NO;
// Instagram can recreate its header/inset on pull-to-refresh after the bounded
// startup repair. Observe only this opted-in Guest, never all hosted apps.
static NSTimer *GuestInstagramWatchTimer;


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
        info[@"visibleAdditionalSafeInsets"]=NSStringFromUIEdgeInsets(visible.additionalSafeAreaInsets);
        if([visible isKindOfClass:UITabBarController.class]) {
            UIViewController *selected=((UITabBarController *)visible).selectedViewController;
            if(selected) {
                info[@"selectedClass"]=NSStringFromClass(selected.class);
                UIView *selectedView=selected.viewIfLoaded;
                if(selectedView && selectedView.window==window) {
                    info[@"selectedFrame"]=NSStringFromCGRect(
                        [selectedView convertRect:selectedView.bounds toView:window]);
                    info[@"selectedSafeInsets"]=NSStringFromUIEdgeInsets(selectedView.safeAreaInsets);
                }
            }
        }
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
// Baidu's custom tab/header is absolutely positioned at y=0 even though its
// UIWindow and child views report a 59pt safe top. Changing the whole scene
// compresses content; only correct these observed top-only surfaces.
static BOOL GuestIsBaiduTopRepair(UIViewController *root) {
    return GuestRelayoutEnabled &&
        [GuestInstallPath() isEqualToString:@"com.bd.iphone.super.app"] &&
        [root isKindOfClass:UINavigationController.class] &&
        [NSStringFromClass(root.class) isEqualToString:@"BDSNavigationController"];
}
static void GuestRestoreTopSurface(LCOrbitTopSurfaceOffset *__strong *slot) {
    LCOrbitTopSurfaceOffset *saved=*slot;
    UIView *view=saved.view;
    if(view && CGAffineTransformEqualToTransform(view.transform,
           CGAffineTransformMakeTranslation(0,saved.applied))) {
        [UIView performWithoutAnimation:^{view.transform=CGAffineTransformIdentity;}];
    }
    *slot=nil;
}
static void GuestRestoreBaiduContentSafeArea(void) {
    LCOrbitBaiduContentSafeState *saved=GuestBaiduContentSafe;
    GuestBaiduContentSafe=nil;
    UIViewController *controller=saved.controller;
    if(!controller) return;
    UIEdgeInsets extra=controller.additionalSafeAreaInsets;
    if(fabs(extra.top-(saved.originalTop+saved.addedTop))>.75) return;
    extra.top=saved.originalTop;
    [UIView performWithoutAnimation:^{
        controller.additionalSafeAreaInsets=extra;
        [controller.viewIfLoaded setNeedsLayout];
    }];
}
static void GuestRestoreBaiduSurfaces(void) {
    GuestRestoreTopSurface(&GuestHeaderOffset);
    GuestRestoreTopSurface(&GuestNavigationOffset);
    GuestRestoreBaiduContentSafeArea();
}
static UIView *GuestFindBaiduSlideMenu(UIView *node,UIWindow *window,
                                       NSUInteger depth,NSUInteger *visited) {
    if(!node || depth>17 || ++(*visited)>900 || node.hidden ||
       node.alpha<.05 || node.window!=window) return nil;
    if([NSStringFromClass(node.class) isEqualToString:@"BDSSlideMenuMain"])
        return node;
    for(UIView *child in node.subviews) {
        UIView *found=GuestFindBaiduSlideMenu(child,window,depth+1,visited);
        if(found) return found;
    }
    return nil;
}
static UIView *GuestBaiduHeaderContainer(UIView *menu,UIView *root,UIWindow *window) {
    // Reuse the same corrected ancestor after its visual frame moves to y=59.
    UIView *saved=GuestHeaderOffset.view;
    for(UIView *node=menu;node && node!=root;node=node.superview)
        if(node==saved) return saved;
    UIView *best=nil;
    for(UIView *node=menu;node && node!=root;node=node.superview) {
        CGRect frame=[node convertRect:node.bounds toView:window];
        if(CGRectGetHeight(frame)>=30 && CGRectGetHeight(frame)<=85 &&
           CGRectGetWidth(frame)>=window.bounds.size.width*.85 &&
           fabs(CGRectGetMinY(frame))<=5) best=node;
    }
    return best;
}
static NSDictionary *GuestCorrectTopSurface(UIView *surface,UIWindow *window,
                                             CGFloat top,NSString *name,
                                             LCOrbitTopSurfaceOffset *__strong *slot) {
    if((*slot).view!=surface) GuestRestoreTopSurface(slot);
    if(!surface || surface.window!=window) {
        GuestRestoreTopSurface(slot);
        return nil;
    }
    LCOrbitTopSurfaceOffset *saved=*slot;
    CGAffineTransform expected=saved?
        CGAffineTransformMakeTranslation(0,saved.applied):CGAffineTransformIdentity;
    // Never overwrite transforms owned by app transitions/animations.
    if(!CGAffineTransformEqualToTransform(surface.transform,expected)) {
        *slot=nil;
        return nil;
    }
    CGRect before=[surface convertRect:surface.bounds toView:window];
    CGFloat baseY=CGRectGetMinY(before)-(saved?saved.applied:0);
    // Correct only full-width top strips (44/48pt), not the body of the app.
    BOOL eligible=isfinite(top) && top>=30 && top<=90 && isfinite(baseY) &&
        baseY>=-5 && baseY<=MIN(22,top*.4) &&
        CGRectGetHeight(before)>=30 && CGRectGetHeight(before)<=85 &&
        CGRectGetWidth(before)>=window.bounds.size.width*.85;
    if(!eligible) {
        GuestRestoreTopSurface(slot);
        return nil;
    }
    CGFloat offset=top-baseY;
    if(saved && fabs(saved.applied-offset)<.5) return nil;
    if(!saved) {
        saved=[LCOrbitTopSurfaceOffset new];
        saved.view=surface;
        *slot=saved;
    }
    saved.applied=offset;
    [UIView performWithoutAnimation:^{
        surface.transform=CGAffineTransformMakeTranslation(0,offset);
    }];
    return @{@"component":name,@"safeTop":@(top),@"offset":@(offset),
        @"before":NSStringFromCGRect(before),
        @"after":NSStringFromCGRect([surface convertRect:surface.bounds toView:window]),
        @"class":NSStringFromClass(surface.class)};
}
static void GuestRepairBaiduTopSurfaces(UIWindow *window,
                                       UIViewController *root,CGFloat top) {
    if(!GuestIsBaiduTopRepair(root)) {
        GuestRestoreBaiduSurfaces();
        return;
    }
    NSUInteger visited=0;
    UIView *menu=GuestFindBaiduSlideMenu(root.viewIfLoaded,window,0,&visited);
    UIView *header=menu?GuestBaiduHeaderContainer(menu,root.viewIfLoaded,window):nil;
    UINavigationBar *bar=((UINavigationController *)root).navigationBar;
    if(bar.window!=window || bar.hidden ||
       ((UINavigationController *)root).navigationBarHidden) bar=nil;
    NSMutableArray *changes=[NSMutableArray arrayWithCapacity:2];
    NSDictionary *headerChange=GuestCorrectTopSurface(header,window,top,
        @"baidu-slide-menu-header",&GuestHeaderOffset);
    if(headerChange) [changes addObject:headerChange];
    NSDictionary *barChange=GuestCorrectTopSurface(bar,window,top,
        @"baidu-navigation-bar",&GuestNavigationOffset);
    if(barChange) [changes addObject:barChange];
    if(changes.count) GuestWriteEvent(@"guest-uikit-top-surfaces-corrected",
        @{@"changes":changes,@"windowSafeInsets":
            NSStringFromUIEdgeInsets(window.safeAreaInsets)});
}
// A custom BDSNavigationController sometimes positions its navigation bar
// at ~54pt, whereas the child controller's reported safe top stays at 59pt.
// Add only the measured uncovered strip (usually ~39pt) to that child VC's
// safe layout. Never change its view frame, the window, or the video surface.
static void GuestRepairBaiduContentSafeArea(UIWindow *window,
                                            UIViewController *root,CGFloat top) {
    if(!GuestIsBaiduTopRepair(root)) {
        GuestRestoreBaiduContentSafeArea();
        return;
    }
    UINavigationController *nav=(UINavigationController *)root;
    UIViewController *child=nav.visibleViewController;
    UIView *childView=child.viewIfLoaded;
    UINavigationBar *bar=nav.navigationBar;
    LCOrbitBaiduContentSafeState *saved=GuestBaiduContentSafe;
    if(saved && saved.controller!=child) {
        GuestRestoreBaiduContentSafeArea();
        saved=nil;
    }
    if(!child || !childView || childView.window!=window || !bar ||
       bar.window!=window || nav.navigationBarHidden || bar.hidden) {
        GuestRestoreBaiduContentSafeArea();
        return;
    }
    // UIKit / the app owns its navigation transitions. Wait until settled.
    if(nav.transitionCoordinator || child.transitionCoordinator) return;
    UIEdgeInsets extra=child.additionalSafeAreaInsets;
    if(saved && fabs(extra.top-(saved.originalTop+saved.addedTop))>.75) {
        GuestBaiduContentSafe=nil;
        return;
    }
    CGRect barRect=[bar convertRect:bar.bounds toView:window];
    CGRect childRect=[childView convertRect:childView.bounds toView:window];
    CGFloat baselineSafeTop=childView.safeAreaInsets.top-(saved?saved.addedTop:0);
    // Only fix a real full-width bar anchored just below the Dynamic Island.
    // A bar at y=0 (or a hidden/fullscreen video bar) must remain untouched.
    BOOL qualifies=isfinite(top) && top>=35 && top<=95 &&
        isfinite(barRect.origin.y) && isfinite(childRect.origin.y) &&
        isfinite(baselineSafeTop) &&
        CGRectGetWidth(barRect)>=window.bounds.size.width*.9 &&
        CGRectGetHeight(barRect)>=38 && CGRectGetHeight(barRect)<=60 &&
        fabs(CGRectGetMinY(barRect)-top)<=12 &&
        CGRectGetMinY(childRect)>=-3 && CGRectGetMinY(childRect)<=3 &&
        CGRectGetHeight(childRect)>=window.bounds.size.height-10;
    if(!qualifies) {
        GuestRestoreBaiduContentSafeArea();
        return;
    }
    CGFloat needed=CGRectGetMaxY(barRect)-
        (CGRectGetMinY(childRect)+baselineSafeTop);
    if(!isfinite(needed) || needed<=1) {
        GuestRestoreBaiduContentSafeArea();
        return;
    }
    if(needed>56) return; // Never compensate for an unrelated overlay.
    if(saved && fabs(saved.addedTop-needed)<.75) return;
    if(!saved) {
        saved=[LCOrbitBaiduContentSafeState new];
        saved.controller=child;
        saved.originalTop=extra.top;
        GuestBaiduContentSafe=saved;
    }
    saved.addedTop=needed;
    extra.top=saved.originalTop+needed;
    [UIView performWithoutAnimation:^{
        child.additionalSafeAreaInsets=extra;
        [childView setNeedsUpdateConstraints];
        [childView setNeedsLayout];
    }];
    GuestWriteEvent(@"guest-uikit-baidu-content-safe-area-updated",
        @{@"controller":NSStringFromClass(child.class),
          @"navigationBar":NSStringFromCGRect(barRect),
          @"contentFrame":NSStringFromCGRect(childRect),
          @"baseSafeTop":@(baselineSafeTop),@"addedTop":@(needed),
          @"contentSafeInsets":NSStringFromUIEdgeInsets(childView.safeAreaInsets),
          @"additionalSafeInsets":NSStringFromUIEdgeInsets(extra)});
}
// Instagram's outer IGGestureCoordinatingCollectionView is a horizontal pager
// (e.g. offset {393,0}, size {786,852}). It must never receive a vertical inset.
// The fixed home header is a sibling of the feed. Locate the story tray's
// vertical scroll owner independently and move only both top components.
static UIView *GuestFindInstagramHeader(UIView *node,UIWindow *window,
        NSUInteger depth,NSUInteger *visited) {
    if(!node || depth>24 || ++(*visited)>1400 || node.hidden ||
       node.alpha<.05 || node.window!=window) return nil;
    if([NSStringFromClass(node.class) isEqualToString:
            @"IGHomeFeedHeader.IGHomeFeedHeaderView"]) return node;
    for(UIView *child in node.subviews) {
        UIView *found=GuestFindInstagramHeader(child,window,depth+1,visited);
        if(found) return found;
    }
    return nil;
}
static BOOL GuestIsVerticalInstagramScroll(UIScrollView *scroll) {
    if(!scroll || [NSStringFromClass(scroll.class) isEqualToString:
                    @"IGGestureCoordinatingCollectionView"] ||
       scroll.bounds.size.height<220 || scroll.bounds.size.width<250) return NO;
    CGSize size=scroll.bounds.size;
    CGFloat horizontal=scroll.contentSize.width-size.width;
    CGFloat vertical=scroll.contentSize.height-size.height;
    if(horizontal>MAX(120,size.width*.35) && vertical<50) return NO;
    if([scroll isKindOfClass:UICollectionView.class]) {
        UICollectionViewLayout *layout=((UICollectionView *)scroll).collectionViewLayout;
        if([layout isKindOfClass:UICollectionViewFlowLayout.class] &&
           ((UICollectionViewFlowLayout *)layout).scrollDirection==
               UICollectionViewScrollDirectionHorizontal) return NO;
    }
    return (vertical>40 || scroll.alwaysBounceVertical ||
            ([scroll isKindOfClass:UICollectionView.class] &&
             [((UICollectionView *)scroll).collectionViewLayout
                isKindOfClass:UICollectionViewFlowLayout.class] &&
             ((UICollectionViewFlowLayout *)
                 ((UICollectionView *)scroll).collectionViewLayout).scrollDirection==
                    UICollectionViewScrollDirectionVertical));
}
static UIView *GuestFindInstagramStoryTray(UIView *node,UIWindow *window,
        NSUInteger depth,NSUInteger *visited) {
    if(!node || depth>24 || ++(*visited)>1800 || node.hidden ||
       node.alpha<.05 || node.window!=window) return nil;
    if([NSStringFromClass(node.class) isEqualToString:
            @"IGStoryTrayCollectionViewCell"]) return node;
    for(UIView *child in node.subviews) {
        UIView *found=GuestFindInstagramStoryTray(child,window,depth+1,visited);
        if(found) return found;
    }
    return nil;
}
static UIScrollView *GuestInstagramInnerScroll(UIView *story,UIWindow *window) {
    if(!story) return nil;
    for(UIView *ancestor=story.superview;ancestor && ancestor!=window;
        ancestor=ancestor.superview)
        if([ancestor isKindOfClass:UIScrollView.class] &&
           GuestIsVerticalInstagramScroll((UIScrollView *)ancestor))
            return (UIScrollView *)ancestor;
    return nil;
}
static void GuestRestoreInstagramInset(void) {
    GuestRestoreTopSurface(&GuestInstagramHeaderOffset);
    LCOrbitInstagramInsetState *saved=GuestInstagramInset;
    GuestInstagramInset=nil;
    UIScrollView *scroll=saved.scroll;
    if(!scroll) return;
    CGFloat expected=saved.originalTop+saved.appliedTop;
    // Respect app-owned modifications after the correction.
    if(fabs(scroll.contentInset.top-expected)>1) return;
    UIEdgeInsets inset=scroll.contentInset;
    inset.top=saved.originalTop;
    [UIView performWithoutAnimation:^{
        scroll.contentInset=inset;
        if(!scroll.dragging && !scroll.decelerating &&
           fabs(scroll.contentOffset.y-(saved.originalOffsetY-saved.appliedTop))<3)
            [scroll setContentOffset:CGPointMake(
                scroll.contentOffset.x,saved.originalOffsetY) animated:NO];
    }];
}
static void GuestRepairInstagramInnerScroll(UIWindow *window,
                                            UIViewController *root,CGFloat top) {
    BOOL enabled=GuestRelayoutEnabled &&
        [GuestInstallPath() isEqualToString:@"com.burbn.instagram.app"] &&
        [NSStringFromClass(root.class) isEqualToString:@"IGRootViewController"];
    if(!enabled) {GuestRestoreInstagramInset();return;}
    NSUInteger visited=0;
    UIView *header=GuestFindInstagramHeader(root.viewIfLoaded,window,0,&visited);
    NSUInteger storyVisited=0;
    UIView *story=GuestFindInstagramStoryTray(root.viewIfLoaded,window,
                                              0,&storyVisited);
    UIScrollView *scroll=GuestInstagramInnerScroll(story,window);
    LCOrbitInstagramInsetState *saved=GuestInstagramInset;
    BOOL oldScroll=saved && saved.scroll!=scroll;
    BOOL oldHeader=saved && saved.header!=header;
    BOOL insetChanged=saved && !oldScroll &&
        fabs(scroll.contentInset.top-(saved.originalTop+saved.appliedTop))>1;
    BOOL headerChanged=saved && !oldHeader && header &&
        !CGAffineTransformEqualToTransform(header.transform,
            CGAffineTransformMakeTranslation(0,saved.appliedTop));
    if(saved && (oldScroll || oldHeader || insetChanged || headerChanged)) {
        // Instagram legitimately moves this header during a drag/deceleration.
        // Never reset the user's in-flight gesture to reapply our baseline.
        if(scroll && (scroll.dragging || scroll.tracking || scroll.decelerating))
            return;
        // A scrolled-away Instagram header is intentionally hidden. Do not
        // undo the safe inset merely because Instagram animated its transform.
        // Reconcile only when the feed returns to its resting top position.
        if(headerChanged && !oldScroll && !oldHeader && !insetChanged &&
           fabs(scroll.contentOffset.y+scroll.adjustedContentInset.top)>1)
            return;
        GuestRestoreInstagramInset();
        saved=nil;
        GuestInstagramNoScrollReported=NO;
        GuestWriteEvent(@"guest-uikit-instagram-layout-reset",
            @{@"oldScroll":@(oldScroll),@"oldHeader":@(oldHeader),
              @"insetChanged":@(insetChanged),
              @"headerChanged":@(headerChanged)});
    }
    if(!header || !story || !scroll) {
        // No app-wide override: only report the missing vertical owner.
        if(!GuestInstagramNoScrollReported && header && story) {
            GuestInstagramNoScrollReported=YES;
            GuestWriteEvent(@"guest-uikit-instagram-inner-scroll-skipped",
                @{@"reason":@"no-vertical-story-ancestor",
                  @"headerVisited":@(visited),@"storyVisited":@(storyVisited)});
        }
        return;
    }
    if(saved) return;
    CGRect beforeHeader=[header convertRect:header.bounds toView:window];
    CGRect beforeStory=[story convertRect:story.bounds toView:window];
    CGFloat y=CGRectGetMinY(beforeHeader);
    CGFloat storyY=CGRectGetMinY(beforeStory);
    UIEdgeInsets original=scroll.contentInset;
    UIEdgeInsets adjusted=scroll.adjustedContentInset;
    CGPoint originalOffset=scroll.contentOffset;
    CGFloat headerHeight=CGRectGetHeight(beforeHeader);
    // Instagram already reserves the 50pt fixed header in the feed's OWN
    // contentInset (normally top=50, offsetY=-50). This is app-owned spacing,
    // not a safe-area inset, and must be retained before adding the 59pt gap.
    // A small/zero top inset here would indicate a different layout entirely.
    BOOL appHeaderInset=isfinite(original.top) &&
        original.top>=30 && original.top<=85 &&
        fabs(original.top-headerHeight)<=5 &&
        fabs(storyY-original.top)<=1 &&
        fabs(adjusted.top-original.top)<=4 &&
        fabs(originalOffset.y+adjusted.top)<=0.75;
    BOOL geometryReady=isfinite(top) && top>=35 && top<=95 &&
        isfinite(y) && fabs(y)<=0.75 &&
        isfinite(storyY) && storyY>=30 && storyY<=110 &&
        !scroll.dragging && !scroll.tracking && !scroll.decelerating &&
        [NSStringFromClass(scroll.class) isEqualToString:
            @"_IGListScrollWhileAnimateCollectionView"];
    if(!appHeaderInset || !geometryReady) {
        if(!GuestInstagramNoScrollReported && isfinite(top) && top>30) {
            GuestInstagramNoScrollReported=YES;
            GuestWriteEvent(@"guest-uikit-instagram-inner-scroll-skipped",
                @{@"reason":@"app-header-inset-or-geometry-mismatch",
                  @"scrollClass":NSStringFromClass(scroll.class),
                  @"header":NSStringFromCGRect(beforeHeader),
                  @"story":NSStringFromCGRect(beforeStory),
                  @"originalInset":NSStringFromUIEdgeInsets(original),
                  @"adjustedInset":NSStringFromUIEdgeInsets(adjusted),
                  @"offset":NSStringFromCGPoint(originalOffset),
                  @"expectedSafeTop":@(top)});
        }
        return;
    }
    CGFloat delta=top-y;
    NSDictionary *headerChange=GuestCorrectTopSurface(header,window,top,
        @"instagram-home-header",&GuestInstagramHeaderOffset);
    if(!headerChange) return;
    UIEdgeInsets changed=original;
    changed.top+=delta;
    [UIView performWithoutAnimation:^{
        scroll.contentInset=changed;
        [scroll setContentOffset:CGPointMake(originalOffset.x,
                originalOffset.y-delta) animated:NO];
        [scroll layoutIfNeeded];
    }];
    CGRect afterHeader=[header convertRect:header.bounds toView:window];
    CGRect afterStory=[story convertRect:story.bounds toView:window];
    if(!isfinite(CGRectGetMinY(afterStory)) ||
       fabs(CGRectGetMinY(afterHeader)-top)>4 ||
       fabs((CGRectGetMinY(afterStory)-storyY)-delta)>4) {
        // Never leave a half-applied fix or a shifted tab/pager.
        [UIView performWithoutAnimation:^{
            scroll.contentInset=original;
            [scroll setContentOffset:originalOffset animated:NO];
        }];
        GuestRestoreTopSurface(&GuestInstagramHeaderOffset);
        GuestWriteEvent(@"guest-uikit-instagram-inner-scroll-skipped",
            @{@"reason":@"story-did-not-follow-feed-scroll",
              @"storyBefore":NSStringFromCGRect(beforeStory),
              @"storyAfter":NSStringFromCGRect(afterStory),
              @"headerBefore":NSStringFromCGRect(beforeHeader),
              @"headerAfter":NSStringFromCGRect(afterHeader)});
        return;
    }
    saved=[LCOrbitInstagramInsetState new];
    saved.scroll=scroll;
    saved.header=header;
    saved.originalTop=original.top;
    saved.originalOffsetY=originalOffset.y;
    saved.appliedTop=delta;
    GuestInstagramInset=saved;
    GuestInstagramNoScrollReported=NO;
    GuestWriteEvent(@"guest-uikit-instagram-inner-scroll-corrected",
        @{@"scrollClass":NSStringFromClass(scroll.class),
          @"originalInset":NSStringFromUIEdgeInsets(original),
          @"adjustedInset":NSStringFromUIEdgeInsets(scroll.adjustedContentInset),
          @"headerBefore":NSStringFromCGRect(beforeHeader),
          @"headerAfter":NSStringFromCGRect(afterHeader),
          @"storyBefore":NSStringFromCGRect(beforeStory),
          @"storyAfter":NSStringFromCGRect(afterStory),
          @"windowSafeTop":@(top)});
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
    if(!window || !root || !view || view.window!=window) {
        GuestRestoreBaiduSurfaces();
        GuestRestoreInstagramInset();
        return;
    }
    UIWindowScene *scene=window.windowScene;
    if(!scene || !UIInterfaceOrientationIsPortrait(scene.interfaceOrientation)) {
        GuestRestoreBaiduSurfaces();
        GuestRestoreInstagramInset();
        return;
    }
    if(GuestRelayoutWindow!=window || GuestRelayoutRoot!=root) {
        GuestRelayoutWindow=window;GuestRelayoutRoot=root;GuestRepairedTop=-1;
    }
    CGFloat top=window.safeAreaInsets.top;
    CGFloat rootTop=view.safeAreaInsets.top;
    if(!isfinite(top) || !isfinite(rootTop) || top<1 || rootTop<1 ||
       fabs(top-rootTop)>2) return;
    // A later app layout may recreate its custom header without changing the
    // safe-area number; the short bounded polling still checks for new views.
    if(fabs(top-GuestRepairedTop)<.5) {
        GuestRepairBaiduTopSurfaces(window,root,top);
        GuestRepairBaiduContentSafeArea(window,root,top);
        GuestRepairInstagramInnerScroll(window,root,top);
        return;
    }
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
        GuestRepairBaiduTopSurfaces(strongWindow,root,top);
        GuestRepairBaiduContentSafeArea(strongWindow,root,top);
        GuestRepairInstagramInnerScroll(strongWindow,root,top);
        if([LCOrbitGuestUIKitDiagnostics isEnabled])
            GuestWriteEvent(@"guest-uikit-safe-area-relayout",@{
                @"windowSafeInsets":NSStringFromUIEdgeInsets(strongWindow.safeAreaInsets),
                @"rootSafeInsets":NSStringFromUIEdgeInsets(view.safeAreaInsets),
                @"navigationBefore":before,
                @"navigationAfter":GuestNavigationGeometry(strongWindow)});
    });
}
// Observe BDS page transitions while active. No global UIKit hooks or
// whole-window resizing; Default run-loop mode avoids interfering with touch.
static void GuestStartBaiduContentWatch(void) {
    if(!GuestRelayoutEnabled ||
       ![GuestInstallPath() isEqualToString:@"com.bd.iphone.super.app"] ||
       GuestBaiduContentWatchTimer) return;
    GuestBaiduContentWatchTimer=[NSTimer timerWithTimeInterval:0.75 repeats:YES
        block:^(NSTimer *timer) {
            if(UIApplication.sharedApplication.applicationState==
               UIApplicationStateActive) GuestSafeAreaRepairTick();
        }];
    [[NSRunLoop mainRunLoop] addTimer:GuestBaiduContentWatchTimer
                            forMode:NSDefaultRunLoopMode];
}
static void GuestStopBaiduContentWatch(void) {
    [GuestBaiduContentWatchTimer invalidate];
    GuestBaiduContentWatchTimer=nil;
    GuestRestoreBaiduContentSafeArea();
}
// Instagram updates its home feed geometry again during refresh/reload. A
// normal-mode, low-rate watcher resumes the top-only fix AFTER scrolling settles.
// It is disabled during UIKit touch tracking, suspended when backgrounded, and
// exists only for Instagram with the per-App UIKit compatibility mode enabled.
static void GuestStartInstagramWatch(void) {
    if(!GuestRelayoutEnabled ||
       ![GuestInstallPath() isEqualToString:@"com.burbn.instagram.app"] ||
       GuestInstagramWatchTimer) return;
    GuestInstagramWatchTimer=[NSTimer timerWithTimeInterval:0.75 repeats:YES
        block:^(NSTimer *timer) {
            if(UIApplication.sharedApplication.applicationState==
               UIApplicationStateActive) GuestSafeAreaRepairTick();
        }];
    [[NSRunLoop mainRunLoop] addTimer:GuestInstagramWatchTimer
                            forMode:NSDefaultRunLoopMode];
}
static void GuestStopInstagramWatch(void) {
    [GuestInstagramWatchTimer invalidate];
    GuestInstagramWatchTimer=nil;
}
static void GuestScheduleSafeAreaRepair(void) {
    if(!GuestRelayoutEnabled || GuestRelayoutPolling) return;
    GuestRelayoutPolling=YES;
    // Bounded startup/foreground probes. No permanent timer or global hook.
    NSArray<NSNumber *> *delays=@[@0.0,@0.2,@0.5,@1.0,@1.8,@3.0,@5.0];
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
// Instagram keeps its feed collection view fullscreen. Diagnose scrolling and
// supplementary/header geometry before considering any content-inset mutation.
static void GuestInstagramHeaderCandidates(UIView *node,UIWindow *window,
        NSMutableArray<NSDictionary *> *results,NSUInteger depth,NSUInteger *visited) {
    if(!node || depth>18 || ++(*visited)>1400 || results.count>=12 ||
       node.hidden || node.alpha<.05 || node.window!=window) return;
    NSString *name=NSStringFromClass(node.class);
    if(depth>=4 && ([name hasPrefix:@"IG"] ||
                     [node isKindOfClass:UICollectionReusableView.class])) {
        CGRect frame=[node convertRect:node.bounds toView:window];
        CGRect topRegion=CGRectMake(0,0,window.bounds.size.width,180);
        if(CGRectIntersectsRect(frame,topRegion) && CGRectGetWidth(frame)>30 &&
           CGRectGetHeight(frame)>10 && CGRectGetHeight(frame)<200)
            [results addObject:@{@"class":name,
                @"frame":NSStringFromCGRect(frame),
                @"safeAreaInsets":NSStringFromUIEdgeInsets(node.safeAreaInsets),
                @"depth":@(depth)}];
    }
    for(UIView *child in node.subviews) {
        if(results.count>=12 || *visited>=1400) break;
        GuestInstagramHeaderCandidates(child,window,results,depth+1,visited);
    }
}
static UIScrollView *GuestInstagramFeedScroll(UIView *node,NSUInteger depth,
                                            NSUInteger *visited) {
    if(!node || depth>18 || ++(*visited)>1400) return nil;
    if([NSStringFromClass(node.class) isEqualToString:
            @"IGGestureCoordinatingCollectionView"] &&
       [node isKindOfClass:UIScrollView.class]) return (UIScrollView *)node;
    for(UIView *child in node.subviews) {
        UIScrollView *found=GuestInstagramFeedScroll(child,depth+1,visited);
        if(found) return found;
    }
    return nil;
}
static NSDictionary *GuestInstagramScrollGeometry(UIWindow *window) {
    if(![GuestInstallPath() isEqualToString:@"com.burbn.instagram.app"] ||
       ![NSStringFromClass(window.rootViewController.class)
           isEqualToString:@"IGRootViewController"]) return nil;
    UIView *root=window.rootViewController.viewIfLoaded;
    NSUInteger visited=0;
    UIScrollView *scroll=GuestInstagramFeedScroll(root,0,&visited);
    if(!scroll || scroll.window!=window)
        return @{@"feedFound":@NO,@"searchedViews":@(visited)};
    CGRect scrollFrame=[scroll convertRect:scroll.bounds toView:window];
    NSMutableDictionary *result=[@{
        @"feedFound":@YES,
        @"scrollClass":NSStringFromClass(scroll.class),
        @"frame":NSStringFromCGRect(scrollFrame),
        @"safeInsets":NSStringFromUIEdgeInsets(scroll.safeAreaInsets),
        @"contentInset":NSStringFromUIEdgeInsets(scroll.contentInset),
        @"adjustedContentInset":NSStringFromUIEdgeInsets(scroll.adjustedContentInset),
        @"contentInsetAdjustmentBehavior":@(scroll.contentInsetAdjustmentBehavior),
        @"contentOffset":NSStringFromCGPoint(scroll.contentOffset),
        @"contentSize":NSStringFromCGSize(scroll.contentSize),
        @"clipsToBounds":@(scroll.clipsToBounds)
    } mutableCopy];
    if([scroll isKindOfClass:UICollectionView.class]) {
        UICollectionView *collection=(UICollectionView *)scroll;
        result[@"layoutClass"]=NSStringFromClass(collection.collectionViewLayout.class);
        NSMutableArray *cells=[NSMutableArray array];
        for(UICollectionViewCell *cell in collection.visibleCells) {
            CGRect frame=[cell convertRect:cell.bounds toView:window];
            if(CGRectIntersectsRect(frame,CGRectMake(0,0,window.bounds.size.width,180)) &&
               cells.count<8)
                [cells addObject:@{@"class":NSStringFromClass(cell.class),
                    @"frame":NSStringFromCGRect(frame)}];
        }
        result[@"topVisibleCells"]=cells;
    }
    NSMutableArray *headers=[NSMutableArray array];
    visited=0;
    GuestInstagramHeaderCandidates(root,window,headers,0,&visited);
    result[@"topHeaderCandidates"]=headers;
    result[@"visitedViews"]=@(visited);
    NSUInteger headerVisited=0;
    UIView *header=GuestFindInstagramHeader(root,window,0,&headerVisited);
    if(header) {
        NSMutableArray *chain=[NSMutableArray array];
        for(UIView *node=header;node && node!=window && chain.count<18;
            node=node.superview) {
            NSMutableDictionary *entry=[@{
                @"class":NSStringFromClass(node.class),
                @"frame":NSStringFromCGRect([node convertRect:node.bounds toView:window])
            } mutableCopy];
            if([node isKindOfClass:UIScrollView.class]) {
                UIScrollView *sv=(UIScrollView *)node;
                entry[@"contentSize"]=NSStringFromCGSize(sv.contentSize);
                entry[@"contentOffset"]=NSStringFromCGPoint(sv.contentOffset);
                entry[@"contentInset"]=NSStringFromUIEdgeInsets(sv.contentInset);
                entry[@"adjustedInset"]=NSStringFromUIEdgeInsets(sv.adjustedContentInset);
                entry[@"verticalCandidate"]=@(GuestIsVerticalInstagramScroll(sv));
            }
            [chain addObject:entry];
        }
        result[@"homeHeaderAncestors"]=chain;
    }
    NSUInteger storyVisited=0;
    UIView *story=GuestFindInstagramStoryTray(root,window,0,&storyVisited);
    if(story) {
        NSMutableArray *storyChain=[NSMutableArray array];
        for(UIView *node=story;node && node!=window &&
            storyChain.count<16;node=node.superview) {
            NSMutableDictionary *entry=[@{
                @"class":NSStringFromClass(node.class),
                @"frame":NSStringFromCGRect(
                    [node convertRect:node.bounds toView:window])
            } mutableCopy];
            if([node isKindOfClass:UIScrollView.class]) {
                UIScrollView *sv=(UIScrollView *)node;
                entry[@"contentSize"]=NSStringFromCGSize(sv.contentSize);
                entry[@"contentOffset"]=NSStringFromCGPoint(sv.contentOffset);
                entry[@"adjustedInset"]=NSStringFromUIEdgeInsets(sv.adjustedContentInset);
                entry[@"verticalCandidate"]=@(GuestIsVerticalInstagramScroll(sv));
            }
            [storyChain addObject:entry];
        }
        result[@"storyTrayAncestors"]=storyChain;
        result[@"innerVerticalScrollFound"]=@(GuestInstagramInnerScroll(story,window)!=nil);
    }

    return result;
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
    NSDictionary *instagram=GuestInstagramScrollGeometry(window);
    if(instagram) details[@"instagramScroll"]=instagram;
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
        if(GuestRelayoutEnabled) {
            [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
                    GuestStopInstagramWatch();
                    GuestStopBaiduContentWatch();
                }];
        }
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
                    GuestStartInstagramWatch();
                    GuestStartBaiduContentWatch();
                }
            }];
        if(GuestRelayoutEnabled) {
            GuestScheduleSafeAreaRepair();
            GuestStartInstagramWatch();
            GuestStartBaiduContentWatch();
        }
        if(diagnostics) for(NSNumber *delay in @[@1.0,@3.0,@6.0])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),
                           dispatch_get_main_queue(),^{
                GuestTakeSnapshot([NSString stringWithFormat:@"startup+%.1fs",delay.doubleValue]);
            });
    });
}
@end
