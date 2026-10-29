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
- (void)automaticPiPChanged:(UISwitch *)control;
- (void)sortDrag:(UILongPressGestureRecognizer *)gesture;
- (void)pan:(UIPanGestureRecognizer *)gesture;
@end
@interface NSUserDefaults (DrawerFixture) @end
@implementation NSUserDefaults (DrawerFixture)
+ (BOOL)isLiveProcess { return YES; } // Suppress injection bootstrap only.
@end
static NSArray *FixtureApps;
static BOOL FixtureCurrent, FixtureRunning=YES, FixtureHost=YES;
static CGFloat FixtureWidth=667;
static NSUInteger CloseCount, PositionWrites;
static NSMutableDictionary *AutoPiPStates;
static NSDictionary *LastAutoPiPTarget;
static BOOL RejectAutoPiP;
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
+ (BOOL)fixtureAutoPiP:(NSDictionary *)app { return [AutoPiPStates[app[@"identity"]] boolValue]; }
+ (BOOL)fixtureSetAutoPiP:(BOOL)enabled forGuest:(NSDictionary *)app error:(NSError **)error {
    if(RejectAutoPiP) {
        if(error) *error=[NSError errorWithDomain:@"DrawerFixture" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"Fixture configuration write rejected"}];
        return NO;
    }
    LastAutoPiPTarget=app;AutoPiPStates[app[@"identity"]]=@(enabled);return YES;
}
@end
@interface LCOrbitHost (DrawerFixture) @end
@implementation LCOrbitHost (DrawerFixture)
+ (BOOL)fixtureHost { return FixtureHost; }
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
@interface FixtureLongPress : UILongPressGestureRecognizer
@property(nonatomic,assign) UIGestureRecognizerState fixtureState;
@property(nonatomic,assign) CGPoint fixturePoint;
@end
@implementation FixtureLongPress
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
    // Test actual UIKit hit-testing, not just the visible 16pt bead frame.
    // Old symmetric -14pt expansion left only ~30pt reachable on the screen.
    for(NSNumber *left in @[@NO,@YES]) for(NSNumber *scale in @[@.70,@1,@1.9]) {
        [prefs setObject:scale forKey:@"LCFloatingMenu.orbScale"];
        FMManager *handle=Manager(NO,1,667,ordinary,left.boolValue,NO,@"apps");
        CGRect frame=Frame(handle.orb,handle);
        CGFloat edge=left.boolValue?CGRectGetMinX(frame):CGRectGetMaxX(frame);
        CGFloat cy=CGRectGetMidY(frame);
        CGFloat sign=left.boolValue?1:-1;
        CGPoint inside=CGPointMake(edge+sign*42,cy);
        CGPoint outside=CGPointMake(edge+sign*46,cy);
        UIView *hit=[handle.overlayView hitTest:inside withEvent:nil];
        UIView *miss=[handle.overlayView hitTest:outside withEvent:nil];
        BOOL works=hit==handle.orb && miss!=handle.orb;
        Check([NSString stringWithFormat:@"bead-inward-hit-%@-%.0f",
               left.boolValue?@"left":@"right",scale.doubleValue*100],works,
              @{ @"frame":NSStringFromCGRect(frame),@"inside":NSStringFromCGPoint(inside),
                 @"outside":NSStringFromCGPoint(outside),@"hit":@(hit==handle.orb),
                 @"outsideMiss":@(miss!=handle.orb)});
    }
    [prefs setObject:@1 forKey:@"LCFloatingMenu.orbScale"];
    FMManager *proportion=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    Check(@"bead-16-by-72-proportion",fabs(proportion.orb.bounds.size.width-16)<.01 &&
          fabs(proportion.orb.bounds.size.height-72)<.01,NSStringFromCGRect(proportion.orb.bounds));
    Snapshot(proportion,@"collapsed-bead");
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
        Check([NSString stringWithFormat:@"manual-pip-button-removed-%.0f",scale.doubleValue*100],
              Actions(m,@"toggleMultitaskPiP").count==0,nil);
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
    FixturePan *g=[FixturePan new];g.fixturePoint=CGPointMake(150,180);g.fixtureState=UIGestureRecognizerStateBegan;[pan pan:g];
    UIView *orbGlass=[pan.orb viewWithTag:9202];
    CAShapeLayer *neutralMask=(CAShapeLayer *)orbGlass.layer.mask;
    CGPathRef neutralPath=CGPathCreateCopy(neutralMask.path);
    CGFloat orbW=CGRectGetWidth(orbGlass.bounds),orbH=CGRectGetHeight(orbGlass.bounds);
    BOOL roundedTop=CGPathContainsPoint(neutralPath,NULL,CGPointMake(orbW*.5,.10),NO) &&
                    !CGPathContainsPoint(neutralPath,NULL,CGPointMake(orbW*.05,.10),NO);
    BOOL roundedBottom=CGPathContainsPoint(neutralPath,NULL,CGPointMake(orbW*.5,orbH-.10),NO) &&
                       !CGPathContainsPoint(neutralPath,NULL,CGPointMake(orbW*.95,orbH-.10),NO);
    Check(@"drag-capsule-not-trapezoid",roundedTop && roundedBottom,nil);
    g.fixtureState=UIGestureRecognizerStateChanged;g.fixturePoint=CGPointMake(520,180);[pan pan:g];
    Check(@"drag-crosses-screen-without-flip",CGPathEqualToPath(neutralPath,neutralMask.path) &&
          !pan.left,nil);
    CGPathRelease(neutralPath);
    g.fixtureState=UIGestureRecognizerStateCancelled;[pan pan:g];
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
    NSArray *savedApps=FixtureApps;
    NSMutableDictionary *longName=[savedApps[0] mutableCopy];
    longName[@"title"]=@"一个很长很长的应用名称用来检查开关不会覆盖应用文字";
    NSDictionary *builtin=@{@"identity":@"builtin/SideStore",@"path":@"SideStore",@"title":@"SideStore",@"builtin":@YES};
    FixtureApps=@[longName,savedApps[1],builtin];
    FMManager *autoSettings=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    UIStackView *autoStack=[[UIStackView alloc] initWithFrame:CGRectMake(20,20,360,1000)];
    autoStack.axis=UILayoutConstraintAxisVertical;autoStack.spacing=10;
    [autoSettings.overlayView addSubview:autoStack];
    [autoSettings populateSettingsCategory:@"apps" stack:autoStack];
    CGSize settingsSize=[autoStack systemLayoutSizeFittingSize:CGSizeMake(360,UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    autoStack.frame=(CGRect){autoStack.frame.origin,settingsSize};[autoStack layoutIfNeeded];
    NSMutableArray<UISwitch *> *autoControls=[NSMutableArray array];BOOL labelsFit=YES;
    for(UIView *view in Views(autoStack)) if([view isKindOfClass:UISwitch.class] &&
        [[(UISwitch *)view actionsForTarget:autoSettings forControlEvent:UIControlEventValueChanged]
            containsObject:@"automaticPiPChanged:"]) {
        UISwitch *control=(UISwitch *)view;[autoControls addObject:control];
        for(UIView *sibling in control.superview.subviews) if([sibling isKindOfClass:UILabel.class])
            labelsFit &= CGRectGetMaxX(sibling.frame)<=CGRectGetMinX(control.frame)-9.99;
    }
    Check(@"auto-pip-real-apps-only",autoControls.count==2 && labelsFit,
          @{@"switchCount":@(autoControls.count),@"longNameDoesNotOverlap":@(labelsFit)});
    NSUInteger titleCount=0;BOOL unified=autoControls.count==2;
    for(UIView *view in Views(autoStack)) if([view isKindOfClass:UILabel.class] &&
        [((UILabel *)view).text isEqual:longName[@"title"]]) titleCount++;
    for(UISwitch *control in autoControls) {
        NSDictionary *target=objc_getAssociatedObject(control,@selector(automaticPiPChanged:));
        BOOL pinFound=NO,dragFound=objc_getAssociatedObject(control.superview,@selector(sortDrag:))==target;
        for(UIView *sibling in control.superview.subviews) {
            if([sibling isKindOfClass:UIControl.class] &&
               [[(UIControl *)sibling actionsForTarget:autoSettings forControlEvent:UIControlEventTouchUpInside]
                   containsObject:@"pinApp:"])
                pinFound=objc_getAssociatedObject(sibling,@selector(pinApp:))==target;
            if(objc_getAssociatedObject(sibling,@selector(sortDrag:)))
                dragFound=objc_getAssociatedObject(sibling,@selector(sortDrag:))==target;
        }
        unified &= pinFound && dragFound;
    }
    Check(@"app-management-one-record-per-app",titleCount==1,@{@"titleOccurrences":@(titleCount)});
    Check(@"app-management-controls-share-target",unified,nil);
    UIView *firstAppRow=autoControls.firstObject.superview;
    UIView *builtinRow=((UIStackView *)firstAppRow.superview).arrangedSubviews.lastObject;
    BOOL builtinPreserved=builtinRow.bounds.size.height==68;
    for(UIView *view in Views(builtinRow)) builtinPreserved &= ![view isKindOfClass:UISwitch.class];
    Check(@"app-management-builtin-keeps-original-row",builtinPreserved,nil);
    for(NSNumber *width in @[@284,@366,@400]) {
        autoStack.frame=CGRectMake(20,20,width.doubleValue,settingsSize.height);[autoStack layoutIfNeeded];
        BOOL fits=YES;
        for(UISwitch *control in autoControls) {
            CGRect rect=control.frame;
            fits &= CGRectGetMinX(rect)>=0 && CGRectGetMaxX(rect)<=control.superview.bounds.size.width &&
                CGRectGetMinY(rect)>=0 && CGRectGetMaxY(rect)<=control.superview.bounds.size.height;
            for(UIView *sibling in control.superview.subviews) if([sibling isKindOfClass:UILabel.class])
                fits &= sibling.frame.size.width>0 && CGRectGetMaxX(sibling.frame)<=CGRectGetMinX(rect)-9.99;
        }
        Check([NSString stringWithFormat:@"app-management-width-%@",width],fits,nil);
    }
    autoStack.frame=CGRectMake(20,20,360,settingsSize.height);[autoStack layoutIfNeeded];
    UISwitch *autoControl=autoControls.firstObject;
    Check(@"auto-pip-default-off",autoControl && !autoControl.isOn && autoControl.enabled,nil);
    Snapshot(autoSettings,@"settings-auto-pip-apps");
    autoControl.on=YES;[autoSettings automaticPiPChanged:autoControl];
    Check(@"auto-pip-exact-app-action",LastAutoPiPTarget==longName &&
          [AutoPiPStates[longName[@"identity"]] boolValue] && ![AutoPiPStates[savedApps[1][@"identity"]] boolValue],nil);
    RejectAutoPiP=YES;CapturedAlert=nil;autoControl.on=NO;
    [autoSettings automaticPiPChanged:autoControl];
    Check(@"auto-pip-rejected-save-restores-switch",autoControl.isOn && CapturedAlert!=nil,nil);
    RejectAutoPiP=NO;
    // A dragged whole row becomes a floating snapshot. Its original 68pt
    // arranged slot visibly empties and travels to the hovered index.
    id orderBeforeMergeTest=[prefs objectForKey:@"LCFloatingMenu.menuOrder"];
    UIView *dragHandle=firstAppRow;
    UIStackView *manageGroup=(UIStackView *)firstAppRow.superview;
    FixtureLongPress *managementDrag=[FixtureLongPress new];
    [dragHandle addGestureRecognizer:managementDrag];
    managementDrag.fixtureState=UIGestureRecognizerStateBegan;
    managementDrag.fixturePoint=CGPointMake(CGRectGetMidX(firstAppRow.frame),CGRectGetMidY(firstAppRow.frame));
    autoSettings.panel=autoStack;
    [autoSettings sortDrag:managementDrag];
    BOOL vacant=firstAppRow.layer.borderWidth>0 &&
        manageGroup.subviews.count>manageGroup.arrangedSubviews.count;
    for(UIView *child in firstAppRow.subviews) vacant &= child.alpha==0;
    Check(@"app-management-drag-creates-vacant-slot",vacant,nil);
    managementDrag.fixtureState=UIGestureRecognizerStateChanged;
    managementDrag.fixturePoint=CGPointMake(CGRectGetMidX(firstAppRow.frame),
        CGRectGetMaxY(builtinRow.frame)+15);
    [autoSettings sortDrag:managementDrag];
    BOOL shifted=[manageGroup.arrangedSubviews indexOfObjectIdenticalTo:firstAppRow]==2;
    Check(@"app-management-drag-animated-vacancy-moves",shifted,nil);
    managementDrag.fixtureState=UIGestureRecognizerStateEnded;
    [autoSettings sortDrag:managementDrag];
    Check(@"app-management-mixed-height-drag",[[prefs objectForKey:@"LCFloatingMenu.menuOrder"]
        isEqual:@[savedApps[1][@"identity"],builtin[@"identity"],longName[@"identity"]]],nil);
    [prefs setObject:orderBeforeMergeTest forKey:@"LCFloatingMenu.menuOrder"];
    FixtureHost=NO;
    FMManager *guestSettings=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    UIStackView *guestStack=[[UIStackView alloc] initWithFrame:CGRectMake(20,20,360,700)];
    guestStack.axis=UILayoutConstraintAxisVertical;guestStack.spacing=10;
    [guestSettings.overlayView addSubview:guestStack];[guestSettings populateSettingsCategory:@"apps" stack:guestStack];
    [guestStack layoutIfNeeded];BOOL guestHasPiP=NO,guestIndependent=NO;
    for(UIView *view in Views(guestStack)) {
        if([view isKindOfClass:UISwitch.class]) guestHasPiP |= [[(UISwitch *)view actionsForTarget:guestSettings
            forControlEvent:UIControlEventValueChanged] containsObject:@"automaticPiPChanged:"];
        if([view isKindOfClass:UILabel.class]) guestIndependent |= [((UILabel *)view).text isEqual:@"当前 App 独立设置"];
    }
    Check(@"app-management-guest-keeps-independent-settings",!guestHasPiP && guestIndependent,nil);
    FixtureHost=YES;FixtureApps=savedApps;
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
    Results=[NSMutableArray array];Managers=[NSMutableArray array];AutoPiPStates=[NSMutableDictionary dictionary];NSMutableArray *apps=[NSMutableArray array];
    for(NSUInteger i=0;i<8;i++) {NSString *folder=[home stringByAppendingFormat:@"/Documents/Fixture%lu.app",(unsigned long)i];[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];[@{@"CFBundleName":[NSString stringWithFormat:@"App %lu",(unsigned long)i]} writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES];[apps addObject:@{@"folder":folder,@"title":[NSString stringWithFormat:@"App %lu",(unsigned long)i],@"identity":folder,@"path":folder,@"launchable":@YES}];}FixtureApps=apps;
    SwapClass(LCOrbitGuestService.class,@selector(installedApps),@selector(fixtureApps));SwapClass(LCOrbitGuestService.class,@selector(isCurrentGuest:),@selector(fixtureCurrent:));
    SwapClass(LCOrbitMultitask.class,@selector(isCurrentGuest:),@selector(fixtureCurrent:));SwapClass(LCOrbitMultitask.class,@selector(isRunningGuest:),@selector(fixtureRunning:));SwapClass(LCOrbitMultitask.class,@selector(closeGuest:error:),@selector(fixtureClose:error:));SwapClass(LCOrbitMultitask.class,@selector(isEnabled),@selector(fixtureEnabled));SwapClass(LCOrbitHost.class,@selector(isHostUI),@selector(fixtureHost));
    SwapClass(LCOrbitMultitask.class,@selector(automaticPiPEnabledForGuest:),@selector(fixtureAutoPiP:));
    SwapClass(LCOrbitMultitask.class,@selector(setAutomaticPiPEnabled:forGuest:error:),@selector(fixtureSetAutoPiP:forGuest:error:));
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
