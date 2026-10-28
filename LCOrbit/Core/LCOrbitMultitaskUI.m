#import "LCOrbitMultitask.h"
#import "LCOrbitHost.h"
#import "LCOrbitLog.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>
#import <math.h>

BOOL OrbitMethodMatches(Class cls, NSString *name, const char *result, NSArray<NSString *> *arguments) {
    Method method=cls?class_getInstanceMethod(cls,NSSelectorFromString(name)):NULL;
    if(!method || method_getNumberOfArguments(method)!=arguments.count+2) return NO;
    char *type=method_copyReturnType(method);
    BOOL matches=type && strcmp(type,result)==0;
    free(type);
    if(!matches) return NO;
    for(NSUInteger index=0;index<arguments.count;index++) {
        type=method_copyArgumentType(method,(unsigned int)index+2);
        matches=type && strcmp(type,arguments[index].UTF8String)==0;
        free(type);
        if(!matches) return NO;
    }
    return YES;
}
// End of Foundation-only ABI guard.

// These declarations describe existing selectors only. No LC classes or Swift
// symbols are linked into the tweak; all entry points are checked at runtime.
@interface NSObject (OrbitWindowSelectors)
- (UIViewController *)appSceneVC;
- (id)delegate;
- (id)presenter;
- (id)scene;
- (NSString *)bundleId;
- (NSString *)dataUUID;
- (UINavigationBar *)navigationBar;
- (UIView *)resizeHandle;
- (UIView *)contentView;
- (NSArray<NSLayoutConstraint *> *)activatedVerticalConstraints;
- (void)setActivatedVerticalConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
- (BOOL)isMaximized;
- (void)setIsMaximized:(BOOL)maximized;
- (CGFloat)scaleRatio;
- (void)setScaleRatio:(CGFloat)scale;
- (void)updateOriginalFrame;
- (void)appSceneVCWillActivateScene:(id)scene;
- (BOOL)isAppRunning;
- (void)updateSettingsWithBlock:(void (^)(id settings))block;
- (void (^)(NSNumber *,NSError *))pidAvailableHandler;
- (UIInterfaceOrientation)interfaceOrientation;
- (NSInteger)deviceOrientation;
- (NSInteger)userInterfaceStyle;
- (void)setInterfaceOrientation:(UIInterfaceOrientation)orientation;
- (void)setDeviceOrientation:(NSInteger)orientation;
- (void)setUserInterfaceStyle:(NSInteger)style;
- (void)setForeground:(BOOL)foreground;
- (void)setFrame:(CGRect)frame;
- (void)setPeripheryInsets:(UIEdgeInsets)insets;
- (void)setSafeAreaInsetsPortrait:(UIEdgeInsets)insets;
- (void)setSafeAreaEdgeInsets:(UIEdgeInsets)insets;
@end

static char SnapshotKey, ConstraintsKey, HostingPlacementKey;
static Class WindowClass, DockClass;
static IMP OriginalInit, OriginalSetup, OriginalVertical, OriginalFrame;
static IMP OriginalSafeArea, OriginalSettings, OriginalExit, OriginalInitialized;
static IMP OriginalLayout, OriginalShowDock, OriginalShowHidden, OriginalToggleDock;
static IMP OriginalBringToFront;
static IMP OriginalMinimize;
static IMP OriginalWindowDidAddSubview;
static __weak UIView *NativeDockSurface;
static char DockVisibilityKey;
static IMP OriginalSceneSettings, OriginalPresenter;
static IMP OriginalFinalSettings;
static IMP OriginalInitialSettings;
static UIViewController *InitialSceneWindow;
static void InstallFinalSceneHook(void);
typedef id (*OrbitInitializer)(id __attribute__((ns_consumed)),SEL,id,id,id,id) __attribute__((ns_returns_retained));

static Class HostClass(NSString *name) {
    return NSClassFromString(name) ?: NSClassFromString([@"LiveContainerSwiftUI." stringByAppendingString:name]);
}
static BOOL Fullscreen(void) { return [LCOrbitMultitask isManagingWindows]; }
static UIViewController *SceneController(UIViewController *window) { return [(id)window appSceneVC]; }
static id Dock(void) {
    SEL selector=NSSelectorFromString(@"shared");
    return [DockClass respondsToSelector:selector]?((id(*)(id,SEL))objc_msgSend)(DockClass,selector):nil;
}
static UIViewController *HostingParentController(UIViewController *requested) {
    id dock=Dock();SEL hosting=NSSelectorFromString(@"windowHostingView");
    if(![dock respondsToSelector:hosting]) return requested;
    UIResponder *responder=((id(*)(id,SEL))objc_msgSend)(dock,hosting);
    while(responder) {
        if([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder=responder.nextResponder;
    }
    return requested;
}

@interface LCOrbitHostingPlacement : NSObject
@property(nonatomic,weak) UIView *parent;
@property(nonatomic) NSUInteger index;
@property(nonatomic) CGRect frame;
@property(nonatomic) UIViewAutoresizing autoresizing;
@end
@implementation LCOrbitHostingPlacement @end

// LC normally attaches this container inside the first SwiftUI subview.
// Mount it above the root content so fullscreen Guests also cover LC's tab bar.
static void PositionHostingView(UIViewController *window,BOOL fullscreen) {
    UIView *hosting=window.view.superview;
    if(![hosting isKindOfClass:HostClass(@"VirtualWindowsHostView")]) return;
    LCOrbitHostingPlacement *placement=objc_getAssociatedObject(hosting,&HostingPlacementKey);
    if(fullscreen) {
        UIView *root=window.parentViewController.view;
        if(!root || root==hosting || [root isDescendantOfView:hosting]) return;
        CGRect bounds=root.bounds;
        if(!isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width<=0 || bounds.size.height<=0) return;
        if(!placement) {
            placement=[LCOrbitHostingPlacement new];placement.parent=hosting.superview;
            placement.index=[hosting.superview.subviews indexOfObjectIdenticalTo:hosting];
            placement.frame=hosting.frame;placement.autoresizing=hosting.autoresizingMask;
            objc_setAssociatedObject(hosting,&HostingPlacementKey,placement,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if(hosting.superview!=root) [root addSubview:hosting];
        [root bringSubviewToFront:hosting];
        hosting.frame=root.bounds;
        hosting.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    } else if(placement) {
        UIView *parent=placement.parent;
        if(parent) {
            [parent insertSubview:hosting atIndex:MIN(placement.index,parent.subviews.count)];
            hosting.frame=placement.frame;hosting.autoresizingMask=placement.autoresizing;
        }
        objc_setAssociatedObject(hosting,&HostingPlacementKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void RememberAppearance(UIViewController *window) {
    if(objc_getAssociatedObject(window,&SnapshotKey)) return;
    UIView *view=window.view;
    UINavigationBar *bar=[(id)window navigationBar];
    UIView *handle=[(id)window resizeHandle];
    UIView *content=[(id)SceneController(window) contentView];
    NSDictionary *snapshot=@{@"frame":[NSValue valueWithCGRect:view.frame],
        @"maximized":@([(id)window isMaximized]),@"scale":@([(id)window scaleRatio]),
        @"radius":@(view.layer.cornerRadius),@"border":@(view.layer.borderWidth),
        @"autoresizing":@(view.autoresizingMask),@"hidden":@(view.hidden),
        @"barHidden":@(bar.hidden),@"barAlpha":@(bar.alpha),
        @"handleHidden":@(handle.hidden),@"handleAlpha":@(handle.alpha),
        @"contentTransform":[NSValue valueWithCGAffineTransform:content?content.transform:CGAffineTransformIdentity],
        @"contentSublayer":[NSValue valueWithCATransform3D:content?content.layer.sublayerTransform:CATransform3DIdentity]};
    objc_setAssociatedObject(window,&SnapshotKey,snapshot,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL OrbitValidFrame(CGRect frame) {
    return isfinite(frame.origin.x) && isfinite(frame.origin.y) &&
        isfinite(frame.size.width) && isfinite(frame.size.height) && frame.size.width>0 && frame.size.height>0;
}
static UIEdgeInsets PortraitInsets(UIEdgeInsets insets, UIInterfaceOrientation orientation) {
    switch(orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            return UIEdgeInsetsMake(insets.left,0,insets.right,insets.bottom);
        case UIInterfaceOrientationLandscapeRight:
            return UIEdgeInsetsMake(insets.left,insets.bottom,insets.right,0);
        default: return insets;
    }
}
static BOOL FullscreenGeometry(UIViewController *window,CGRect *frame,UIInterfaceOrientation *orientation,UIEdgeInsets *insets) {
    UIWindow *host=window.view.window ?: window.parentViewController.view.window;
    UIWindowScene *scene=host.windowScene;
    CGRect bounds=host.bounds;
    UIInterfaceOrientation direction=scene.interfaceOrientation;
    if(!host || !scene || !OrbitValidFrame(bounds) || direction<UIInterfaceOrientationPortrait ||
       direction>UIInterfaceOrientationLandscapeRight) return NO;
    UIEdgeInsets safe=host.safeAreaInsets;
    if(!isfinite(safe.top) || !isfinite(safe.left) || !isfinite(safe.bottom) || !isfinite(safe.right) ||
       safe.top<0 || safe.left<0 || safe.bottom<0 || safe.right<0 ||
       safe.top+safe.bottom>bounds.size.height || safe.left+safe.right>bounds.size.width) return NO;
    *frame=(CGRect){CGPointZero,bounds.size};
    if(UIInterfaceOrientationIsLandscape(direction)) frame->size=CGSizeMake(bounds.size.height,bounds.size.width);
    *orientation=direction;*insets=safe;
    return YES;
}
static void ApplyGeometry(id settings,CGRect frame,UIInterfaceOrientation orientation,UIEdgeInsets insets) {
    [settings setInterfaceOrientation:orientation];
    [settings setFrame:frame];
    [settings setPeripheryInsets:insets];
    [settings setSafeAreaInsetsPortrait:PortraitInsets(insets,orientation)];
    if([settings respondsToSelector:@selector(setSafeAreaEdgeInsets:)]) [settings setSafeAreaEdgeInsets:insets];
}
static void ConfigureSafeArea(UIViewController *window,id settings) {
    CGRect frame;UIInterfaceOrientation orientation;UIEdgeInsets insets;
    if(FullscreenGeometry(window,&frame,&orientation,&insets)) ApplyGeometry(settings,frame,orientation,insets);
}

static void LayoutFullscreen(UIViewController *window) {
    UIViewController *scene=SceneController(window);
    if(!window.isViewLoaded || !scene || ![(id)window navigationBar]) return;
    CGRect frame;UIInterfaceOrientation orientation;UIEdgeInsets insets;
    if(!FullscreenGeometry(window,&frame,&orientation,&insets)) return;
    RememberAppearance(window);
    PositionHostingView(window,YES);
    UIView *view=window.view;
    if(view.superview && OrbitValidFrame(view.superview.bounds) && !CGRectEqualToRect(view.frame,view.superview.bounds))
        view.frame=view.superview.bounds;
    view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    view.layer.cornerRadius=0;
    view.layer.borderWidth=0;
    [(id)window setIsMaximized:YES];
    [(id)window setScaleRatio:1];
    [(id)scene setScaleRatio:1];
    UIView *content=[(id)scene contentView];
    content.transform=CGAffineTransformIdentity;
    content.layer.sublayerTransform=CATransform3DIdentity;
    UINavigationBar *bar=[(id)window navigationBar];
    bar.hidden=YES;bar.alpha=0;
    UIView *handle=[(id)window resizeHandle];
    handle.hidden=YES;handle.alpha=0;
    if(!objc_getAssociatedObject(window,&ConstraintsKey)) {
        [NSLayoutConstraint deactivateConstraints:[(id)window activatedVerticalConstraints]?:@[]];
        NSArray *constraints=@[
            [scene.view.topAnchor constraintEqualToAnchor:view.topAnchor],
            [scene.view.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
            [bar.heightAnchor constraintEqualToConstant:0]];
        [(id)window setActivatedVerticalConstraints:constraints];
        [NSLayoutConstraint activateConstraints:constraints];
        objc_setAssociatedObject(window,&ConstraintsKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void UpdateScene(UIViewController *window,id baseSettings) {
    CGRect frame;UIInterfaceOrientation orientation;UIEdgeInsets insets;
    if(!FullscreenGeometry(window,&frame,&orientation,&insets)) return;
    LayoutFullscreen(window);
    UIViewController *scene=SceneController(window);
    if(!scene) return;
    __weak UIViewController *weakWindow=window;
    [(id)scene updateSettingsWithBlock:^(id settings) {
        UIViewController *strongWindow=weakWindow;
        if(!strongWindow) return;
        if(baseSettings) {
            [settings setUserInterfaceStyle:[baseSettings userInterfaceStyle]];
            [settings setDeviceOrientation:[baseSettings deviceOrientation]];
            // Follow the host scene even when a guest requests another size.
        } else {
            [settings setDeviceOrientation:UIDevice.currentDevice.orientation];
        }
        [settings setForeground:YES];
        ApplyGeometry(settings,frame,orientation,insets);
    }];
}
static void SceneSettings(id scene,SEL selector,void (^block)(id)) {
    UIViewController *window=[scene delegate];
    if(!Fullscreen() || ![window isKindOfClass:WindowClass]) {
        ((void(*)(id,SEL,id))OriginalSceneSettings)(scene,selector,block);return;
    }
    CGRect frame;UIInterfaceOrientation orientation;UIEdgeInsets insets;
    if(!FullscreenGeometry(window,&frame,&orientation,&insets)) return;
    // LC's queued resize blocks bypass the decorated-controller delegate.
    // Apply one coherent geometry snapshot after every caller's changes.
    ((void(*)(id,SEL,id))OriginalSceneSettings)(scene,selector,^(id settings) {
        if(block) block(settings);
        ApplyGeometry(settings,frame,orientation,insets);
    });
}
static void FinalSceneSettings(id remote,SEL selector,void (^block)(id,id)) {
    UIViewController *window=nil;
    if(Fullscreen()) for(UIViewController *candidate in [LCOrbitMultitask windows]) {
        id presenter=[(id)SceneController(candidate) presenter];
        if([presenter scene]==remote) {window=candidate;break;}
    }
    if(!window) {((void(*)(id,SEL,id))OriginalFinalSettings)(remote,selector,block);return;}
    CGRect frame;UIInterfaceOrientation orientation;UIEdgeInsets insets;
    if(!FullscreenGeometry(window,&frame,&orientation,&insets)) return;
    // iOS 18+ uses AppScene's temporary settings only for contentView.frame.
    // Apply insets at the real FBScene boundary, after LC's UIKit wrapper.
    ((void(*)(id,SEL,id))OriginalFinalSettings)(remote,selector,^(id settings,id context) {
        if(block) block(settings,context);
        ApplyGeometry(settings,frame,orientation,insets);
    });
}
static void InitialSceneSettings(id parameters,SEL selector,void (^block)(id)) {
    UIViewController *window=NSThread.isMainThread && Fullscreen()?InitialSceneWindow:nil;
    CGRect frame;UIInterfaceOrientation orientation;UIEdgeInsets insets;
    if(!window || !FullscreenGeometry(window,&frame,&orientation,&insets)) {
        ((void(*)(id,SEL,id))OriginalInitialSettings)(parameters,selector,block);return;
    }
    // Both LC scene APIs configure these parameters before remote activation.
    // Later FBScene updates cannot repair geometry an App cached at launch.
    ((void(*)(id,SEL,id))OriginalInitialSettings)(parameters,selector,^(id settings) {
        if(block) block(settings);
        ApplyGeometry(settings,frame,orientation,insets);
    });
}
static void PresenterReady(id scene,SEL selector) {
    if(!NSThread.isMainThread) {
        ((void(*)(id,SEL))OriginalPresenter)(scene,selector);return;
    }
    InstallFinalSceneHook();
    UIViewController *window=[scene delegate];
    BOOL managed=Fullscreen() && [window isKindOfClass:WindowClass];
    UIViewController *previous=InitialSceneWindow;
    if(managed) {
        LayoutFullscreen(window);
        [window.view layoutIfNeeded];
    }
    InitialSceneWindow=managed?window:nil;
    @try {
        ((void(*)(id,SEL))OriginalPresenter)(scene,selector);
    } @finally {
        InitialSceneWindow=previous;
    }
    if(managed) {
        [window.view layoutIfNeeded];
        UpdateScene(window,nil);
    }
}

static void RestoreAppearance(UIViewController *window) {
    NSDictionary *snapshot=objc_getAssociatedObject(window,&SnapshotKey);
    if(!snapshot) return;
    PositionHostingView(window,NO);
    [NSLayoutConstraint deactivateConstraints:[(id)window activatedVerticalConstraints]?:@[]];
    [(id)window setActivatedVerticalConstraints:@[]];
    objc_setAssociatedObject(window,&ConstraintsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.view.frame=[snapshot[@"frame"] CGRectValue];
    window.view.autoresizingMask=[snapshot[@"autoresizing"] unsignedIntegerValue];
    window.view.layer.cornerRadius=[snapshot[@"radius"] doubleValue];
    window.view.layer.borderWidth=[snapshot[@"border"] doubleValue];
    window.view.hidden=[snapshot[@"hidden"] boolValue];window.view.alpha=1;
    [(id)window setIsMaximized:[snapshot[@"maximized"] boolValue]];
    CGFloat scale=[snapshot[@"scale"] doubleValue];
    [(id)window setScaleRatio:scale];
    [(id)SceneController(window) setScaleRatio:scale];
    UIView *content=[(id)SceneController(window) contentView];
    content.transform=[snapshot[@"contentTransform"] CGAffineTransformValue];
    content.layer.sublayerTransform=[snapshot[@"contentSublayer"] CATransform3DValue];
    UINavigationBar *bar=[(id)window navigationBar];
    bar.hidden=[snapshot[@"barHidden"] boolValue];bar.alpha=[snapshot[@"barAlpha"] doubleValue];
    UIView *handle=[(id)window resizeHandle];
    handle.hidden=[snapshot[@"handleHidden"] boolValue];handle.alpha=[snapshot[@"handleAlpha"] doubleValue];
    objc_setAssociatedObject(window,&SnapshotKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Fullscreen setup made LC skip its non-maximized geometry snapshot.
    // Rebuild it before native resizing/rotation can use the saved frame.
    [(id)window updateOriginalFrame];
    ((void(*)(id,SEL))OriginalVertical)(window,NSSelectorFromString(@"updateVerticalConstraints"));
    [window.view layoutIfNeeded];
    [(id)window appSceneVCWillActivateScene:SceneController(window)];
}

static void SetVisible(UIViewController *window,SEL selector,BOOL visible) {
    [window.view.layer removeAllAnimations];
    window.view.transform=CGAffineTransformIdentity;
    window.view.alpha=visible?1:0;
    window.view.hidden=!visible;
}
static void Activate(UIViewController *window,SEL selector) {
    if(![LCOrbitMultitask isEnabled]) return;
    if(Fullscreen()) for(UIViewController *other in [LCOrbitMultitask windows])
        SetVisible(other,selector,other==window);
    SetVisible(window,selector,YES);
    [window.view.superview bringSubviewToFront:window.view];
    [LCOrbitMultitask didActivateWindow:window];
    if(Fullscreen()) UpdateScene(window,nil);
}
static id InitWindow(id __attribute__((ns_consumed)) self,SEL selector,NSString *name,NSString *bundle,NSString *container,UIViewController *root) __attribute__((ns_returns_retained));
static id InitWindow(id __attribute__((ns_consumed)) self,SEL selector,NSString *name,NSString *bundle,NSString *container,UIViewController *root) {
    // LCUtils reads keyWindow, which can temporarily be the floating menu's
    // alert/settings window. LC adds the child view to its existing hosting
    // container first, so containment must use that container's actual owner.
    root=HostingParentController(root);
    UIViewController *window=((OrbitInitializer)OriginalInit)(self,selector,name,bundle,container,root);
    if(window) {
        InstallFinalSceneHook();
        [LCOrbitMultitask recordWindow:window bundle:bundle container:container];
        if(Fullscreen()) Activate(window,NSSelectorFromString(@"orbit_activate"));
        else if([LCOrbitMultitask isEnabled]) [LCOrbitMultitask didActivateWindow:window];
    }
    return window;
}
static void Setup(UIViewController *window,SEL selector) {
    ((void(*)(id,SEL))OriginalSetup)(window,selector);
    if(Fullscreen()) LayoutFullscreen(window);
}
static void Vertical(UIViewController *window,SEL selector) {
    if(!Fullscreen()) { ((void(*)(id,SEL))OriginalVertical)(window,selector);return; }
    LayoutFullscreen(window);
    UpdateScene(window,nil);
}
static void Frame(UIViewController *window,SEL selector,id settings) {
    if(!Fullscreen()) { ((void(*)(id,SEL,id))OriginalFrame)(window,selector,settings);return; }
    LayoutFullscreen(window);ConfigureSafeArea(window,settings);
}
static UIEdgeInsets SafeArea(UIViewController *window,SEL selector,id settings) {
    if(!Fullscreen()) return ((UIEdgeInsets(*)(id,SEL,id))OriginalSafeArea)(window,selector,settings);
    ConfigureSafeArea(window,settings);
    return UIEdgeInsetsZero;
}
static void Settings(UIViewController *window,SEL selector,id scene,id settings,id context,uint32_t actionType) {
    if(!Fullscreen()) {
        ((void(*)(id,SEL,id,id,id,uint32_t))OriginalSettings)(window,selector,scene,settings,context,actionType);
        return;
    }
    UpdateScene(window,settings);
}
static void Layout(UIViewController *window,SEL selector) {
    ((void(*)(id,SEL))OriginalLayout)(window,selector);
    if(Fullscreen()) LayoutFullscreen(window);
}
static void Exited(UIViewController *window,SEL selector,id scene) {
    BOOL managed=Fullscreen();
    ((void(*)(id,SEL,id))OriginalExit)(window,selector,scene);
    if(![(id)scene isAppRunning]) {
        [LCOrbitMultitask forgetWindow:window];
        if(managed) {
            SetVisible(window,selector,NO);
            NSString *container=[(id)scene dataUUID];
            SEL remove=NSSelectorFromString(@"removeRunningApp:");
            id dock=Dock();
            if(container.length && [dock respondsToSelector:remove])
                ((void(*)(id,SEL,id))objc_msgSend)(dock,remove,container);
            [window.view removeFromSuperview];
            [window willMoveToParentViewController:nil];
            [window removeFromParentViewController];
        }
    }
}
static void Initialized(UIViewController *window,SEL selector,id scene,NSError *error) {
    ((void(*)(id,SEL,id,id))OriginalInitialized)(window,selector,scene,error);
    if(error && Fullscreen()) {
        // LC forwards successful PIDs but not failures. Defer until LCUtils has
        // assigned its completion block after the decorated initializer returns.
        dispatch_async(dispatch_get_main_queue(),^{
            void (^completion)(NSNumber *,NSError *)=[(id)window pidAvailableHandler];
            if(completion) completion(nil,error);
        });
    }
}
// Native LC Swift calls showDock() directly from its own task registration.
// Those calls can bypass ObjC IMP replacement, and dispatch later. We only
// suppress the actual SwiftUI dock view, never the task manager or scene host.
static BOOL BeadMenu(void) {
    return Fullscreen() && ![LCOrbitMultitask usesSystemMenu];
}
static BOOL OrbitDockShouldSuppress(BOOL bead,NSString *name,BOOL rootView) {
    if(!bead || rootView || ![name isKindOfClass:NSString.class]) return NO;
    return [name rangeOfString:@"HostingView"].location!=NSNotFound &&
           [name rangeOfString:@"AnyView"].location!=NSNotFound;
}
static BOOL IsNativeDockSurface(UIView *view,UIWindow *window) {
    return view && window && view.superview==window &&
       OrbitDockShouldSuppress(YES,NSStringFromClass(view.class),view==window.rootViewController.view);
}
static void ApplyDockSurfaceVisibility(UIView *view,BOOL suppress) {
    if(!view) return;
    NSArray *saved=objc_getAssociatedObject(view,&DockVisibilityKey);
    if(suppress) {
        if(!saved) objc_setAssociatedObject(view,&DockVisibilityKey,
            @[@(view.hidden),@(view.userInteractionEnabled)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.hidden=YES;view.userInteractionEnabled=NO;
    } else if(saved) {
        view.hidden=[saved[0] boolValue];view.userInteractionEnabled=[saved[1] boolValue];
        objc_setAssociatedObject(view,&DockVisibilityKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void SyncNativeDockSurface(void) {
    if(![LCOrbitHost isHostUI] || !DockClass) return;
    if(!NativeDockSurface || !NativeDockSurface.superview) {
        NativeDockSurface=nil;
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if(![scene isKindOfClass:UIWindowScene.class]) continue;
            for(UIWindow *window in ((UIWindowScene *)scene).windows) {
                if(window.windowLevel!=UIWindowLevelNormal) continue;
                for(UIView *view in window.subviews) if(IsNativeDockSurface(view,window)) {
                    NativeDockSurface=view;
                    break;
                }
                if(NativeDockSurface) break;
            }
            if(NativeDockSurface) break;
        }
    }
    ApplyDockSurfaceVisibility(NativeDockSurface,BeadMenu());
}
static void WindowDidAddSubview(UIWindow *window,SEL selector,UIView *subview) {
    ((void(*)(id,SEL,id))OriginalWindowDidAddSubview)(window,selector,subview);
    if([LCOrbitHost isHostUI] && IsNativeDockSurface(subview,window)) {
        NativeDockSurface=subview;
        SyncNativeDockSurface();
        [LCOrbitLog appendEvent:@"native-dock-attached" details:@{@"microbead":@(BeadMenu())} kind:@"runtime"];
    }
}
static void ShowDock(id dock,SEL selector) {
    if(BeadMenu()) {
        // Task registration should not open another menu or show LC's Dock.
        SyncNativeDockSurface();
    } else ((void(*)(id,SEL))OriginalShowDock)(dock,selector);
}
static void ShowHidden(id dock,SEL selector) {
    if(BeadMenu()) [LCOrbitMultitask requestMenu];
    else ((void(*)(id,SEL))OriginalShowHidden)(dock,selector);
}
static void ToggleDock(id dock,SEL selector) {
    if(BeadMenu()) [LCOrbitMultitask requestMenu];
    else ((void(*)(id,SEL))OriginalToggleDock)(dock,selector);
}
static void HostingBringToFront(UIView *hosting,SEL selector,UIView *view) {
    ((void(*)(id,SEL,id))OriginalBringToFront)(hosting,selector,view);
    if(![LCOrbitMultitask isEnabled]) return;
    // LC's Swift Dock reorders the task view directly, bypassing orbit_activate.
    for(UIViewController *window in [LCOrbitMultitask windows]) {
        if(window.view!=view) continue;
        if(Fullscreen()) for(UIViewController *other in [LCOrbitMultitask windows])
            SetVisible(other,selector,other==window);
        [LCOrbitMultitask didActivateWindow:window];
        if(Fullscreen()) UpdateScene(window,nil);
        break;
    }
}
static void Minimize(UIViewController *window,SEL selector) {
    ((void(*)(id,SEL))OriginalMinimize)(window,selector);
    if([LCOrbitMultitask isEnabled]) [LCOrbitMultitask didHideWindow:window];
}

static void Replace(Class cls,NSString *name,IMP replacement,IMP *original) {
    SEL selector=NSSelectorFromString(name);
    Method method=class_getInstanceMethod(cls,selector);
    *original=method_getImplementation(method);
    class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
}
static void InstallFinalSceneHook(void) {
    if(OriginalFinalSettings) return;
    Class cls=HostClass(@"FBScene");
    // UIKitFixesInit swaps these methods when the first AppScene is created.
    // Installing on LC's original-method alias afterwards keeps our geometry
    // last in the chain, irrespective of when fullscreen mode was enabled.
    NSString *name=class_getInstanceMethod(cls,NSSelectorFromString(@"hook__performUpdateWithoutActivation:"))?
        @"hook__performUpdateWithoutActivation:":@"_performUpdateWithoutActivation:";
    if(OrbitMethodMatches(cls,name,@encode(void),@[@"@?"]) || OrbitMethodMatches(cls,name,@encode(void),@[@"@"]))
        Replace(cls,name,(IMP)FinalSceneSettings,&OriginalFinalSettings);
}
static void FindWindows(UIViewController *controller,NSMutableSet *found) {
    if(!controller || [found containsObject:controller]) return;
    if([controller isKindOfClass:WindowClass]) {
        [found addObject:controller];
        id scene=SceneController(controller);
        NSString *bundle=[scene bundleId],*container=[scene dataUUID];
        if(bundle.length && container.length)
            [LCOrbitMultitask recordWindow:controller bundle:bundle container:container];
    }
    for(UIViewController *child in controller.childViewControllers) FindWindows(child,found);
    FindWindows(controller.presentedViewController,found);
}

@implementation LCOrbitMultitask (Presentation)
+ (BOOL)installHooksWithError:(NSError **)error {
    static BOOL installed=NO;
    if(installed) return YES;
    WindowClass=HostClass(@"DecoratedAppSceneViewController");
    DockClass=HostClass(@"MultitaskDockManager");
    Class sceneClass=HostClass(@"AppSceneViewController");
    NSArray *methods=@[
        @[@"initWindowName:bundleId:dataUUID:rootVC:",@"@",@[@"@",@"@",@"@",@"@"]],
        @[@"setupDecoratedView",@"v",@[]],@[@"updateVerticalConstraints",@"v",@[]],
        @[@"minimizeWindow",@"v",@[]],
        @[@"updateOriginalFrame",@"v",@[]],@[@"appSceneVCWillActivateScene:",@"v",@[@"@"]],
        @[@"updateMaximizedFrameWithSettings:",@"v",@[@"@"]],
        @[@"updateMaximizedSafeAreaWithSettings:",@(@encode(UIEdgeInsets)),@[@"@"]],
        @[@"appSceneVC:didUpdateFromSettings:transitionContext:lifecycleActionType:",@"v",@[@"@",@"@",@"@",@(@encode(uint32_t))]],
        @[@"appSceneVCAppDidExit:",@"v",@[@"@"]],
        @[@"appSceneVC:didInitializeWithError:",@"v",@[@"@",@"@"]],
        @[@"viewDidLayoutSubviews",@"v",@[]],
        @[@"appSceneVC",@"@",@[]],@[@"navigationBar",@"@",@[]],
        @[@"resizeHandle",@"@",@[]],@[@"activatedVerticalConstraints",@"@",@[]],
        @[@"setActivatedVerticalConstraints:",@"v",@[@"@"]],
        @[@"isMaximized",@(@encode(BOOL)),@[]],
        @[@"setIsMaximized:",@"v",@[@(@encode(BOOL))]],
        @[@"scaleRatio",@(@encode(CGFloat)),@[]],
        @[@"setScaleRatio:",@"v",@[@(@encode(CGFloat))]],
        @[@"pidAvailableHandler",@"@?",@[]]];
    Class hostingClass=HostClass(@"VirtualWindowsHostView");
    BOOL compatible=[WindowClass isSubclassOfClass:UIViewController.class] && sceneClass && DockClass &&
        [hostingClass isSubclassOfClass:UIView.class] && OrbitMethodMatches(hostingClass,@"bringSubviewToFront:",@encode(void),@[@"@"]);
    for(NSArray *method in methods)
        compatible=compatible && OrbitMethodMatches(WindowClass,method[0],[method[1] UTF8String],method[2]);
    for(NSString *method in @[@"showDock",@"showDockFromHidden",@"toggleDockVisibility",@"hideDock"])
        compatible=compatible && OrbitMethodMatches(DockClass,method,@encode(void),@[]);
    compatible=compatible && OrbitMethodMatches(sceneClass,@"updateSettingsWithBlock:",@encode(void),@[@"@?"])
        && OrbitMethodMatches(sceneClass,@"setUpAppPresenter",@encode(void),@[])
        && OrbitMethodMatches(sceneClass,@"delegate",@encode(id),@[])
        && OrbitMethodMatches(sceneClass,@"setScaleRatio:",@encode(void),@[@(@encode(CGFloat))])
        && OrbitMethodMatches(sceneClass,@"contentView",@encode(id),@[])
        && OrbitMethodMatches(sceneClass,@"presenter",@encode(id),@[])
        && OrbitMethodMatches(sceneClass,@"isAppRunning",@encode(BOOL),@[]);
    Class remoteClass=HostClass(@"FBScene");
    // A real UIWindow callback catches Swift's deferred addSubview even if
    // its internal showDock() call bypasses the Objective-C selector hook.
    compatible=compatible && OrbitMethodMatches(UIWindow.class,@"didAddSubview:",@encode(void),@[@"@"]);
    compatible=compatible && (OrbitMethodMatches(remoteClass,@"_performUpdateWithoutActivation:",@encode(void),@[@"@?"]) ||
        OrbitMethodMatches(remoteClass,@"_performUpdateWithoutActivation:",@encode(void),@[@"@"]));
    Class parametersClass=HostClass(@"FBSMutableSceneParameters");
    compatible=compatible && (OrbitMethodMatches(parametersClass,@"updateSettingsWithBlock:",@encode(void),@[@"@?"]) ||
        OrbitMethodMatches(parametersClass,@"updateSettingsWithBlock:",@encode(void),@[@"@"]));
    if(!compatible || class_getInstanceMethod(WindowClass,NSSelectorFromString(@"orbit_activate")) ||
       class_getInstanceMethod(WindowClass,NSSelectorFromString(@"orbit_setVisible:"))) {
        if(error) *error=[NSError errorWithDomain:@"LCOrbitMultitask" code:1 userInfo:
            @{NSLocalizedDescriptionKey:@"当前 LC 的多任务窗口接口不兼容，未启用全屏接管。"}];
        return NO;
    }
    class_addMethod(WindowClass,NSSelectorFromString(@"orbit_setVisible:"),(IMP)SetVisible,"v@:B");
    class_addMethod(WindowClass,NSSelectorFromString(@"orbit_activate"),(IMP)Activate,"v@:");
    Replace(WindowClass,@"initWindowName:bundleId:dataUUID:rootVC:",(IMP)InitWindow,&OriginalInit);
    Replace(WindowClass,@"setupDecoratedView",(IMP)Setup,&OriginalSetup);
    Replace(WindowClass,@"updateVerticalConstraints",(IMP)Vertical,&OriginalVertical);
    Replace(WindowClass,@"updateMaximizedFrameWithSettings:",(IMP)Frame,&OriginalFrame);
    Replace(WindowClass,@"updateMaximizedSafeAreaWithSettings:",(IMP)SafeArea,&OriginalSafeArea);
    Replace(WindowClass,@"appSceneVC:didUpdateFromSettings:transitionContext:lifecycleActionType:",(IMP)Settings,&OriginalSettings);
    Replace(WindowClass,@"appSceneVCAppDidExit:",(IMP)Exited,&OriginalExit);
    Replace(WindowClass,@"appSceneVC:didInitializeWithError:",(IMP)Initialized,&OriginalInitialized);
    Replace(WindowClass,@"viewDidLayoutSubviews",(IMP)Layout,&OriginalLayout);
    Replace(WindowClass,@"minimizeWindow",(IMP)Minimize,&OriginalMinimize);
    Replace(DockClass,@"showDock",(IMP)ShowDock,&OriginalShowDock);
    Replace(DockClass,@"showDockFromHidden",(IMP)ShowHidden,&OriginalShowHidden);
    Replace(DockClass,@"toggleDockVisibility",(IMP)ToggleDock,&OriginalToggleDock);
    Replace(UIWindow.class,@"didAddSubview:",(IMP)WindowDidAddSubview,&OriginalWindowDidAddSubview);
    Replace(hostingClass,@"bringSubviewToFront:",(IMP)HostingBringToFront,&OriginalBringToFront);
    Replace(sceneClass,@"updateSettingsWithBlock:",(IMP)SceneSettings,&OriginalSceneSettings);
    Replace(parametersClass,@"updateSettingsWithBlock:",(IMP)InitialSceneSettings,&OriginalInitialSettings);
    Replace(sceneClass,@"setUpAppPresenter",(IMP)PresenterReady,&OriginalPresenter);
    installed=YES;
    return YES;
}
+ (void)refreshPresentation {
    if(!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{[self refreshPresentation];});return; }
    if(!WindowClass || ![LCOrbitHost isHostUI]) return;
    NSMutableSet *found=[NSMutableSet set];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class]) continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows)
            FindWindows(window.rootViewController,found);
    }
    // Persist visibility across deferred native Dock animations and mode changes.
    SyncNativeDockSurface();
    if(Fullscreen() && found.count) {
        InstallFinalSceneHook();
        UIViewController *active=[self activeWindow];
        if(active.view.hidden || active.view.alpha<.1) active=nil;
        if(!active) for(UIViewController *window in found)
            if(!window.view.hidden) active=window;
        for(UIViewController *window in found) LayoutFullscreen(window);
        if(active) Activate(active,NSSelectorFromString(@"orbit_activate"));
    } else {
        BOOL restored=NO;
        for(UIViewController *window in found) {
            restored|=objc_getAssociatedObject(window,&SnapshotKey)!=nil;
            RestoreAppearance(window);
        }
        if(restored && OriginalShowDock) {
            ((void(*)(id,SEL))OriginalShowDock)(Dock(),NSSelectorFromString(@"showDock"));
            // LC's hide animation clears isVisible only in its completion.
            // A quick off/on/off must not leave the restored Dock invisible.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                if(!Fullscreen() && [LCOrbitMultitask windows].count)
                    ((void(*)(id,SEL))OriginalShowDock)(Dock(),NSSelectorFromString(@"showDock"));
            });
        }
    }
}
@end
