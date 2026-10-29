#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "LCOrbit/Core/LCOrbitCore.h"
#import "LCOrbit/Core/LCOrbitStorage.h"
#import "LCOrbit/Core/LCOrbitGuestService.h"
#import "LCOrbit/Core/LCOrbitMultitask.h"
#import "LCOrbit/Core/LCOrbitHost.h"

// Only host/task/presentation boundaries are fixtures; layout and menu actions
// below execute the real LCFloatingMenu and Core linked into this simulator app.
@interface FMManager : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *overlayView;
@property(nonatomic,strong) LCOrbitContext *orbitContext;
@property(nonatomic,strong) UIButton *orb;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) NSArray *apps;
@property(nonatomic,copy) NSString *page;
@property(nonatomic,assign) CGFloat orbY;
@property(nonatomic,assign) BOOL left;
@property(nonatomic,assign) BOOL isOpen;
@property(nonatomic,weak) UIScrollView *appsScroll;
@property(nonatomic,assign) CGFloat appsScrollOffset;
- (NSArray<NSDictionary *> *)orderedAppsForMenu;
- (void)rememberCurrentApp;
- (void)loadAppsScroll;
- (void)persistAppsScroll;
- (void)draw;
- (void)refreshAppsContent;
- (void)populateSettingsCategory:(NSString *)category stack:(UIStackView *)stack;
- (void)closeTaskFromButton:(UIControl *)sender;
- (void)closeMultitaskGuest;
- (void)pan:(UIPanGestureRecognizer *)gesture;
@end
@interface NSUserDefaults (DrawerFixture) @end
@implementation NSUserDefaults (DrawerFixture)
+ (BOOL)isLiveProcess { return YES; } // Suppress injection bootstrap only.
@end
static NSArray *FixtureApps;
static BOOL FixtureCurrent, FixtureRunning=YES;
static CGFloat FixtureWidth=667;
static NSUInteger CloseCount, PositionWrites;
static UIAlertController *CapturedAlert;
static NSMutableArray *Results;
static NSMutableArray *Managers;
static NSString *EvidencePath;
static void SwapClass(Class c,SEL a,SEL b) { method_exchangeImplementations(class_getClassMethod(c,a),class_getClassMethod(c,b)); }
static void SwapInstance(Class c,SEL a,SEL b) { method_exchangeImplementations(class_getInstanceMethod(c,a),class_getInstanceMethod(c,b)); }
@interface LCOrbitGuestService (DrawerFixture) @end
@implementation LCOrbitGuestService (DrawerFixture)
+ (NSArray *)fixtureApps { return FixtureApps; }
+ (BOOL)fixtureCurrent:(NSDictionary *)app { return FixtureCurrent && [app[@"identity"] isEqual:FixtureApps.firstObject[@"identity"]]; }
@end
@interface LCOrbitMultitask (DrawerFixture) @end
@implementation LCOrbitMultitask (DrawerFixture)
+ (BOOL)fixtureRunning:(NSDictionary *)app { return FixtureRunning && [app[@"identity"] isEqual:FixtureApps.firstObject[@"identity"]]; }
+ (BOOL)fixtureEnabled { return YES; }
+ (BOOL)fixtureCurrent:(NSDictionary *)app { return FixtureCurrent && [app[@"identity"] isEqual:FixtureApps.firstObject[@"identity"]]; }
+ (BOOL)fixtureClose:(NSDictionary *)app error:(NSError **)error { CloseCount++;return YES; }
@end
@interface LCOrbitHost (DrawerFixture) @end
@implementation LCOrbitHost (DrawerFixture)
+ (BOOL)fixtureHost { return YES; }
@end
@interface LCOrbitPreferences (DrawerFixture) @end
@implementation LCOrbitPreferences (DrawerFixture)
- (void)fixtureSetObject:(id)object forKey:(NSString *)key {
    if([@[@"LCFloatingMenu.orbY",@"LCFloatingMenu.onLeft"] containsObject:key]) PositionWrites++;
    [self fixtureSetObject:object forKey:key];
}
@end
@interface UIViewController (DrawerFixture) @end
@implementation UIViewController (DrawerFixture)
- (void)fixturePresent:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if([controller isKindOfClass:UIAlertController.class]) { CapturedAlert=(UIAlertController *)controller;if(completion) completion();return; }
    [self fixturePresent:controller animated:animated completion:completion];
}
@end
@interface GeometryWindow : UIWindow
@property(nonatomic,assign) CGSize fixtureSize;
@property(nonatomic,assign) UIEdgeInsets fixtureInsets;
@end
@implementation GeometryWindow
- (CGRect)bounds { return (CGRect){CGPointZero,self.fixtureSize}; }
- (UIEdgeInsets)safeAreaInsets { return self.fixtureInsets; }
@end
@interface FixturePan : UIPanGestureRecognizer
@property(nonatomic,assign) UIGestureRecognizerState fixtureState;
@property(nonatomic,assign) CGPoint fixturePoint;
@end
@implementation FixturePan
- (UIGestureRecognizerState)state { return self.fixtureState; }
- (CGPoint)locationInView:(UIView *)view { return self.fixturePoint; }
@end
static NSArray<UIView *> *Views(UIView *root) {
    NSMutableArray *found=[NSMutableArray array];if(root)[found addObject:root];
    for(UIView *v in root.subviews) [found addObjectsFromArray:Views(v)];return found;
}
static NSArray<UIControl *> *Actions(FMManager *m,NSString *action) {
    NSMutableArray *found=[NSMutableArray array];
    for(UIView *v in Views(m.panel)) if([v isKindOfClass:UIControl.class] && [[(UIControl *)v actionsForTarget:m forControlEvent:UIControlEventTouchUpInside] containsObject:action]) [found addObject:v];
    return found;
}
static void Check(NSString *name,BOOL passed,id details) {
    [Results addObject:@{@"name":name,@"passed":@(passed),@"details":details?:@{}}];
    NSLog(@"%@ %@ %@",passed?@"PASS":@"FAIL",name,details?:@"");
}
static CGRect Frame(UIView *v,FMManager *m) { return [v convertRect:v.bounds toView:m.overlayView]; }
static FMManager *Manager(BOOL compact,CGFloat scale,CGFloat height,UIEdgeInsets insets,BOOL left,BOOL opened,NSString *page) {
    LCOrbitPreferences *p=[LCOrbitStorage preferences];
    [p setObject:@(compact) forKey:@"LCFloatingMenu.compactMode"];
    [p setObject:@(scale) forKey:@"LCFloatingMenu.panelScale"];
    GeometryWindow *window=[[GeometryWindow alloc] initWithFrame:CGRectMake(0,0,FixtureWidth,height)];window.fixtureSize=CGSizeMake(FixtureWidth,height);window.fixtureInsets=insets;
    window.rootViewController=[UIViewController new];window.rootViewController.view.frame=window.bounds;
    FMManager *m=[FMManager new];m.window=window;m.overlayView=[[UIView alloc] initWithFrame:window.bounds];
    [window.rootViewController.view addSubview:m.overlayView];m.orbitContext=[LCOrbitContext new];m.orbY=.5;m.left=left;m.isOpen=opened;m.page=page;m.apps=FixtureApps;
    [m draw];[m.overlayView layoutIfNeeded];[m.panel layoutIfNeeded];[m.appsScroll layoutIfNeeded];[Managers addObject:m];return m;
}
static void Snapshot(FMManager *m,NSString *name) {
    UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc] initWithSize:m.overlayView.bounds.size];
    UIImage *image=[r imageWithActions:^(UIGraphicsImageRendererContext *context){
        [[UIColor colorWithWhite:.16 alpha:1] setFill];UIRectFill(m.overlayView.bounds);
        [m.overlayView.layer renderInContext:context.CGContext];
    }];[UIImagePNGRepresentation(image) writeToFile:[EvidencePath stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
}
static void RunTests(void) {
    UIEdgeInsets ordinary=UIEdgeInsetsMake(0,0,21,0);
    LCOrbitPreferences *prefs=[LCOrbitStorage preferences];
    [prefs setObject:@NO forKey:@"LCFloatingMenu.recentAppsFirst"];
    for(NSNumber *compact in @[@NO,@YES]) for(NSNumber *height in @[@320,@375]) {
        FMManager *m=Manager(compact.boolValue,1,height.doubleValue,ordinary,NO,YES,@"apps");
        CGRect list=Frame(m.appsScroll,m);CGFloat headerEnd=CGRectGetMinY(list),footerStart=CGFLOAT_MAX;
        for(UIControl *control in Actions(m,@"switchFromRow:")) if(![control isDescendantOfView:m.appsScroll]) headerEnd=MAX(headerEnd,CGRectGetMaxY(Frame(control,m)));
        for(NSString *selector in @[@"compactReturnHome",@"goHome",@"closeMultitaskGuest",@"openSettings"]) for(UIControl *control in Actions(m,selector)) footerStart=MIN(footerStart,CGRectGetMinY(Frame(control.superview,m)));
        BOOL good=m.panel && list.size.height>=44-.01 && headerEnd<=CGRectGetMinY(list)+.01 && CGRectGetMaxY(list)<=footerStart+.01;
        NSString *name=[NSString stringWithFormat:@"short-%@-%@",compact.boolValue?@"compact":@"normal",height];
        Check(name,good,@{@"list":NSStringFromCGRect(list),@"headerEnd":@(headerEnd),@"footerStart":@(footerStart)});Snapshot(m,name);
    }
    for(NSNumber *compact in @[@NO,@YES]) for(NSNumber *scale in @[@.50,@.75,@1,@1.2]) {
        FMManager *m=Manager(compact.boolValue,scale.doubleValue,667,ordinary,NO,YES,@"apps");
        NSArray *close=Actions(m,@"closeTaskFromButton:");BOOL good=close.count>0,distinct=YES;NSMutableArray *frames=[NSMutableArray array];
        for(UIControl *c in close) {
            CGRect f=Frame(c,m);[frames addObject:NSStringFromCGRect(f)];
            CGFloat minimum=compact.boolValue?(scale.doubleValue<.75?16:24):48;
            good &= f.size.width>=minimum-.01 && f.size.height>=minimum-.01;
            UIControl *switcher=nil;for(UIControl *s in Actions(m,@"switchFromRow:")) if(s.superview==c.superview) switcher=s;
            if(!switcher) { distinct=NO;continue; }
            CGRect sf=Frame(switcher,m);BOOL found=NO;
            if(compact.boolValue) {
                UIView *hit=[m.overlayView hitTest:CGPointMake(CGRectGetMidX(sf),CGRectGetMidY(sf)) withEvent:nil];
                found=(hit==switcher || [hit isDescendantOfView:switcher]) &&
                    CGRectGetMidX(f)>CGRectGetMidX(sf) && CGRectGetMidY(f)<CGRectGetMidY(sf) &&
                    fabs(c.superview.bounds.size.height-63)<.01;
            } else for(CGFloat x=CGRectGetMinX(sf)+24;x<=CGRectGetMaxX(sf)-24;x+=2) {
                CGRect candidate=CGRectMake(x-24,CGRectGetMidY(sf)-24,48,48);
                CGPoint center=CGPointMake(x,CGRectGetMidY(sf));UIView *hit=[m.overlayView hitTest:center withEvent:nil];
                if(!CGRectIntersectsRect(candidate,f) && (hit==switcher || [hit isDescendantOfView:switcher])) { found=YES;break; }
            }
            distinct &= found;
        }
        NSString *name=[NSString stringWithFormat:@"targets-%@-%.0f",compact.boolValue?@"compact":@"normal",scale.doubleValue*100];
        Check(name,good && distinct,@{@"closeFrames":frames,@"switchCenterAccessible":@(distinct)});Snapshot(m,name);
    }
    for(NSNumber *scale in @[@.50,@.75,@1,@1.2]) {
        FMManager *m=Manager(NO,scale.doubleValue,667,ordinary,NO,YES,@"apps");
        NSMutableArray<UIControl *> *buttons=[NSMutableArray array];
        for(NSString *action in @[@"goHome",@"closeMultitaskGuest",@"openSettings",@"toggle"])
            [buttons addObjectsFromArray:Actions(m,action)];
        BOOL centersWork=buttons.count==4,blankIsInactive=YES;
        for(UIControl *button in buttons) {
            UIView *tile=button.subviews.firstObject;
            if(!tile) {centersWork=NO;continue;}
            CGRect visible=Frame(tile,m);
            CGPoint center=CGPointMake(CGRectGetMidX(visible),CGRectGetMidY(visible));
            UIView *hit=[m.overlayView hitTest:center withEvent:nil];
            centersWork &= hit==button || [hit isDescendantOfView:button];
            CGPoint outside[]={CGPointMake(CGRectGetMinX(visible)-1,center.y),
                               CGPointMake(CGRectGetMaxX(visible)+1,center.y),
                               CGPointMake(center.x,CGRectGetMinY(visible)-1),
                               CGPointMake(center.x,CGRectGetMaxY(visible)+1)};
            for(NSUInteger i=0;i<4;i++) {
                hit=[m.overlayView hitTest:outside[i] withEvent:nil];
                for(UIControl *candidate in buttons)
                    blankIsInactive &= hit!=candidate && ![hit isDescendantOfView:candidate];
            }
        }
        Check([NSString stringWithFormat:@"normal-footer-icon-only-%.0f",scale.doubleValue*100],
              centersWork && blankIsInactive,@{@"iconCentersWork":@(centersWork),@"surroundingBlankInactive":@(blankIsInactive)});
    }
    for(NSNumber *left in @[@NO,@YES]) {
        UIEdgeInsets insets=UIEdgeInsetsMake(0,59,21,35);FMManager *m=Manager(NO,1,375,insets,left.boolValue,NO,@"apps");
        CGRect orb=Frame(m.orb,m);BOOL safe=CGRectGetMinX(orb)>=insets.left-.01 && CGRectGetMaxX(orb)<=667-insets.right+.01;
        Check([NSString stringWithFormat:@"horizontal-safe-handle-%@",left],safe,NSStringFromCGRect(orb));
        m.isOpen=YES;[m draw];[m.overlayView layoutIfNeeded];safe=YES;
        for(UIControl *c in Actions(m,@"switchFromRow:")) {CGRect f=Frame(c,m);safe &= CGRectGetMinX(f)>=insets.left-.01 && CGRectGetMaxX(f)<=667-insets.right+.01;}
        Check([NSString stringWithFormat:@"horizontal-safe-content-%@",left],safe,NSStringFromCGRect(m.panel.frame));Snapshot(m,[NSString stringWithFormat:@"safe-%@",left]);
    }
    FixtureCurrent=YES;FMManager *header=Manager(NO,1,667,ordinary,NO,YES,@"apps");UIControl *tile=nil;
    for(UIControl *c in Actions(header,@"switchFromRow:")) if(![c isDescendantOfView:header.appsScroll]) {tile=c;break;}
    BOOL disabled=tile && !tile.enabled;Snapshot(header,@"current-running-close");FixtureCurrent=NO;[header refreshAppsContent];BOOL enabled=NO;
    for(UIControl *c in Actions(header,@"switchFromRow:")) if(![c isDescendantOfView:header.appsScroll]) {enabled=c.enabled;break;}
    Check(@"header-refresh-current-state",disabled && enabled,@{@"disabledBefore":@(disabled),@"enabledAfter":@(enabled)});
    NSUInteger headerCount=0;for(UIControl *c in Actions(header,@"switchFromRow:")) if(![c isDescendantOfView:header.appsScroll]) headerCount++;
    for(NSUInteger i=0;i<3;i++) [header refreshAppsContent];
    NSUInteger refreshedCount=0;for(UIControl *c in Actions(header,@"switchFromRow:")) if(![c isDescendantOfView:header.appsScroll]) refreshedCount++;
    Check(@"header-refresh-does-not-duplicate",headerCount>0 && refreshedCount==headerCount,@{@"before":@(headerCount),@"after":@(refreshedCount)});
    for(NSNumber *compact in @[@NO,@YES]) {
        FixtureRunning=YES;FMManager *closing=Manager(compact.boolValue,1,667,ordinary,NO,YES,@"apps");
        UIControl *close=Actions(closing,@"closeTaskFromButton:").firstObject;
        CapturedAlert=nil;CloseCount=0;[closing closeTaskFromButton:close];
        Check(compact.boolValue?@"compact-close-immediate":@"normal-close-immediate",!CapturedAlert && CloseCount==1 && !close.enabled,@{@"alert":@(CapturedAlert!=nil),@"closeCalls":@(CloseCount)});
    }
    FixtureRunning=YES;FMManager *closing=Manager(YES,1,667,ordinary,NO,YES,@"apps");
    UIControl *close=Actions(closing,@"closeTaskFromButton:").firstObject;
    CapturedAlert=nil;CloseCount=0;FixtureRunning=NO;[closing closeTaskFromButton:close];
    Check(@"close-rejects-stale-target",CloseCount==0 && close.enabled,@{@"closeCalls":@(CloseCount)});FixtureRunning=YES;
    FixtureCurrent=YES;closing=Manager(NO,1,667,ordinary,NO,YES,@"apps");
    CapturedAlert=nil;CloseCount=0;[closing closeMultitaskGuest];
    Check(@"footer-close-immediate",!CapturedAlert && CloseCount==1 && !closing.isOpen,@{@"closeCalls":@(CloseCount),@"alert":@(CapturedAlert!=nil)});FixtureCurrent=NO;
    FMManager *pan=Manager(NO,1,667,ordinary,NO,NO,@"apps");CGRect saved=pan.orb.frame;PositionWrites=0;
    FixturePan *g=[FixturePan new];g.fixturePoint=CGPointMake(150,180);g.fixtureState=UIGestureRecognizerStateBegan;[pan pan:g];g.fixtureState=UIGestureRecognizerStateChanged;[pan pan:g];g.fixtureState=UIGestureRecognizerStateCancelled;[pan pan:g];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.6*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Check(@"cancelled-pan-restores-position",CGRectEqualToRect(saved,pan.orb.frame) && PositionWrites==0,@{@"saved":NSStringFromCGRect(saved),@"actual":NSStringFromCGRect(pan.orb.frame),@"positionWrites":@(PositionWrites)});
    });
    LCOrbitPreferences *p=[LCOrbitStorage preferences];[p setObject:@YES forKey:@"LCFloatingMenu.roundOrb"];[p setObject:@YES forKey:@"LCFloatingMenu.autoFade"];
    FMManager *legacy=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    Check(@"legacy-round-orb-ignored",legacy.orb.bounds.size.height>legacy.orb.bounds.size.width*2,NSStringFromCGRect(legacy.orb.frame));
    for(NSString *page in @[@"settings",@"diy",@"manage"]) {
        FMManager *m=Manager(NO,1,667,ordinary,NO,YES,page);BOOL removed=YES;
        for(UIView *v in Views(m.panel)) if([v isKindOfClass:UILabel.class]) {NSString *t=((UILabel *)v).text;removed &= ![t containsString:@"圆形微珠"] && ![t containsString:@"闲置贴边待命"];}
        Check([@"removed-controls-" stringByAppendingString:page],removed,nil);Snapshot(m,[@"settings-" stringByAppendingString:page]);
    }
    for(NSString *category in @[@"appearance",@"behavior"]) {
        FMManager *m=Manager(NO,1,667,ordinary,NO,NO,@"apps");
        UIStackView *stack=[[UIStackView alloc] initWithFrame:CGRectMake(20,20,400,620)];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=10;
        [m.overlayView addSubview:stack];[m populateSettingsCategory:category stack:stack];[stack layoutIfNeeded];
        BOOL removed=YES;for(UIView *v in Views(stack)) if([v isKindOfClass:UILabel.class]) {NSString *t=((UILabel *)v).text;removed &= ![t containsString:@"圆形微珠"] && ![t containsString:@"闲置贴边待命"];}
        Check([@"removed-native-category-" stringByAppendingString:category],removed,nil);Snapshot(m,[@"settings-native-" stringByAppendingString:category]);
    }
    // Recent ordering is opt-in, uses scoped identities, and never modifies
    // the saved manual order. Only reopening resets scroll, not row refresh.
    FMManager *recency=Manager(NO,1,667,ordinary,NO,YES,@"apps");
    NSArray *manual=[recency orderedAppsForMenu];
    id manualOrderBefore=[prefs objectForKey:@"LCFloatingMenu.menuOrder"];
    NSDictionary *second=FixtureApps[2],*third=FixtureApps[3];
    [prefs setObject:@[third[@"identity"],second[@"identity"]] forKey:@"LCFloatingMenu.recentOpenedAppKeys"];
    Check(@"recent-off-keeps-manual-order",[recency orderedAppsForMenu].firstObject==manual.firstObject,nil);
    [prefs setObject:@YES forKey:@"LCFloatingMenu.recentAppsFirst"];
    NSArray *ordered=[recency orderedAppsForMenu];
    Check(@"recent-on-moves-opened-to-front",ordered.count==manual.count &&
          ordered[0]==third && ordered[1]==second,nil);
    Check(@"recent-on-keeps-manual-preference",
          (manualOrderBefore==nil && [prefs objectForKey:@"LCFloatingMenu.menuOrder"]==nil) ||
          [manualOrderBefore isEqual:[prefs objectForKey:@"LCFloatingMenu.menuOrder"]],nil);
    FixtureCurrent=YES;
    [recency rememberCurrentApp];
    NSArray *savedRecent=[prefs objectForKey:@"LCFloatingMenu.recentOpenedAppKeys"];
    Check(@"recent-current-becomes-first",[savedRecent.firstObject isEqual:FixtureApps[0][@"identity"]] &&
          [recency orderedAppsForMenu].firstObject==FixtureApps[0],nil);
    FixtureCurrent=NO;
    [prefs setObject:@(93) forKey:@"LCFloatingMenu.appsScrollOffset"];
    recency.appsScrollOffset=51;
    [recency loadAppsScroll];
    Check(@"recent-on-open-resets-scroll",fabs(recency.appsScrollOffset)<.01,nil);
    recency.appsScrollOffset=65;
    [recency persistAppsScroll];
    Check(@"recent-on-does-not-overwrite-saved-scroll",
          [[prefs objectForKey:@"LCFloatingMenu.appsScrollOffset"] doubleValue]==93,nil);
    [prefs setObject:@NO forKey:@"LCFloatingMenu.recentAppsFirst"];
    [recency loadAppsScroll];
    Check(@"recent-off-restores-scroll",fabs(recency.appsScrollOffset-93)<.01 &&
          [recency orderedAppsForMenu].firstObject==manual.firstObject,nil);
    FixtureWidth=402;
    FMManager *portrait=Manager(NO,1,874,UIEdgeInsetsMake(62,0,34,0),NO,YES,@"apps");
    Snapshot(portrait,@"normal-portrait");
    FixtureWidth=667;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3.8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        UIView *bead=[legacy.orb viewWithTag:9202];
        Check(@"legacy-auto-fade-ignored",bead && CGAffineTransformIsIdentity(bead.transform) && bead.alpha>=.99,@{@"alpha":@(bead.alpha),@"transform":NSStringFromCGAffineTransform(bead.transform)});
        NSUInteger failures=0;for(NSDictionary *r in Results) if(![r[@"passed"] boolValue]) failures++;
        NSDictionary *report=@{@"kind":@"production-uikit-synthetic-host-fixtures",@"runtime":UIDevice.currentDevice.systemVersion,@"count":@(Results.count),@"failures":@(failures),@"results":Results,@"limitation":@"Real UIKit simulator; synthetic host window dimensions and task state. Does not validate LC SwiftUI host integration, hardware sensor occlusion or actual guest process closure."};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[EvidencePath stringByAppendingPathComponent:@"result.json"] atomically:YES];
        NSLog(@"DRAWER_TESTS_DONE failures=%lu",(unsigned long)failures);
    });
}
@interface DrawerController : UIViewController @end
@implementation DrawerController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];static BOOL ran=NO;if(ran)return;ran=YES;
    NSString *home=NSHomeDirectory();setenv("LC_HOME_PATH",home.UTF8String,1);EvidencePath=[home stringByAppendingPathComponent:@"Documents/DrawerEvidence"];
    [NSFileManager.defaultManager createDirectoryAtPath:EvidencePath withIntermediateDirectories:YES attributes:nil error:nil];
    Results=[NSMutableArray array];Managers=[NSMutableArray array];NSMutableArray *apps=[NSMutableArray array];
    for(NSUInteger i=0;i<8;i++) {NSString *folder=[home stringByAppendingFormat:@"/Documents/Fixture%lu.app",(unsigned long)i];[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];[@{@"CFBundleName":[NSString stringWithFormat:@"App %lu",(unsigned long)i]} writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES];[apps addObject:@{@"folder":folder,@"title":[NSString stringWithFormat:@"App %lu",(unsigned long)i],@"identity":folder,@"path":folder,@"launchable":@YES}];}FixtureApps=apps;
    SwapClass(LCOrbitGuestService.class,@selector(installedApps),@selector(fixtureApps));SwapClass(LCOrbitGuestService.class,@selector(isCurrentGuest:),@selector(fixtureCurrent:));
    SwapClass(LCOrbitMultitask.class,@selector(isCurrentGuest:),@selector(fixtureCurrent:));SwapClass(LCOrbitMultitask.class,@selector(isRunningGuest:),@selector(fixtureRunning:));SwapClass(LCOrbitMultitask.class,@selector(closeGuest:error:),@selector(fixtureClose:error:));SwapClass(LCOrbitMultitask.class,@selector(isEnabled),@selector(fixtureEnabled));SwapClass(LCOrbitHost.class,@selector(isHostUI),@selector(fixtureHost));
    SwapInstance(LCOrbitPreferences.class,@selector(setObject:forKey:),@selector(fixtureSetObject:forKey:));SwapInstance(UIViewController.class,@selector(presentViewController:animated:completion:),@selector(fixturePresent:animated:completion:));
    RunTests();
}
@end
@interface DrawerDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation DrawerDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[DrawerController new];[self.window makeKeyAndVisible];return YES;}
@end
int main(int argc,char **argv) {@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(DrawerDelegate.class));}}
