#import "LCOrbitTaskSwitcher.h"
#import "LCOrbitMultitask.h"
#import "LCOrbitStorage.h"
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static id TaskObject(id object,SEL selector) {
    return [object respondsToSelector:selector]?((id(*)(id,SEL))objc_msgSend)(object,selector):nil;
}
// 0 means closest to the home-indicator safe area; larger values lift the Dock.
// Read once when the overview opens instead of loading preferences during layout.
static CGFloat TaskDockBottomGap(void) {
    id stored=[[LCOrbitStorage preferences] objectForKey:@"LCFloatingMenu.adaptiveDockBottomGap"];
    CGFloat gap=stored?[stored doubleValue]:4;
    return isfinite(gap)?fmax(0,fmin(80,gap)):4;
}
// The drawer's 弹出动画 setting, read the same way the drawer itself reads it:
// 0 = one after another, 1 = all at once, 2 = no animation at all.
static NSInteger TaskPopMode(void) {
    id stored=[[LCOrbitStorage preferences] objectForKey:@"LCFloatingMenu.popAnimation"];
    CGFloat value=stored?[stored doubleValue]:0;
    if(!isfinite(value))return 0;
    return value<.5?0:(value<1.5?1:2);
}
// One overview element fading in after the others, so the switcher mirrors the
// drawer's staggered pop-in. The model alpha stays at its final value and the
// backwards fill holds the first frame hidden while the delay runs.
static void TaskFadeInLayer(CALayer *layer,CFTimeInterval delay) {
    if(!layer)return;
    CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue=@0;fade.toValue=@1;fade.duration=.28;
    fade.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    fade.beginTime=[layer convertTime:CACurrentMediaTime() fromLayer:nil]+delay;
    fade.fillMode=kCAFillModeBackwards;
    [layer addAnimation:fade forKey:@"task.stagger.in"];
}
static BOOL TaskUsesPiP(UIViewController *window) {
    id scene=TaskObject(window,NSSelectorFromString(@"appSceneVC"));
    SEL ignoreSelector=NSSelectorFromString(@"shouldIgnoreSceneUpdates");
    return [scene respondsToSelector:ignoreSelector] && ((BOOL(*)(id,SEL))objc_msgSend)(scene,ignoreSelector);
}
static UIView *TaskFirstResponder(UIView *view) {
    if(view.isFirstResponder) return view;
    for(UIView *child in view.subviews) { UIView *responder=TaskFirstResponder(child);if(responder)return responder; }
    return nil;
}
static BOOL SameGuest(NSDictionary *app,NSDictionary *task) {
    return [app[@"path"] isEqual:task[@"path"]]&&[app[@"uuid"] isEqual:task[@"uuid"]]&&[app[@"folder"] isEqual:task[@"folder"]];
}

static void SuppressLayerInput(CALayer *layer,NSMapTable<CALayer *,NSNumber *> *saved) {
    SEL get=NSSelectorFromString(@"allowsHitTesting"),set=NSSelectorFromString(@"setAllowsHitTesting:");
    if([layer respondsToSelector:get]&&[layer respondsToSelector:set]) {
        if(![saved objectForKey:layer])
            [saved setObject:@(((BOOL(*)(id,SEL))objc_msgSend)(layer,get)) forKey:layer];
        ((void(*)(id,SEL,BOOL))objc_msgSend)(layer,set,NO);
    }
}

static void SuppressRemoteLayers(CALayer *layer,Class hostClass,NSMapTable<CALayer *,NSNumber *> *saved) {
    if([layer isKindOfClass:hostClass])SuppressLayerInput(layer,saved);
    for(CALayer *child in layer.sublayers)SuppressRemoteLayers(child,hostClass,saved);
}

@interface LCOrbitTaskPlacement : NSObject
@property(nonatomic,strong) UIViewController *controller;
@property(nonatomic,strong) UIView *view;
@property(nonatomic,strong) UIView *parent;
@property(nonatomic,strong) UIView *shadow;
@property(nonatomic,strong) NSArray<NSLayoutConstraint *> *externalConstraints;
@property(nonatomic) CGRect originalFrame;
@property(nonatomic) CGPoint center;
@property(nonatomic) CGAffineTransform transform;
@property(nonatomic) BOOL clipsToBounds;
@property(nonatomic) CGFloat alpha, cornerRadius, depth;
@property(nonatomic) CGFloat shadowRadius;
@property(nonatomic,copy) CALayerCornerCurve cornerCurve;
@property(nonatomic,strong) UIView *firstResponder;
@property(nonatomic,strong) NSMapTable<CALayer *,NSNumber *> *layerInput;
@property(nonatomic) BOOL hidden, interactive, accessibilityHidden;
- (instancetype)initWithController:(UIViewController *)controller;
- (void)restore;
- (void)restoreConstraints;
- (void)suppressLayerInput;
@end
@implementation LCOrbitTaskPlacement
- (instancetype)initWithController:(UIViewController *)controller {
    if((self=[super init])) {
        _controller=controller;_view=controller.view;_parent=_view.superview;
        _hidden=_view.hidden;_interactive=_view.userInteractionEnabled;
        _accessibilityHidden=_view.accessibilityElementsHidden;_firstResponder=TaskFirstResponder(_view);
        _originalFrame=[_view convertRect:_view.bounds toView:_parent];
        _center=_view.center;_transform=_view.transform;_alpha=_view.alpha;_depth=_view.layer.zPosition;
        _clipsToBounds=_view.clipsToBounds;_cornerRadius=_view.layer.cornerRadius;_cornerCurve=_view.layer.cornerCurve;
        NSMutableArray<NSLayoutConstraint *> *external=[NSMutableArray array];
        for(UIView *container=_parent;container;container=container.superview)for(NSLayoutConstraint *constraint in container.constraints)
            if(constraint.firstItem==_view||constraint.secondItem==_view)[external addObject:constraint];
        _externalConstraints=external;
        [NSLayoutConstraint deactivateConstraints:_externalConstraints];
        _layerInput=[NSMapTable weakToStrongObjectsMapTable];
        [self suppressLayerInput];
        _view.hidden=NO;_view.alpha=1;_view.clipsToBounds=YES;
        _view.layer.cornerCurve=kCACornerCurveContinuous;

        _shadow=[UIView new];
        _shadow.userInteractionEnabled=NO;
        _shadow.layer.shadowColor=UIColor.blackColor.CGColor;
        _shadow.layer.shadowOpacity=.30;
        _shadow.layer.shadowRadius=16;
        _shadow.layer.shadowOffset=CGSizeMake(0,8);
        [_parent insertSubview:_shadow belowSubview:_view];
    }
    return self;
}
- (void)suppressLayerInput {
    // A hosted scene can receive touches at its Core Animation context
    // even when the enclosing UIKit view has userInteractionEnabled=NO.
    SuppressLayerInput(self.view.layer,self.layerInput);
    Class hostClass=NSClassFromString(@"CALayerHost");
    if(hostClass)SuppressRemoteLayers(self.view.layer,hostClass,self.layerInput);
}
- (void)restore {
    [self.shadow removeFromSuperview];
    self.view.hidden=self.hidden;self.view.userInteractionEnabled=self.interactive;
    self.view.accessibilityElementsHidden=self.accessibilityHidden;
    self.view.transform=self.transform;self.view.center=self.center;self.view.alpha=self.alpha;self.view.clipsToBounds=self.clipsToBounds;
    self.view.layer.cornerCurve=self.cornerCurve;self.view.layer.cornerRadius=self.cornerRadius;self.view.layer.zPosition=self.depth;
    SEL set=NSSelectorFromString(@"setAllowsHitTesting:");
    for(CALayer *layer in self.layerInput)
        ((void(*)(id,SEL,BOOL))objc_msgSend)(layer,set,[[self.layerInput objectForKey:layer] boolValue]);
}
- (void)restoreConstraints {
    for(NSLayoutConstraint *constraint in self.externalConstraints) {
        id item=constraint.firstItem==self.view?constraint.secondItem:constraint.firstItem;
        UIView *other=[item isKindOfClass:UILayoutGuide.class]?[(UILayoutGuide *)item owningView]:item;
        if([other isKindOfClass:UIView.class]&&self.view.window&&self.view.window==other.window)constraint.active=YES;
    }
}
@end

@interface LCOrbitDockLaunchCover : UIViewController
@property(nonatomic,strong) NSDictionary *app;
@property(nonatomic,strong) NSUUID *token;
@property(nonatomic,strong) UIWindow *launchWindow;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic) CFTimeInterval begunAt, mountedAt;
@property(nonatomic,weak) UIViewController *mountedGuest;
- (void)begin;
- (void)stop;
@end
static LCOrbitDockLaunchCover *ActiveLaunchCover;

@implementation LCOrbitDockLaunchCover
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithWhite:.13 alpha:1];
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(stopForNotification:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(stopForNotification:) name:UISceneWillDeactivateNotification object:self.launchWindow.windowScene];
    [center addObserver:self selector:@selector(stopForNotification:) name:UISceneDidDisconnectNotification object:self.launchWindow.windowScene];
    [center addObserver:self selector:@selector(launchFailed:) name:LCOrbitMultitaskLaunchFailedNotification object:nil];
    [center addObserver:self selector:@selector(configurationChanged:) name:LCOrbitMultitaskConfigurationChangedNotification object:nil];
}
- (void)stopForNotification:(NSNotification *)notification { [self stop]; }
- (void)configurationChanged:(NSNotification *)notification {
    if(![LCOrbitMultitask usesAdaptiveSwitcher]||[LCOrbitMultitask usesNativeTaskWindows]||![LCOrbitMultitask isManagingWindows])[self stop];
}
- (void)launchFailed:(NSNotification *)notification {
    if(self.begunAt)[self stop];
}
- (void)begin {
    if(self.begunAt)return;
    self.begunAt=CACurrentMediaTime();
    self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(checkPresentedGuest:)];
    self.displayLink.preferredFramesPerSecond=20;
    [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)checkPresentedGuest:(CADisplayLink *)link {
    if(link.timestamp-self.begunAt>30) {
        [self stop];
        return;
    }
    UIViewController *guest=[LCOrbitMultitask activeWindow];
    id guestScene=TaskObject(guest,NSSelectorFromString(@"appSceneVC"));
    UIView *content=TaskObject(guestScene,NSSelectorFromString(@"contentView"));
    BOOL ready=content.window.windowScene==self.launchWindow.windowScene
        && !CGRectIsEmpty(content.bounds) && !content.hidden && !guest.view.hidden && guest.view.alpha>.99;
    if(ready && guest!=self.mountedGuest) {
        ready=NO;
        for(NSDictionary *task in [LCOrbitMultitask runningTasksForApps:@[self.app]]) {
            if(task[@"window"]==guest&&SameGuest(self.app,task)){ready=YES;break;}
        }
    }
    if(!ready) {
        self.mountedGuest=nil;
        self.mountedAt=0;
        return;
    }
    if(self.mountedGuest!=guest) {
        self.mountedGuest=guest;
        self.mountedAt=link.timestamp;
        return;
    }
    // Let the mounted remote scene commit across display frames before
    // the cover reveals it. A process ID by itself is not a visual handoff.
    if(link.timestamp-self.mountedAt<.10)return;
    [self.displayLink invalidate];self.displayLink=nil;
    if(UIAccessibilityIsReduceMotionEnabled()) {[self stop];return;}
    [UIView animateWithDuration:.15 animations:^{self.view.alpha=0;} completion:^(BOOL finished){[self stop];}];
}
- (void)stop {
    [self.displayLink invalidate];self.displayLink=nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    UIWindow *window=self.launchWindow;
    self.launchWindow=nil;
    window.hidden=YES;window.rootViewController=nil;
    if(ActiveLaunchCover==self)ActiveLaunchCover=nil;
}
@end

static void KeepDockLaunchCover(UIWindowScene *scene,NSDictionary *app,UIView *surface,UIView *icon) {
    [ActiveLaunchCover stop];
    LCOrbitDockLaunchCover *cover=[LCOrbitDockLaunchCover new];
    cover.app=app;
    cover.token=NSUUID.UUID;
    cover.launchWindow=[[UIWindow alloc] initWithWindowScene:scene];
    cover.launchWindow.accessibilityIdentifier=@"orbit.dock.launch-cover";
    // Keep the existing floating menu's alert presenter above the cover.
    cover.launchWindow.windowLevel=UIWindowLevelNormal+74;
    cover.launchWindow.rootViewController=cover;
    cover.view.frame=cover.launchWindow.bounds;
    [cover.view addSubview:surface];
    surface.frame=cover.view.bounds;
    surface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    surface.layer.cornerRadius=0;
    icon.center=CGPointMake(CGRectGetMidX(surface.bounds),CGRectGetMidY(surface.bounds));
    icon.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|
                          UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
    ActiveLaunchCover=cover;
    cover.launchWindow.hidden=NO;
}

static UIImage *TaskIcon(NSDictionary *task) {
    NSString *folder=task[@"folder"];if(![folder isKindOfClass:NSString.class]||!folder.length)return nil;
    for(NSString *file in @[@"LCAppIconLight.png",@"LCAppIconDark.png"]) { UIImage *icon=[UIImage imageWithContentsOfFile:[folder stringByAppendingPathComponent:file]];if(icon)return icon; }
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:@"Info.plist"]];
    id icons=info[@"CFBundleIcons"]?:info[@"CFBundleIcons~ipad"];id primary=[icons isKindOfClass:NSDictionary.class]?icons[@"CFBundlePrimaryIcon"]:nil;if(![primary isKindOfClass:NSDictionary.class])primary=nil;
    NSMutableArray *names=[NSMutableArray array];
    for(id name in @[primary[@"CFBundleIconName"]?:@"",info[@"CFBundleIconFile"]?:@""])if([name isKindOfClass:NSString.class]&&[name length])[names addObject:name];
    for(id files in @[primary[@"CFBundleIconFiles"]?:@[],info[@"CFBundleIconFiles"]?:@[]])if([files isKindOfClass:NSArray.class])for(id name in [files reverseObjectEnumerator])if([name isKindOfClass:NSString.class])[names addObject:name];
    NSBundle *bundle=[NSBundle bundleWithPath:folder];
    for(NSString *name in names) {
        UIImage *icon=nil;
        @try { if(bundle)icon=[UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil]; } @catch(NSException *exception) {}
        if(icon)return icon;
        NSString *base=name.stringByDeletingPathExtension;
        for(NSString *variant in @[name,[base stringByAppendingString:@"@3x.png"],[base stringByAppendingString:@"@2x.png"],[base stringByAppendingString:@".png"]]) { icon=[UIImage imageWithContentsOfFile:[folder stringByAppendingPathComponent:variant]];if(icon)return icon; }
    }
    return nil;
}
@class LCOrbitTaskOverviewController;
@interface LCOrbitTaskCard : UIView
@property(nonatomic,weak) LCOrbitTaskOverviewController *owner;
@property(nonatomic) NSUInteger index;
@property(nonatomic,strong) UIView *preview;
@property(nonatomic,strong) UIView *touchShield;
@property(nonatomic,strong) UIImageView *icon;
@property(nonatomic,strong) UILabel *name;
@property(nonatomic,strong) LCOrbitTaskPlacement *placement;
@property(nonatomic) CGAffineTransform restingTransform;
@end
@interface LCOrbitTaskOverviewController : UIViewController <UIScrollViewDelegate,UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIWindowScene *hostScene;
@property(nonatomic,strong) NSArray<NSDictionary *> *tasks;
@property(nonatomic,copy) NSArray<NSDictionary *> *apps;
@property(nonatomic,copy) void (^launchHandler)(NSDictionary *app);
@property(nonatomic,copy) LCOrbitTaskDockIconProvider iconProvider;
@property(nonatomic) CGFloat dockIconSize;
@property(nonatomic) CGFloat dockBottomGap;
@property(nonatomic) BOOL gridPresentation;
@property(nonatomic) BOOL initialDockVisible;
@property(nonatomic) NSUInteger cardsPerPage;
@property(nonatomic,strong) UIVisualEffectView *dock;
@property(nonatomic,strong) UIVisualEffectView *backdrop;
@property(nonatomic,strong) UILabel *emptyLabel;
@property(nonatomic,strong) UIScrollView *dockScroll;
@property(nonatomic,strong) NSMutableArray<LCOrbitTaskPlacement *> *placements;
@property(nonatomic,strong) NSMutableArray<LCOrbitTaskCard *> *cards;
@property(nonatomic,strong) UIScrollView *pages;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic,strong) UIViewPropertyAnimator *entranceAnimator, *transitionAnimator, *reboundAnimator;
@property(nonatomic) CGRect sceneBounds;
@property(nonatomic) BOOL restoring, transitioning, scrollingDeck;
@property(nonatomic) CGRect laidOutBounds;
@property(nonatomic) UIEdgeInsets laidOutSafeInsets;
@property(nonatomic) CFTimeInterval lastValidation;
@property(nonatomic) CGFloat stride;
@property(nonatomic) CGFloat dragStartPage;
@property(nonatomic) NSUInteger selectedIndex;
@property(nonatomic,weak) LCOrbitTaskCard *draggingCard, *reboundingCard;
@property(nonatomic) CGFloat dragStartOffset;
@property(nonatomic) BOOL closingTaskInPlace;
@property(nonatomic,copy) NSString *lastDockVisibilityReason;
- (void)stopAndRestore;
- (void)animateDismissWithCompletion:(void(^)(void))completion;
- (void)animateReflowFromFrames:(NSDictionary<NSString *,NSValue *> *)frames;
- (void)finishEntrance;
- (void)stopRebound;
- (void)activateCard:(LCOrbitTaskCard *)card;
- (void)closeCard:(LCOrbitTaskCard *)card;
- (void)restorePlacementsForClose;
- (void)removeClosedTaskWithToken:(NSString *)token;
@end
@interface LCOrbitTaskDockButton : UIButton
@property(nonatomic,strong) UIView *artwork;
@end
@implementation LCOrbitTaskDockButton
- (void)layoutSubviews {
    [super layoutSubviews];
    self.artwork.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
}
@end
@interface LCOrbitTaskSwitcher ()
+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray *)apps dockIconSize:(CGFloat)size
          iconProvider:(LCOrbitTaskDockIconProvider)provider launchHandler:(void (^)(NSDictionary *))handler
           focusToken:(NSString *)focusToken excludedToken:(NSString *)excludedToken
          restoredDock:(BOOL)restoredDock error:(NSError **)error;
@end
static LCOrbitTaskOverviewController *CurrentOverview;
static UIWindow *OverviewWindow;
@implementation LCOrbitTaskCard
- (BOOL)accessibilityActivate { [self.owner activateCard:self];return YES; }
@end

@implementation LCOrbitTaskOverviewController
- (UIView *)dockArtworkForApp:(NSDictionary *)app size:(CGFloat)size current:(BOOL)current {
    UIView *artwork=self.iconProvider?self.iconProvider(app,size,current):nil;
    if(!artwork) {
        UIImageView *image=[[UIImageView alloc] initWithImage:TaskIcon(app)?:[UIImage systemImageNamed:@"app.fill"]];
        image.contentMode=UIViewContentModeScaleAspectFit;
        image.tintColor=UIColor.whiteColor;
        image.layer.cornerRadius=size*.225;
        image.layer.cornerCurve=kCACornerCurveContinuous;
        image.clipsToBounds=YES;
        artwork=image;
    }
    artwork.frame=CGRectMake(0,0,size,size);
    artwork.userInteractionEnabled=NO;
    artwork.accessibilityElementsHidden=YES;
    return artwork;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.clearColor;self.view.accessibilityViewIsModal=YES;
    self.pages=[UIScrollView new];self.pages.accessibilityIdentifier=@"orbit.task.pages";self.pages.delegate=self;self.pages.clipsToBounds=YES;self.pages.showsHorizontalScrollIndicator=NO;self.pages.decelerationRate=UIScrollViewDecelerationRateFast;self.pages.directionalLockEnabled=YES;self.pages.bounces=NO;self.pages.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;self.pages.contentInset=UIEdgeInsetsZero;self.pages.scrollIndicatorInsets=UIEdgeInsetsZero;[self.view addSubview:self.pages];
    if(!self.tasks.count) {
        UILabel *empty=[UILabel new];empty.accessibilityIdentifier=@"orbit.task.empty";empty.text=@"没有正在运行的 App";empty.textAlignment=NSTextAlignmentCenter;empty.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];empty.textColor=[UIColor.whiteColor colorWithAlphaComponent:.82];[self.view addSubview:empty];self.emptyLabel=empty;
    }
    if(self.apps.count) {
        self.dock=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];self.dock.accessibilityIdentifier=@"orbit.dock";self.dock.layer.cornerRadius=19;self.dock.layer.cornerCurve=kCACornerCurveContinuous;self.dock.clipsToBounds=YES;self.dock.layer.borderWidth=.5;self.dock.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:.16].CGColor;[self.view addSubview:self.dock];
        self.dockScroll=[UIScrollView new];self.dockScroll.accessibilityIdentifier=@"orbit.dock.scroll";self.dockScroll.delegate=self;self.dockScroll.showsHorizontalScrollIndicator=NO;self.dockScroll.showsVerticalScrollIndicator=NO;self.dockScroll.alwaysBounceHorizontal=YES;self.dockScroll.directionalLockEnabled=YES;self.dockScroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[self.dock.contentView addSubview:self.dockScroll];
        NSDictionary *active=nil;
        for(NSDictionary *task in self.tasks)if([task[@"active"] boolValue]){active=task;break;}
        for(NSUInteger index=0;index<self.apps.count;index++) {
            NSDictionary *app=self.apps[index];
            LCOrbitTaskDockButton *button=[LCOrbitTaskDockButton buttonWithType:UIButtonTypeCustom];
            button.tag=index;
            button.accessibilityIdentifier=[NSString stringWithFormat:@"orbit.dock.app.%lu",(unsigned long)index];
            button.accessibilityLabel=app[@"title"]?:@"App";
            button.artwork=[self dockArtworkForApp:app size:self.dockIconSize current:SameGuest(app,active)];
            button.accessibilityValue=button.artwork.accessibilityValue;
            [button addSubview:button.artwork];
            [button addTarget:self action:@selector(dockAppTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.dockScroll addSubview:button];
        }
    }
    [self setDockVisible:self.initialDockVisible];
    UITapGestureRecognizer *background=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];background.delegate=self;[self.view addGestureRecognizer:background];
    self.cards=[NSMutableArray array];
    for(NSUInteger index=0;index<self.tasks.count;index++) {
        NSDictionary *task=self.tasks[index];UIViewController *controller=task[@"window"];NSString *token=task[@"token"];
        LCOrbitTaskCard *card=[LCOrbitTaskCard new];card.owner=self;card.index=index;card.accessibilityIdentifier=[@"orbit.task.card." stringByAppendingString:token];card.isAccessibilityElement=YES;card.accessibilityTraits=UIAccessibilityTraitButton;card.accessibilityLabel=task[@"title"]?:@"App";[self.pages addSubview:card];[self.cards addObject:card];
        card.icon=[[UIImageView alloc] initWithImage:TaskIcon(task)?:[UIImage systemImageNamed:@"app.fill"]];card.icon.accessibilityIdentifier=[@"orbit.task.icon." stringByAppendingString:token];card.icon.contentMode=UIViewContentModeScaleAspectFit;card.icon.layer.cornerRadius=6;card.icon.clipsToBounds=YES;card.icon.tintColor=UIColor.whiteColor;[card addSubview:card.icon];
        card.name=[UILabel new];card.name.text=card.accessibilityLabel;card.name.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];card.name.textColor=UIColor.whiteColor;card.name.numberOfLines=1;card.name.lineBreakMode=NSLineBreakByTruncatingTail;card.name.accessibilityIdentifier=[@"orbit.task.name." stringByAppendingString:token];[card addSubview:card.name];
        card.preview=[UIView new];card.preview.accessibilityIdentifier=[@"orbit.task.preview." stringByAppendingString:token];card.preview.backgroundColor=UIColor.clearColor;card.preview.clipsToBounds=YES;card.preview.layer.cornerRadius=28;card.preview.layer.cornerCurve=kCACornerCurveContinuous;
        // Live App previews are already rounded and shadowed; an extra transparent
        // outline can draw across a neighboring card in the stacked switcher.
        [card addSubview:card.preview];
        LCOrbitTaskPlacement *placement=nil;for(LCOrbitTaskPlacement *candidate in self.placements)if(candidate.controller==controller)placement=candidate;
        if(placement) {
            card.placement=placement;
            // The real controller and view stay in the original window; the
            // transparent overview is the sole touch surface for gestures.
            placement.view.userInteractionEnabled=NO;placement.view.accessibilityElementsHidden=YES;
        } else {
            card.preview.backgroundColor=[UIColor colorWithWhite:.18 alpha:1];
            card.preview.layer.borderWidth=.5;
            card.preview.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:.25].CGColor;
            UIImageView *pip=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"pip.fill"]];pip.contentMode=UIViewContentModeScaleAspectFit;pip.tintColor=UIColor.whiteColor;pip.tag=12;pip.accessibilityIdentifier=[@"orbit.task.pip." stringByAppendingString:token];[card.preview addSubview:pip];card.accessibilityHint=@"此 App 的画面保留在画中画中";
        }
        // The entire App-content rectangle belongs to task gestures, including
        // areas that depict buttons, lists, web views or a playing video.
        card.touchShield=[UIView new];card.touchShield.backgroundColor=UIColor.clearColor;card.touchShield.accessibilityIdentifier=[@"orbit.task.shield." stringByAppendingString:token];[card addSubview:card.touchShield];
        SEL opaqueHitTest=NSSelectorFromString(@"setHitTestsAsOpaque:");
        if([card.touchShield.layer respondsToSelector:opaqueHitTest])
            ((void(*)(id,SEL,BOOL))objc_msgSend)(card.touchShield.layer,opaqueHitTest,YES);
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];tap.delegate=self;[card addGestureRecognizer:tap];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(cardPanned:)];pan.delegate=self;[card addGestureRecognizer:pan];[tap requireGestureRecognizerToFail:pan];[self.pages.panGestureRecognizer requireGestureRecognizerToFail:pan];
        __weak LCOrbitTaskCard *weakCard=card;
        card.accessibilityCustomActions=@[[[UIAccessibilityCustomAction alloc] initWithName:@"打开 App" actionHandler:^BOOL(UIAccessibilityCustomAction *action){[weakCard.owner activateCard:weakCard];return YES;}],[[UIAccessibilityCustomAction alloc] initWithName:@"关闭 App" actionHandler:^BOOL(UIAccessibilityCustomAction *action){[weakCard.owner closeCard:weakCard];return YES;}]];
    }
    NSNotificationCenter *notifications=NSNotificationCenter.defaultCenter;
    for(NSString *name in @[UIApplicationWillResignActiveNotification,UIApplicationDidEnterBackgroundNotification,LCOrbitMultitaskConfigurationChangedNotification]) [notifications addObserver:self selector:@selector(applicationChanged:) name:name object:nil];
    for(NSString *name in @[UISceneWillDeactivateNotification,UISceneDidEnterBackgroundNotification,UISceneDidDisconnectNotification]) [notifications addObserver:self selector:@selector(applicationChanged:) name:name object:self.hostScene];
    self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(validateTasks:)];self.displayLink.preferredFramesPerSecond=1;[self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)installBackdrop {
    UIView *host=self.placements.firstObject.parent;
    if(host) {
        for(LCOrbitTaskPlacement *placement in self.placements)
            while(host&&![placement.view isDescendantOfView:host])host=host.superview;
    } else {
        for(UIWindow *window in self.hostScene.windows) {
            if(window.windowLevel==UIWindowLevelNormal&&!window.hidden&&window.rootViewController.view) {
                host=window.rootViewController.view;
                break;
            }
        }
    }
    if(!host)return;
    UIVisualEffectView *backdrop=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    backdrop.accessibilityIdentifier=@"orbit.task.backdrop";
    backdrop.userInteractionEnabled=NO;
    backdrop.frame=host.bounds;
    backdrop.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    // Keep the system material in the host hierarchy below every live surface.
    // A blur in the overlay window would also sample the guest pixels.
    NSMutableSet<UIView *> *taskBranches=[NSMutableSet set];
    for(LCOrbitTaskPlacement *placement in self.placements) {
        UIView *branch=placement.view;
        while(branch&&branch.superview!=host)branch=branch.superview;
        if(branch)[taskBranches addObject:branch];
    }
    UIView *firstTask=nil;
    for(UIView *subview in host.subviews)if([taskBranches containsObject:subview]){firstTask=subview;break;}
    if(firstTask)[host insertSubview:backdrop belowSubview:firstTask];
    else [host addSubview:backdrop];
    self.backdrop=backdrop;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];if(self.restoring||self.transitioning||self.draggingCard||self.scrollingDeck||self.pages.dragging||self.pages.decelerating)return;
    CGRect bounds=self.view.bounds;
    // UIKit can request layout while the scroll view follows a finger. Do not
    // reassign its frame/offset for unchanged geometry.
    UIEdgeInsets safe=self.view.safeAreaInsets;
    if(CGRectEqualToRect(bounds,self.laidOutBounds)&&UIEdgeInsetsEqualToEdgeInsets(safe,self.laidOutSafeInsets))return;self.laidOutBounds=bounds;self.laidOutSafeInsets=safe;
    CGFloat width=bounds.size.width,height=bounds.size.height;
    // Keep an actual 8pt inset around the artwork, even at maximum size.
    // A fixed 56pt cap previously made larger icons hug the glass border.
    CGFloat dockHeight=MAX(54,ceil(self.dockIconSize)+16);
    CGFloat dockTop=MAX(safe.top+12,height-safe.bottom-dockHeight-self.dockBottomGap);
    if(self.dock) {
        CGFloat x=14,buttonWidth=MAX(44,self.dockIconSize);
        for(LCOrbitTaskDockButton *button in self.dockScroll.subviews) {
            if(![button isKindOfClass:LCOrbitTaskDockButton.class])continue;
            button.frame=CGRectMake(x,8,buttonWidth,dockHeight-16);
            x+=buttonWidth+10;
        }
        CGFloat dockContentWidth=x+4;
        CGFloat dockWidth=MIN(width-safe.left-safe.right-28,dockContentWidth);
        // The entrance animation initially translates the Dock by 32pt. Setting
        // frame while transformed bakes that translation into its base position;
        // clearing the transform then lifts the visible Dock above its target.
        // bounds + center describe the untransformed geometry in both states.
        self.dock.bounds=CGRectMake(0,0,dockWidth,dockHeight);
        self.dock.center=CGPointMake(width*.5,dockTop+dockHeight*.5);
        self.dockScroll.frame=self.dock.bounds;
        self.dockScroll.contentSize=CGSizeMake(dockContentWidth,dockHeight);
    }
    // Reserve a visible 28pt gutter above the Dock, even in a dense deck.
    CGFloat cardBottom=self.dock?dockTop-28:height-safe.bottom-16;
    CGFloat availableHeight=MAX(35,cardBottom-safe.top);
    self.emptyLabel.frame=CGRectMake(0,safe.top,width,availableHeight);
    NSUInteger columns=self.gridPresentation?(width>height?3:2):1;
    self.cardsPerPage=self.gridPresentation?columns*2:1;
    CGFloat gridInset=MAX(safe.left,safe.right)+16;
    CGFloat cellWidth=(width-2*gridInset)/columns;
    CGFloat cellHeight=availableHeight/2;
    CGFloat previewHeight=self.gridPresentation?MAX(1,cellHeight-46):MAX(1,MIN(height*.70,availableHeight-60));
    CGFloat maxCardWidth=self.gridPresentation?MAX(1,cellWidth-12):(width>height?previewHeight*.78:width*.72);
    CGFloat deckCenterX=width/2+(self.cards.count>1?maxCardWidth*.125:0);
    NSUInteger selectedIndex=self.selectedIndex;
    NSUInteger lastPage=self.cards.count?(self.cards.count-1)/self.cardsPerPage:0;
    self.pages.frame=bounds;
    self.stride=self.gridPresentation?width:maxCardWidth*.77;
    self.pages.contentSize=CGSizeMake(width+self.stride*lastPage,height);
    for(NSUInteger index=0;index<self.cards.count;index++) {
        LCOrbitTaskCard *card=self.cards[index];
        CGSize source=card.placement.view.bounds.size;
        CGFloat aspect=source.height>0&&source.width>0?source.width/source.height:maxCardWidth/previewHeight;
        CGFloat cardWidth=MIN(maxCardWidth,previewHeight*aspect),cardHeight=MIN(previewHeight,maxCardWidth/aspect);
        NSUInteger slot=index%self.cardsPerPage;
        CGFloat centerX=self.gridPresentation?gridInset+(slot%columns+.5)*cellWidth:deckCenterX;
        CGFloat centerY=safe.top+(self.gridPresentation?(slot/columns+.5)*cellHeight:availableHeight*.52);
        // The preview begins 34pt below the card top, so its bottom is
        // centerY + 17 + cardHeight/2. Account for the deck's 1.018x
        // scale to keep even a non-focused card clear of the Dock.
        CGFloat maxDeckScale=self.gridPresentation?1:1.018;
        centerY=MIN(centerY,cardBottom-maxDeckScale*(17+cardHeight*.5));
        card.transform=CGAffineTransformIdentity;
        card.bounds=CGRectMake(0,0,cardWidth,cardHeight+34);
        card.center=CGPointMake(centerX+(index/self.cardsPerPage)*self.stride,centerY);
        card.preview.frame=CGRectMake(0,34,cardWidth,cardHeight);card.touchShield.frame=card.preview.frame;
        [card.preview viewWithTag:12].frame=CGRectMake((cardWidth-54)/2,(cardHeight-54)/2,54,54);
    }
    self.selectedIndex=selectedIndex;
    self.pages.contentOffset=CGPointMake((selectedIndex/self.cardsPerPage)*self.stride,0);
    [self updateDeck];
    [self updateLiveGeometry];
}
- (void)updateLiveGeometry {
    if(self.restoring)return;
    for(LCOrbitTaskCard *card in self.cards) {
        LCOrbitTaskPlacement *placement=card.placement;
        if(!placement)continue;
        CGRect frame=[card.preview convertRect:card.preview.bounds toView:placement.parent];
        CGSize source=placement.view.bounds.size;
        if(source.width<=0||source.height<=0||CGRectIsEmpty(frame))continue;
        CGFloat sx=frame.size.width/source.width,sy=frame.size.height/source.height;
        placement.view.transform=CGAffineTransformMakeScale(sx,sy);
        placement.view.center=CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
        CGFloat radius=card.preview.layer.cornerRadius/MAX(.01,sx)*fabs(card.transform.a);
        placement.view.layer.cornerRadius=radius;
        CGRect shadowBounds=(CGRect){CGPointZero,source};
        if(!CGRectEqualToRect(placement.shadow.bounds,shadowBounds)||fabs(placement.shadowRadius-radius)>.5) {
            placement.shadow.bounds=shadowBounds;
            placement.shadowRadius=radius;
            placement.shadow.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:shadowBounds cornerRadius:radius].CGPath;
        }
        placement.shadow.transform=placement.view.transform;
        placement.shadow.center=placement.view.center;
        placement.shadow.layer.zPosition=placement.view.layer.zPosition-.01;
        placement.shadow.alpha=placement.view.alpha;
    }
}
- (void)updateDeck {
    if(self.restoring||self.transitioning||!self.stride||!self.cards.count)return;
    CGFloat pagePosition=self.pages.contentOffset.x/self.stride;
    for(LCOrbitTaskCard *card in self.cards) {
        card.restingTransform=CGAffineTransformIdentity;
        if(!self.gridPresentation) {
            CGFloat distance=(CGFloat)card.index-pagePosition;
            CGFloat pageX=distance*self.stride;
            // Earlier cards compress behind the focal card, with matching scroll speed at the focal point.
            CGFloat deckX=distance<0?pageX/(1-2.25*distance):pageX;
            CGFloat scale=1+.018*MAX(-3,MIN(1,distance));
            card.restingTransform=CGAffineTransformMake(scale,0,0,scale,deckX-pageX,0);
        }
        if(card!=self.draggingCard&&card!=self.reboundingCard)card.transform=card.restingTransform;
        card.placement.view.layer.zPosition=2+card.index;
        card.alpha=1;
    }
    CGFloat leftEdge=self.pages.contentOffset.x,rightEdge=leftEdge+self.pages.bounds.size.width;
    for(LCOrbitTaskCard *card in self.cards) {
        CGRect cardFrame=card.frame;
        CGFloat left=MAX(leftEdge+12,CGRectGetMinX(cardFrame));
        CGFloat right=MIN(rightEdge-12,CGRectGetMaxX(cardFrame));
        if(!self.gridPresentation&&card.index+1<self.cards.count)
            right=MIN(right,CGRectGetMinX(self.cards[card.index+1].frame)-5);
        CGFloat iconX=[card convertPoint:CGPointMake(left,0) fromView:self.pages].x;
        card.icon.alpha=MAX(0,MIN(1,(right-left-16)/9));
        card.icon.frame=CGRectMake(iconX,0,25,25);
        CGFloat titleWidth=MAX(0,(right-left)/card.transform.a-33);
        card.name.frame=CGRectMake(iconX+33,1,titleWidth,24);
        CGFloat titleVisibility=self.gridPresentation?(titleWidth>=26):MAX(0,MIN(1,(titleWidth-48)/20));
        card.name.alpha=titleVisibility*card.icon.alpha;
    }
}
- (void)selectPage:(NSUInteger)page {
    if(self.selectedIndex/self.cardsPerPage!=page)
        self.selectedIndex=MIN(self.cards.count-1,page*self.cardsPerPage);
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if(scrollView!=self.pages)return;
    if(self.stride>0&&self.cards.count) {
        NSUInteger lastPage=(self.cards.count-1)/self.cardsPerPage;
        [self selectPage:MIN(lastPage,(NSUInteger)MAX(0,llround(scrollView.contentOffset.x/self.stride)))];
    }
    [self updateDeck];
    [self updateLiveGeometry];
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if(scrollView!=self.pages)return;
    [self finishEntrance];
    self.dragStartPage=round(scrollView.contentOffset.x/MAX(1,self.stride));
    self.scrollingDeck=YES;
}
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)offset {
    if(scrollView!=self.pages||!self.stride||!self.cards.count)return;
    CGFloat current=scrollView.contentOffset.x/self.stride;
    CGFloat page=round(current);
    if(fabs(velocity.x)>.25) {
        // The finger can cross multiple cards. Release momentum can only
        // advance within one page of the drag start or settle the page reached.
        CGFloat start=self.scrollingDeck?self.dragStartPage:page;
        CGFloat directional=velocity.x>0?floor(current+.05)+1:ceil(current-.05)-1;
        page=MIN(MAX(directional,MIN(page,start-1)),MAX(page,start+1));
    }
    page=MIN(MAX(0,page),(self.cards.count-1)/self.cardsPerPage);
    offset->x=page*self.stride;offset->y=0;
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if(scrollView!=self.pages||decelerate)return;
    if(self.stride&&self.cards.count) {
        CGFloat target=(self.selectedIndex/self.cardsPerPage)*self.stride;
        if(fabs(scrollView.contentOffset.x-target)>=.5) {
            BOOL animated=!UIAccessibilityIsReduceMotionEnabled();
            [scrollView setContentOffset:CGPointMake(target,0) animated:animated];
            if(animated)return;
        }
    }
    self.scrollingDeck=NO;
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView { if(scrollView==self.pages)self.scrollingDeck=NO; }
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView { if(scrollView==self.pages)self.scrollingDeck=NO; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if(self.restoring||self.transitioning)return NO;
    if([gesture isKindOfClass:UIPanGestureRecognizer.class]) { CGPoint velocity=[(UIPanGestureRecognizer *)gesture velocityInView:self.view];return fabs(velocity.y)>fabs(velocity.x)*1.2; }
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if(gesture.view==self.view) { if([touch.view isDescendantOfView:self.dock])return NO;for(LCOrbitTaskCard *card in self.cards)if([touch.view isDescendantOfView:card])return NO; }
    return YES;
}
- (void)cardTapped:(UITapGestureRecognizer *)tap { if(tap.state==UIGestureRecognizerStateEnded)[self activateCard:(id)tap.view]; }
- (void)backgroundTapped:(UITapGestureRecognizer *)tap { if(tap.state==UIGestureRecognizerStateEnded)[LCOrbitTaskSwitcher dismissAnimatedWithHome]; }
- (void)setDockVisible:(BOOL)visible {
    self.lastDockVisibilityReason=visible?@"visible":@"hidden";
    self.dock.transform=visible?CGAffineTransformIdentity:CGAffineTransformMakeTranslation(0,32);
    self.dock.effect=visible?[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]:nil;
    self.dockScroll.alpha=visible?1:0;
    self.emptyLabel.alpha=visible?1:0;
}
- (void)alignPreviewOfCard:(LCOrbitTaskCard *)card toFrame:(CGRect)frame {
    if(CGRectIsEmpty(frame)||CGRectIsEmpty(card.preview.bounds))return;
    CGRect target=[self.pages convertRect:frame fromView:self.view];
    CGFloat sx=target.size.width/card.preview.bounds.size.width;
    CGFloat sy=target.size.height/card.preview.bounds.size.height;
    CGFloat x=CGRectGetMidX(target)-card.center.x;
    CGFloat y=CGRectGetMidY(target)-card.center.y-sy*(CGRectGetMidY(card.preview.frame)-CGRectGetMidY(card.bounds));
    card.transform=CGAffineTransformMake(sx,0,0,sy,x,y);
}
- (CGRect)expandedFrameForCard:(LCOrbitTaskCard *)card {
    LCOrbitTaskPlacement *placement=card.placement;
    return placement?[self.view convertRect:placement.originalFrame fromView:placement.parent]:self.view.bounds;
}
- (void)runTransitionWithDuration:(NSTimeInterval)duration damping:(CGFloat)damping velocity:(CGFloat)velocity
                      animations:(void (^)(void))animations completion:(void (^)(void))completion {
    self.transitioning=YES;
    self.pages.scrollEnabled=NO;
    if(UIAccessibilityIsReduceMotionEnabled()){completion();return;}
    UISpringTimingParameters *timing=[[UISpringTimingParameters alloc] initWithDampingRatio:damping
                                                                         initialVelocity:CGVectorMake(0,velocity)];
    self.transitionAnimator=[[UIViewPropertyAnimator alloc] initWithDuration:duration timingParameters:timing];
    [self.transitionAnimator addAnimations:animations];
    __weak typeof(self) weakSelf=self;
    [self.transitionAnimator addCompletion:^(UIViewAnimatingPosition position){
        LCOrbitTaskOverviewController *owner=weakSelf;
        if(!owner||CurrentOverview!=owner||owner.restoring)return;
        owner.transitionAnimator=nil;
        if(position==UIViewAnimatingPositionEnd)completion();
    }];
    [self.transitionAnimator startAnimation];
}
- (void)closeCard:(LCOrbitTaskCard *)card velocity:(CGFloat)velocity closeInPlace:(BOOL)closeInPlace {
    if(!card||self.restoring||self.transitioning||card.index>=self.tasks.count)return;
    [self finishEntrance];
    [self stopRebound];
    NSUInteger index=card.index;
    CGRect frame=[card.preview convertRect:card.preview.bounds toView:self.view];
    CGFloat travel=MAX(30,CGRectGetMaxY(frame)+60);
    CGFloat speed=MAX(0,MIN(5,-velocity/travel));
    __weak typeof(self) weakSelf=self;
    [self runTransitionWithDuration:.30 damping:1 velocity:speed animations:^{
        card.transform=CGAffineTransformConcat(card.transform,CGAffineTransformMakeTranslation(0,-travel));
        card.alpha=0;
        card.placement.view.alpha=0;
        [weakSelf updateLiveGeometry];
    } completion:^{[weakSelf performTaskAtIndex:index close:YES];}];
}
- (void)expandCard:(LCOrbitTaskCard *)card completion:(void (^)(void))completion {
    [self finishEntrance];
    [self stopRebound];
    [self runTransitionWithDuration:.34 damping:.92 velocity:0 animations:^{
        self.backdrop.effect=nil;
        [self setDockVisible:NO];
        for(LCOrbitTaskCard *other in self.cards) {
            other.icon.alpha=0;
            other.name.alpha=0;
            if(other==card)continue;
            other.alpha=0;
            other.placement.view.alpha=0;
        }
        card.alpha=1;
        card.preview.alpha=card.placement?0:1;
        [self alignPreviewOfCard:card toFrame:[self expandedFrameForCard:card]];
        [self updateLiveGeometry];
        card.placement.view.layer.cornerRadius=card.placement.cornerRadius;
    } completion:completion];
}
- (void)dockAppTapped:(LCOrbitTaskDockButton *)button {
    if(self.restoring||self.transitioning||button.tag<0||(NSUInteger)button.tag>=self.apps.count)return;
    NSDictionary *app=self.apps[button.tag];
    void(^handler)(NSDictionary *)=self.launchHandler;
    void (^complete)(void)=^{
        [LCOrbitTaskSwitcher dismiss];
        if(handler)handler(app);
    };
    [self finishEntrance];
    [self stopRebound];
    [button layoutIfNeeded];
    CGRect sourceFrame=[button.artwork convertRect:button.artwork.bounds toView:self.view];
    for(LCOrbitTaskCard *card in self.cards) {
        NSDictionary *task=self.tasks[card.index];
        if(SameGuest(app,task)) {
            CGRect preview=[card.preview convertRect:card.preview.bounds toView:self.view];
            if(!CGRectIntersectsRect(preview,self.view.bounds)){
                [self alignPreviewOfCard:card toFrame:sourceFrame];
                [self updateLiveGeometry];
            }
            [self expandCard:card completion:complete];
            return;
        }
    }
    BOOL needsCover=handler&&[app[@"launchable"] boolValue]&&![app[@"builtin"] boolValue]&&![app[@"classicOnly"] boolValue];
    if(UIAccessibilityIsReduceMotionEnabled()&&!needsCover){complete();return;}
    UIView *surface=[[UIView alloc] initWithFrame:sourceFrame];
    surface.accessibilityIdentifier=@"orbit.dock.launch";
    surface.userInteractionEnabled=NO;
    surface.backgroundColor=[UIColor colorWithWhite:.13 alpha:1];
    surface.layer.cornerCurve=kCACornerCurveContinuous;
    surface.layer.cornerRadius=self.dockIconSize*.225;
    surface.clipsToBounds=YES;
    UIView *icon=[self dockArtworkForApp:app size:self.dockIconSize current:NO];
    [surface addSubview:icon];
    [self.view addSubview:surface];
    [self runTransitionWithDuration:.32 damping:.93 velocity:0 animations:^{
        self.pages.alpha=0;
        for(LCOrbitTaskPlacement *placement in self.placements) {
            placement.view.alpha=0;
            placement.shadow.alpha=0;
        }
        [self setDockVisible:NO];
        surface.frame=self.view.bounds;
        surface.layer.cornerRadius=0;
        icon.center=CGPointMake(CGRectGetMidX(surface.bounds),CGRectGetMidY(surface.bounds));
        icon.transform=CGAffineTransformMakeScale(1.3,1.3);
    } completion:^{
        if(needsCover)KeepDockLaunchCover(self.hostScene,app,surface,icon);
        complete();
    }];
}
- (BOOL)accessibilityPerformEscape { [LCOrbitTaskSwitcher dismiss];return YES; }
- (void)stopRebound {
    if(!self.reboundAnimator)return;
    [self.reboundAnimator stopAnimation:YES];
    self.reboundAnimator=nil;
    LCOrbitTaskCard *card=self.reboundingCard;
    self.reboundingCard=nil;
    card.transform=card.restingTransform;
    [self updateLiveGeometry];
}
- (void)cardPanned:(UIPanGestureRecognizer *)pan {
    LCOrbitTaskCard *card=(id)pan.view;
    if(![card isKindOfClass:LCOrbitTaskCard.class]||self.restoring||self.transitioning)return;
    CGPoint translation=[pan translationInView:self.view],velocity=[pan velocityInView:self.view];
    if(pan.state==UIGestureRecognizerStateBegan) {
        if(fabs(velocity.y)<=fabs(velocity.x)*1.2)return;
        [self finishEntrance];
        CALayer *visible=self.reboundingCard==card?card.layer.presentationLayer:nil;
        CGFloat offset=visible?visible.affineTransform.ty-card.restingTransform.ty:0;
        [self stopRebound];
        self.draggingCard=card;
        self.dragStartOffset=offset;
        [self updateDeck];
    }
    if(self.draggingCard!=card)return;
    if(pan.state==UIGestureRecognizerStateBegan||pan.state==UIGestureRecognizerStateChanged||pan.state==UIGestureRecognizerStateEnded) {
        CGFloat y=translation.y+self.dragStartOffset;
        if(y>0)y=.25*y/(1+y/MAX(1,card.preview.bounds.size.height));
        card.transform=CGAffineTransformConcat(card.restingTransform,CGAffineTransformMakeTranslation(0,y));
        [self updateLiveGeometry];
    }
    if(pan.state!=UIGestureRecognizerStateEnded&&pan.state!=UIGestureRecognizerStateCancelled&&pan.state!=UIGestureRecognizerStateFailed)return;
    self.draggingCard=nil;
    CGFloat projected=translation.y+self.dragStartOffset+.12*MAX(-2200,MIN(1400,velocity.y));
    BOOL upward=translation.y< -8&&fabs(translation.y)>fabs(translation.x)*1.12;
    if(pan.state==UIGestureRecognizerStateEnded&&upward&&projected< -card.preview.bounds.size.height*.23) {
        [self closeCard:card velocity:velocity.y];
        return;
    }

    CGFloat offset=card.transform.ty-card.restingTransform.ty;
    if(UIAccessibilityIsReduceMotionEnabled()||fabs(offset)<.5) {
        card.transform=card.restingTransform;
        [self updateDeck];[self updateLiveGeometry];
        return;
    }
    CGFloat springVelocity=pan.state==UIGestureRecognizerStateEnded?MAX(-4,MIN(4,velocity.y/-offset)):0;
    UISpringTimingParameters *timing=[[UISpringTimingParameters alloc] initWithDampingRatio:.84
                                                                         initialVelocity:CGVectorMake(0,springVelocity)];
    self.reboundingCard=card;
    self.reboundAnimator=[[UIViewPropertyAnimator alloc] initWithDuration:.32 timingParameters:timing];
    __weak typeof(self) weakSelf=self;
    [self.reboundAnimator addAnimations:^{ card.transform=card.restingTransform;[weakSelf updateLiveGeometry]; }];
    [self.reboundAnimator addCompletion:^(UIViewAnimatingPosition position){
        LCOrbitTaskOverviewController *owner=weakSelf;
        owner.reboundAnimator=nil;owner.reboundingCard=nil;
        [owner updateDeck];[owner updateLiveGeometry];
    }];
    [self.reboundAnimator startAnimation];
}
- (void)activateCard:(LCOrbitTaskCard *)card {
    if(!card||self.restoring||self.transitioning||card.index>=self.tasks.count)return;
    NSUInteger index=card.index;
    __weak typeof(self) weakSelf=self;
    [self expandCard:card completion:^{[weakSelf performTaskAtIndex:index close:NO];}];
}
- (void)closeCard:(LCOrbitTaskCard *)card { [self closeCard:card velocity:0]; }
- (void)closeCard:(LCOrbitTaskCard *)card velocity:(CGFloat)velocity {
    [self closeCard:card velocity:velocity closeInPlace:YES];
}
- (void)performTaskAtIndex:(NSUInteger)index close:(BOOL)close {
    NSDictionary *task=self.tasks[index];
    UIWindowScene *scene=self.hostScene;
    NSError *error=nil;
    if(close) {
        LCOrbitTaskCard *card=self.cards[index];
        LCOrbitTaskPlacement *placement=card.placement;
        NSMutableDictionary *frames=[NSMutableDictionary dictionary];
        for(LCOrbitTaskCard *other in self.cards) if(other!=card)
            frames[self.tasks[other.index][@"token"]]=[NSValue valueWithCGRect:
                [other.preview convertRect:other.preview.bounds toView:self.view]];

        // Exit callbacks can run synchronously. Release only this preview
        // before closing so a callback cannot dismiss the surviving deck.
        if(placement) [self.placements removeObjectIdenticalTo:placement];
        BOOL success=[LCOrbitMultitask closeTaskFromOverview:task error:&error];
        self.transitioning=NO;
        self.pages.scrollEnabled=YES;
        if(success) {
            if(placement) {
                placement.hidden=YES;
                [placement restore];
                [placement restoreConstraints];
            }
            [self removeClosedTaskWithToken:task[@"token"]];
            if(!self.cards.count && !self.apps.count) {
                [LCOrbitTaskSwitcher dismissAnimatedWithHome];
                return;
            }
            if(!UIAccessibilityIsReduceMotionEnabled()) [self animateReflowFromFrames:frames];
            return;
        }
        if(placement) [self.placements addObject:placement];
        card.alpha=1;
        placement.view.alpha=1;
        [self updateDeck];
        [self updateLiveGeometry];
        NSString *message=error.localizedDescription?:@"此任务已结束或发生变化。";
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,message);
        UIViewController *presenter=CurrentOverview?:scene.keyWindow.rootViewController;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"无法操作此 App" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:NO completion:nil];
        return;
    } else {
        BOOL success=[LCOrbitMultitask activateTask:task error:&error];
        if(success)return;
        [LCOrbitTaskSwitcher dismiss];
        NSString *message=error.localizedDescription?:@"此任务已结束或发生变化。";
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,message);
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"无法操作此 App" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    }
    NSString *message=error.localizedDescription?:@"此任务已结束或发生变化。";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,message);
    UIViewController *presenter=CurrentOverview?:scene.keyWindow.rootViewController;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"无法操作此 App" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:NO completion:nil];
}

- (void)restorePlacementsForClose {
    NSArray *ordered=[self.placements copy];
    for(LCOrbitTaskPlacement *placement in ordered) [placement restore];
    for(LCOrbitTaskPlacement *placement in ordered) [placement restoreConstraints];
}

- (void)removeClosedTaskWithToken:(NSString *)token {
    NSUInteger index=NSNotFound;
    for(NSUInteger candidate=0;candidate<self.tasks.count;candidate++)
        if([self.tasks[candidate][@"token"] isEqual:token]){index=candidate;break;}
    if(index==NSNotFound)return;

    UIViewController *retiring=self.tasks[index][@"window"];
    if(!retiring.view.hidden)retiring.view.hidden=YES;
    for(LCOrbitTaskCard *card in self.cards)if(card.placement.controller==retiring)card.placement.view.alpha=0;

    NSMutableArray *tasks=[self.tasks mutableCopy];
    [tasks removeObjectAtIndex:index];
    NSMutableArray *cards=[self.cards mutableCopy];
    LCOrbitTaskCard *closed=cards[index];
    [cards removeObjectAtIndex:index];
    [closed removeFromSuperview];

    self.tasks=tasks;
    self.cards=cards;
    for(NSUInteger cardIndex=0;cardIndex<cards.count;cardIndex++)((LCOrbitTaskCard *)cards[cardIndex]).index=cardIndex;
    if(index<self.selectedIndex) self.selectedIndex--;
    if(self.selectedIndex>=cards.count)self.selectedIndex=cards.count?cards.count-1:0;

    if(!cards.count) {
        if(!self.emptyLabel) {
            UILabel *empty=[UILabel new];empty.accessibilityIdentifier=@"orbit.task.empty";empty.text=@"没有正在运行的 App";empty.textAlignment=NSTextAlignmentCenter;empty.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];empty.textColor=[UIColor.whiteColor colorWithAlphaComponent:.82];[self.view addSubview:empty];self.emptyLabel=empty;
        }
        self.laidOutBounds=CGRectNull;
        self.pages.alpha=0;
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        return;
    }

    self.laidOutBounds=CGRectNull;
    self.selectedIndex=MIN(self.selectedIndex,cards.count-1);
    self.pages.alpha=1;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self updateDeck];
    [self updateLiveGeometry];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator { [LCOrbitTaskSwitcher dismiss];[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator]; }
- (void)applicationChanged:(NSNotification *)notification {
    UIViewController *exitedWindow=notification.userInfo[@"exitedWindow"];
    if(exitedWindow&&![LCOrbitTaskSwitcher isPresentingWindow:exitedWindow])return;
    [LCOrbitTaskSwitcher dismiss];
}
- (void)animateEntrance {
    if(UIAccessibilityIsReduceMotionEnabled())return;
    NSInteger popMode=TaskPopMode();
    BOOL staged=popMode==0;
    LCOrbitTaskCard *card=self.cards.count?self.cards[self.selectedIndex]:nil;
    BOOL fromApp=card.placement&&!card.placement.hidden&&[self.tasks[self.selectedIndex][@"active"] boolValue];
    self.backdrop.effect=nil;
    [self setDockVisible:NO];
    for(LCOrbitTaskCard *other in self.cards) {
        other.alpha=0;
        other.placement.view.alpha=other==card&&fromApp?1:0;
    }
    if(fromApp) {
        [self alignPreviewOfCard:card toFrame:[self expandedFrameForCard:card]];
    } else {
        for(LCOrbitTaskCard *other in self.cards)
            other.transform=CGAffineTransformConcat(CGAffineTransformScale(other.restingTransform,.91,.91),CGAffineTransformMakeTranslation(0,32));
    }
    [self updateLiveGeometry];
    if(fromApp)card.placement.view.layer.cornerRadius=card.placement.cornerRadius;
    __weak typeof(self) weakSelf=self;
    UISpringTimingParameters *timing=[[UISpringTimingParameters alloc] initWithDampingRatio:.91];
    // The "off" setting still has to put the switcher on screen, it just does it
    // without a visible transition.
    self.entranceAnimator=[[UIViewPropertyAnimator alloc] initWithDuration:popMode==2?.01:.38 timingParameters:timing];
    [self.entranceAnimator addAnimations:^{
        LCOrbitTaskOverviewController *owner=weakSelf;
        owner.backdrop.effect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
        [owner setDockVisible:YES];
        [owner updateDeck];
        for(LCOrbitTaskPlacement *placement in owner.placements)placement.view.alpha=1;
        [owner updateLiveGeometry];
        if(staged) {
            NSUInteger step=0;
            for(LCOrbitTaskCard *other in owner.cards) {
                TaskFadeInLayer(other.layer,.05*step);
                TaskFadeInLayer(other.placement.view.layer,.05*step);
                TaskFadeInLayer(other.placement.shadow.layer,.05*step);
                step++;
            }
            NSUInteger buttonStep=0;
            for(UIView *button in owner.dockScroll.subviews)TaskFadeInLayer(button.layer,.04*buttonStep++);
        }
    }];
    [self.entranceAnimator addCompletion:^(UIViewAnimatingPosition position){weakSelf.entranceAnimator=nil;}];
    [self.entranceAnimator startAnimation];
}
- (void)animateReflowFromFrames:(NSDictionary<NSString *,NSValue *> *)frames {
    if(!frames.count||!self.cards.count)return;
    BOOL moved=NO;
    for(LCOrbitTaskCard *card in self.cards) {
        NSValue *previous=frames[self.tasks[card.index][@"token"]];
        if(!previous)continue;
        CGRect current=[card.preview convertRect:card.preview.bounds toView:self.view];
        if(CGRectEqualToRect(current,previous.CGRectValue))continue;
        [self alignPreviewOfCard:card toFrame:previous.CGRectValue];
        moved=YES;
    }
    if(!moved)return;
    [self updateLiveGeometry];
    UISpringTimingParameters *timing=[[UISpringTimingParameters alloc] initWithDampingRatio:.88];
    self.entranceAnimator=[[UIViewPropertyAnimator alloc] initWithDuration:.28 timingParameters:timing];
    __weak typeof(self) weakSelf=self;
    [self.entranceAnimator addAnimations:^{[weakSelf updateDeck];[weakSelf updateLiveGeometry];}];
    [self.entranceAnimator addCompletion:^(UIViewAnimatingPosition position){weakSelf.entranceAnimator=nil;}];
    [self.entranceAnimator startAnimation];
}
- (void)finishEntrance {
    UIViewPropertyAnimator *animator=self.entranceAnimator;
    if(animator.state==UIViewAnimatingStateActive) {
        [animator stopAnimation:NO];
        [animator finishAnimationAtPosition:UIViewAnimatingPositionEnd];
    }
}
- (void)animateDismissWithCompletion:(void (^)(void))completion {
    if(self.restoring||self.transitioning)return;
    [self finishEntrance];
    [self stopRebound];
    [self runTransitionWithDuration:.28 damping:1 velocity:0 animations:^{
        self.backdrop.effect=nil;
        [self setDockVisible:NO];
        self.pages.alpha=0;
        for(LCOrbitTaskCard *card in self.cards) {
            [card.layer removeAnimationForKey:@"task.stagger.in"];
            card.transform=CGAffineTransformConcat(CGAffineTransformScale(card.restingTransform,.86,.86),CGAffineTransformMakeTranslation(0,46));
            card.placement.view.alpha=0;
        }
        [self updateLiveGeometry];
    } completion:completion];
}
- (void)validateTasks:(CADisplayLink *)link {
    if(self.restoring||link.timestamp-self.lastValidation<.8)return;self.lastValidation=link.timestamp;
    if(![LCOrbitMultitask usesAdaptiveSwitcher]||[LCOrbitMultitask usesNativeTaskWindows]||![LCOrbitMultitask isManagingWindows]||!CGRectEqualToRect(self.hostScene.coordinateSpace.bounds,self.sceneBounds)){[LCOrbitTaskSwitcher dismiss];return;}
    NSArray *running=self.apps?[LCOrbitMultitask runningTasksForApps:self.apps]:[LCOrbitMultitask runningTasks];
    for(NSDictionary *task in self.tasks) { BOOL exists=NO;for(NSDictionary *current in running)if([current[@"token"] isEqual:task[@"token"]]&&current[@"window"]==task[@"window"])exists=YES;if(!exists){[LCOrbitTaskSwitcher dismiss];return;} }
    for(LCOrbitTaskPlacement *placement in self.placements) {
        if(TaskUsesPiP(placement.controller)||placement.view.superview!=placement.parent){[LCOrbitTaskSwitcher dismiss];return;}
        [placement suppressLayerInput];
    }
}
- (void)stopAndRestore {
    if(self.restoring)return;self.restoring=YES;[self.displayLink invalidate];self.displayLink=nil;[NSNotificationCenter.defaultCenter removeObserver:self];
    [self.entranceAnimator stopAnimation:YES];self.entranceAnimator=nil;
    [self.transitionAnimator stopAnimation:YES];self.transitionAnimator=nil;
    [self.reboundAnimator stopAnimation:YES];self.reboundAnimator=nil;
    [self.backdrop removeFromSuperview];self.backdrop=nil;
    NSArray *ordered=[self.placements copy];
    for(LCOrbitTaskPlacement *placement in ordered) [placement restore];
    for(LCOrbitTaskPlacement *placement in ordered) [placement restoreConstraints];
    for(LCOrbitTaskPlacement *placement in ordered)if(placement.firstResponder && !placement.hidden) [placement.firstResponder becomeFirstResponder];
    // Keep every task guarded until visibility and input have been restored.
    [self.placements removeAllObjects];
}
- (void)dealloc { [self.displayLink invalidate];[NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

@implementation LCOrbitTaskSwitcher
+ (BOOL)presentInScene:(UIWindowScene *)scene error:(NSError **)error {
    return [self presentInScene:scene apps:nil launchHandler:nil error:error];
}
+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray<NSDictionary *> * _Nullable)apps launchHandler:(void (^ _Nullable)(NSDictionary *))handler error:(NSError **)error {
    return [self presentInScene:scene apps:apps dockIconSize:48 iconProvider:nil launchHandler:handler error:error];
}
+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray<NSDictionary *> *)apps dockIconSize:(CGFloat)size
          iconProvider:(LCOrbitTaskDockIconProvider)provider launchHandler:(void (^)(NSDictionary *))handler error:(NSError **)error {
    return [self presentInScene:scene apps:apps dockIconSize:size iconProvider:provider launchHandler:handler
                     focusToken:nil excludedToken:nil restoredDock:NO error:error];
}
+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray *)apps dockIconSize:(CGFloat)size
          iconProvider:(LCOrbitTaskDockIconProvider)provider launchHandler:(void (^)(NSDictionary *))handler
           focusToken:(NSString *)focusToken excludedToken:(NSString *)excludedToken
          restoredDock:(BOOL)restoredDock error:(NSError **)error {
    if(!NSThread.isMainThread||!scene||scene.activationState!=UISceneActivationStateForegroundActive||![LCOrbitMultitask usesAdaptiveSwitcher]||[LCOrbitMultitask usesNativeTaskWindows]||![LCOrbitMultitask isManagingWindows]) {
        if(error)*error=[NSError errorWithDomain:@"LCOrbitTaskSwitcher" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请在当前 LC 窗口启用原生自适应多任务后打开任务切换。"}];return NO;
    }
    if(ActiveLaunchCover.launchWindow.windowScene==scene)return YES;
    [self dismiss];NSMutableArray *tasks=[NSMutableArray array];
    for(NSDictionary *task in (apps?[LCOrbitMultitask runningTasksForApps:apps]:[LCOrbitMultitask runningTasks])) {
        UIViewController *controller=task[@"window"];
        if([task[@"native"] boolValue]||![controller isKindOfClass:UIViewController.class]||![task[@"token"] isKindOfClass:NSString.class])continue;
        if([task[@"token"] isEqual:excludedToken])continue;
        if(controller.isViewLoaded&&controller.view.superview&&controller.view.window.windowScene==scene)[tasks addObject:task];
    }
    if(!tasks.count&&!apps.count){[LCOrbitMultitask showHome];return YES;}
    NSMutableArray *placements=[NSMutableArray array];
    for(NSDictionary *task in tasks)if(!TaskUsesPiP(task[@"window"])) {
        LCOrbitTaskPlacement *placement=[[LCOrbitTaskPlacement alloc] initWithController:task[@"window"]];
        [placements addObject:placement];
    }
    LCOrbitTaskOverviewController *controller=[LCOrbitTaskOverviewController new];controller.hostScene=scene;controller.tasks=tasks;controller.apps=[apps copy];controller.launchHandler=handler;controller.placements=placements;controller.sceneBounds=scene.coordinateSpace.bounds;
    controller.gridPresentation=[LCOrbitMultitask taskSwitcherPresentation]==1;
    controller.initialDockVisible=restoredDock;
    controller.dockIconSize=MIN(50,MAX(24,size));
    controller.dockBottomGap=TaskDockBottomGap();
    controller.iconProvider=provider;
    for(NSUInteger index=0;index<tasks.count;index++)if([tasks[index][@"active"] boolValue]){controller.selectedIndex=index;break;}
    if(focusToken)for(NSUInteger index=0;index<tasks.count;index++)if([tasks[index][@"token"] isEqual:focusToken]){controller.selectedIndex=index;break;}
    CurrentOverview=controller;OverviewWindow=[[UIWindow alloc] initWithWindowScene:scene];OverviewWindow.accessibilityIdentifier=@"orbit.task.overview";OverviewWindow.backgroundColor=UIColor.clearColor;OverviewWindow.opaque=NO;OverviewWindow.windowLevel=UIWindowLevelNormal+80;OverviewWindow.rootViewController=controller;
    [controller installBackdrop];
    OverviewWindow.hidden=NO;[controller.view setNeedsLayout];[controller.view layoutIfNeeded];
    if(!restoredDock&&!focusToken)[controller animateEntrance];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification,controller.cards.count?controller.cards[controller.selectedIndex]:controller.dock);return YES;
}
+ (void)dismiss {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self dismiss];});return;}
    LCOrbitTaskOverviewController *controller=CurrentOverview;if(!controller||controller.restoring)return;
    [controller dismissViewControllerAnimated:NO completion:nil];OverviewWindow.hidden=YES;[controller stopAndRestore];OverviewWindow.rootViewController=nil;OverviewWindow=nil;CurrentOverview=nil;
}
+ (void)dismissAnimated {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self dismissAnimated];});return;}
    [CurrentOverview animateDismissWithCompletion:^{[self dismiss];}];
}
+ (void)dismissAnimatedWithHome {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self dismissAnimatedWithHome];});return;}
    LCOrbitTaskOverviewController *controller=CurrentOverview;if(!controller){[LCOrbitMultitask showHome];return;}
    [controller animateDismissWithCompletion:^{
        [self dismiss];[LCOrbitMultitask showHome];
    }];
}
+ (NSUUID *)dockLaunchTokenForApp:(NSDictionary *)app {
    return SameGuest(ActiveLaunchCover.app,app)?ActiveLaunchCover.token:nil;
}
+ (void)beginDockLaunch:(NSUUID *)token {
    if(token&&[ActiveLaunchCover.token isEqual:token])[ActiveLaunchCover begin];
}
+ (void)cancelDockLaunch:(NSUUID *)token {
    if(token&&[ActiveLaunchCover.token isEqual:token])[ActiveLaunchCover stop];
}
+ (BOOL)isPresentingWindow:(UIViewController *)window { if(!window)return NO;for(LCOrbitTaskPlacement *placement in CurrentOverview.placements)if(placement.controller==window)return YES;return NO; }
@end
