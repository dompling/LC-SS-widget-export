#import "LCOrbitHostSettings.h"
#import "LCOrbitHost.h"
#import "LCOrbitLog.h"
#import "LCOrbitMultitask.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Standalone plugin recovery path. No SwiftUI private hooks, no floating window,
// no dependency on the FloatingMenu module's enabled state.
static NSString *const NativeRowRequest=@"LCOrbitOpenHostSettings";
static void (^OpenPluginSettings)(UIWindowScene *);
static id SettingsObserver;
static NSMutableArray *LifecycleObservers;
static LCOrbitHostSettings *GestureTarget;
static char DataManagementPressKey,TwoFingerPressKey;

// Recognize the real localized SwiftUI setting, not a hard-coded screen Y value.
static BOOL IsDataManagementTitle(NSString *label) {
    if(![label isKindOfClass:NSString.class]) return NO;
    NSString *text=[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([text isEqualToString:@"数据管理"] || [text isEqualToString:@"Data Management"] ||
       [text isEqualToString:@"資料管理"]) return YES;
    NSString *localized=[NSBundle.mainBundle localizedStringForKey:@"lc.settings.dataManagement" value:nil table:nil];
    return localized.length && ![localized isEqualToString:@"lc.settings.dataManagement"] &&
           [text isEqualToString:localized];
}
static BOOL HostGestureAllowed(BOOL host,BOOL foreground,BOOL activeTask) {
    return host && foreground && !activeTask;
}

static BOOL MatchesRowRect(CGRect rect,CGPoint point,CGFloat width) {
    if(CGRectIsEmpty(rect) || !isfinite(rect.origin.y) || !isfinite(rect.size.height) ||
       rect.size.height>130 || rect.size.width<20 || width<180) return NO;
    return point.y>=CGRectGetMinY(rect)-26 && point.y<=CGRectGetMaxY(rect)+26 &&
           point.x>=8 && point.x<=width-8;
}
static BOOL HasDataManagementAtPoint(UIView *view,UIWindow *window,CGPoint point,NSUInteger *remaining) {
    if(!view || !*remaining || view.hidden || view.alpha<.03) return NO;
    --*remaining;
    NSString *label=view.accessibilityLabel;
    if([view isKindOfClass:UILabel.class] && IsDataManagementTitle(((UILabel *)view).text))
        label=((UILabel *)view).text;
    if(IsDataManagementTitle(label)) {
        CGRect rect=[view convertRect:view.bounds toView:window];
        if(MatchesRowRect(rect,point,CGRectGetWidth(window.bounds))) return YES;
    }
    // SwiftUI sometimes exposes Text only as UIAccessibilityElement.
    NSArray *elements=view.accessibilityElements;
    if([elements isKindOfClass:NSArray.class]) for(id element in elements) {
        if(!*remaining) break;
        --*remaining;
        NSString *name=[element respondsToSelector:@selector(accessibilityLabel)] ?
            [element accessibilityLabel]:nil;
        if(!IsDataManagementTitle(name)) continue;
        CGRect screenRect=[element respondsToSelector:@selector(accessibilityFrame)] ?
            [element accessibilityFrame]:CGRectNull;
        CGRect rect=[window convertRect:screenRect fromWindow:nil];
        if(MatchesRowRect(rect,point,CGRectGetWidth(window.bounds))) return YES;
    }
    for(UIView *child in view.subviews)
        if(HasDataManagementAtPoint(child,window,point,remaining)) return YES;
    return NO;
}

@interface LCOrbitHostSettings () <UIGestureRecognizerDelegate>
@end
@implementation LCOrbitHostSettings
+ (void)installWithOpenSettings:(void (^)(UIWindowScene *))openSettings {
    if(!NSThread.isMainThread || ![LCOrbitHost isHostUI]) return;
    OpenPluginSettings=[openSettings copy];
    if(!GestureTarget) GestureTarget=[self new];
    if(!SettingsObserver) {
        SettingsObserver=[NSNotificationCenter.defaultCenter addObserverForName:NativeRowRequest
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                if(![LCOrbitHost isHostUI] || !OpenPluginSettings) return;
                UIWindowScene *scene=[LCOrbitHost activeScene];
                NSMutableDictionary *reply=note.userInfo[@"reply"];
                if(!scene || ![reply isKindOfClass:NSMutableDictionary.class]) return;
                reply[@"handled"]=@YES;
                OpenPluginSettings(scene);
            }];
    }
    if(!LifecycleObservers) {
        LifecycleObservers=[NSMutableArray array];
        for(NSString *name in @[UIApplicationDidBecomeActiveNotification,
                                UIApplicationWillEnterForegroundNotification,
                                UISceneDidActivateNotification,
                                UISceneWillEnterForegroundNotification,
                                UIWindowDidBecomeVisibleNotification]) {
            id token=[NSNotificationCenter.defaultCenter addObserverForName:name object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    [self attachToHostWindows];
                }];
            if(token) [LifecycleObservers addObject:token];
        }
    }
    [self attachToHostWindows];
    [LCOrbitLog appendEvent:@"recovery-gestures-installed" details:nil kind:@"runtime"];
}
+ (void)attachToHostWindows {
    if(![LCOrbitHost isHostUI]) return;
    UIWindowScene *scene=[LCOrbitHost activeScene];
    if(!scene) return;
    for(UIWindow *window in scene.windows) {
        if(window.hidden || window.windowLevel!=UIWindowLevelNormal || !window.rootViewController) continue;
        if(!objc_getAssociatedObject(window,&DataManagementPressKey)) {
            UILongPressGestureRecognizer *row=[[UILongPressGestureRecognizer alloc]
                initWithTarget:GestureTarget action:@selector(openFromLongPress:)];
            row.minimumPressDuration=.8;
            row.cancelsTouchesInView=YES;
            row.delegate=GestureTarget;
            [window addGestureRecognizer:row];
            objc_setAssociatedObject(window,&DataManagementPressKey,row,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if(!objc_getAssociatedObject(window,&TwoFingerPressKey)) {
            UILongPressGestureRecognizer *recovery=[[UILongPressGestureRecognizer alloc]
                initWithTarget:GestureTarget action:@selector(openFromLongPress:)];
            recovery.numberOfTouchesRequired=2;
            recovery.minimumPressDuration=1.2;
            recovery.cancelsTouchesInView=NO;
            recovery.delegate=GestureTarget;
            [window addGestureRecognizer:recovery];
            objc_setAssociatedObject(window,&TwoFingerPressKey,recovery,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if(!HostGestureAllowed([LCOrbitHost isHostUI],[LCOrbitHost activeScene]!=nil,
                            [LCOrbitMultitask activeWindow]!=nil)) return NO;
    UIWindow *window=(UIWindow *)gestureRecognizer.view;
    if(![window isKindOfClass:UIWindow.class] || window.windowLevel!=UIWindowLevelNormal) return NO;
    if(gestureRecognizer==objc_getAssociatedObject(window,&TwoFingerPressKey)) return YES;
    if(gestureRecognizer!=objc_getAssociatedObject(window,&DataManagementPressKey)) return NO;
    NSUInteger remaining=1400;
    return HasDataManagementAtPoint(window,window,[touch locationInView:window],&remaining);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
- (void)openFromLongPress:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan) return;
    if(!HostGestureAllowed([LCOrbitHost isHostUI],[LCOrbitHost activeScene]!=nil,
                            [LCOrbitMultitask activeWindow]!=nil) || !OpenPluginSettings) return;
    UIWindow *window=(UIWindow *)gesture.view;
    if(![window isKindOfClass:UIWindow.class]) return;
    UIWindowScene *scene=window.windowScene;
    if(!scene || scene!=[LCOrbitHost activeScene]) return;
    [LCOrbitLog appendEvent:@"recovery-settings-opened" details:nil kind:@"runtime"];
    OpenPluginSettings(scene);
}
@end
