#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <math.h>

// Only the running-process boundary is synthetic. The overview, UIKit views,
// constraints, scene, buttons and view restoration execute production code.
@interface NSObject (SwitcherFixtureAPI)
+ (BOOL)presentInScene:(UIWindowScene *)scene error:(NSError **)error;
+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray<NSDictionary *> *)apps launchHandler:(void(^)(NSDictionary *app))handler error:(NSError **)error;
+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray<NSDictionary *> *)apps dockIconSize:(CGFloat)size iconProvider:(UIView *(^)(NSDictionary *,CGFloat,BOOL))provider launchHandler:(void(^)(NSDictionary *))handler error:(NSError **)error;
+ (void)dismiss;
+ (BOOL)isPresentingWindow:(UIViewController *)window;
+ (NSUUID *)dockLaunchTokenForApp:(NSDictionary *)app;
+ (void)beginDockLaunch:(NSUUID *)token;
+ (void)cancelDockLaunch:(NSUUID *)token;
@end
@interface CALayer (FixtureLayerHitTesting)
@property(nonatomic) BOOL allowsHitTesting;
@end
static NSMutableArray<NSDictionary *> *Tasks;
static NSMutableArray *Results;
static NSDictionary *Activated, *Closed;
static BOOL RejectAction, RejectClose, RestoredBeforeAction;
static NSUInteger HostMoves;
static NSUInteger HomeCount, CloseCalls, EmbeddedActions, InventoryReads;
static NSArray *LastInventory, *VisualApps;
static UIWindow *Bead;
static UIWindow *Host;
static BOOL TaskRemovesViewOnClose;
static UIViewController *DockActiveWindow;
static BOOL GridPresentation;
@interface LCOrbitMultitask : NSObject
@end
NSString *const LCOrbitMultitaskConfigurationChangedNotification=@"LCOrbitMultitaskConfigurationChanged";
NSString *const LCOrbitMultitaskLaunchFailedNotification=@"LCOrbitMultitaskLaunchFailed";
static Class Switcher(void) { return NSClassFromString(@"LCOrbitTaskSwitcher"); }
static void Check(NSString *name, BOOL passed) { [Results addObject:@{@"name":name,@"passed":@(passed),@"details":passed?@"":@"Assertion failed"}]; }
static void FailureDetails(NSDictionary *details) { if(![Results.lastObject[@"passed"] boolValue]){NSMutableDictionary *result=[Results.lastObject mutableCopy];result[@"details"]=details;Results[Results.count-1]=result;} }
@interface FixtureSceneController : UIViewController
@property(nonatomic) BOOL shouldIgnoreSceneUpdates;
@property(nonatomic) BOOL stopped;
@property(nonatomic,strong) id presenter;
@property(nonatomic,strong) UIView *contentView;
@end
@implementation FixtureSceneController
- (BOOL)isAppRunning { return !self.stopped; }
@end
// The cross-process capture transport is the boundary double. Production
// still installs the returned real pixel layer, hides hosts and handles input.
@interface FixtureCapturedPresenter : NSObject
@property(nonatomic,strong) UIView *captured;
@end
@implementation FixtureCapturedPresenter
- (UIView *)captureSnapshotPresentationView { return self.captured; }
@end
@interface FixtureLegacyPresenter : NSObject
@property(nonatomic,strong) UIView *captured;
@end
@implementation FixtureLegacyPresenter
- (UIView *)newSnapshotPresentationView { return self.captured; }
@end
@interface FixtureTaskController : UIViewController <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) FixtureSceneController *appSceneVC;
@end
@interface FixtureTaskView : UIView
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UIView *originalParent;
@end
@implementation FixtureTaskView
- (void)willMoveToSuperview:(UIView *)parent {
    HostMoves++;
    [super willMoveToSuperview:parent];
}
@end
@implementation FixtureTaskController
- (void)embeddedPressed { EmbeddedActions++; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 5; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=@[@"整理本周的阅读笔记",@"给新想法留一点时间",@"继续昨天的项目",@"周末散步和阅读",@"记录今天的小事"][indexPath.row];cell.textLabel.font=[UIFont systemFontOfSize:15];cell.detailTextLabel.text=indexPath.row==0?@"已完成 · 今天 09:41":@"今天 · 轻点查看详情";cell.accessoryType=indexPath.row==0?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { EmbeddedActions++; }
- (void)loadView { FixtureTaskView *view=[FixtureTaskView new];view.owner=self;self.view=view; }
@end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation LCOrbitMultitask
+ (NSArray *)runningTasks { InventoryReads++;return [Tasks copy]; }
+ (NSArray *)runningTasksForApps:(NSArray *)apps { LastInventory=apps;return [Tasks copy]; }
+ (BOOL)usesAdaptiveSwitcher { return YES; }
+ (BOOL)usesNativeTaskWindows { return NO; }
+ (NSInteger)taskSwitcherPresentation { return GridPresentation?1:0; }
+ (BOOL)isManagingWindows { return YES; }
+ (id)activeWindow { return DockActiveWindow; }
+ (BOOL)activateTask:(NSDictionary *)task error:(NSError **)error {
    RestoredBeforeAction = ((UIViewController *)task[@"window"]).view.superview==Host.rootViewController.view && ![Switcher() isPresentingWindow:task[@"window"]];
    if(RejectAction) { if(error) *error=[NSError errorWithDomain:@"fixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"This task has ended."}];return NO; }
    Activated=task;
    for(NSDictionary *entry in Tasks) ((UIViewController *)entry[@"window"]).view.hidden=entry!=task;
    return YES;
}
+ (BOOL)closeTaskFromOverview:(NSDictionary *)task error:(NSError **)error {
    RestoredBeforeAction = ((UIViewController *)task[@"window"]).view.superview==Host.rootViewController.view && ![Switcher() isPresentingWindow:task[@"window"]];
    CloseCalls++;
    if(RejectClose) { if(error)*error=[NSError errorWithDomain:@"fixture" code:2 userInfo:@{NSLocalizedDescriptionKey:@"此任务已重新启动。"}];return NO; }
    Closed=task;[Tasks removeObjectIdenticalTo:task];((FixtureSceneController *)((FixtureTaskController *)task[@"window"]).appSceneVC).stopped=YES;
    if(TaskRemovesViewOnClose)[((UIViewController *)task[@"window"]).view removeFromSuperview];return YES;
}
+ (void)showHome {
    HomeCount++;
    for(NSDictionary *entry in Tasks) ((UIViewController *)entry[@"window"]).view.hidden=YES;
}
@end
#pragma clang diagnostic pop
static UIView *Find(UIView *view, NSString *identifier) {
    if([view.accessibilityIdentifier isEqual:identifier]) return view;
    for(UIView *child in view.subviews) { UIView *found=Find(child,identifier);if(found)return found; }return nil;
}
static UIWindow *Overview(UIWindowScene *scene) { for(UIWindow *window in scene.windows) if(!window.hidden && window.rootViewController && [window.accessibilityIdentifier isEqual:@"orbit.task.overview"]) return window;return nil; }
static UIWindow *LaunchCover(UIWindowScene *scene) { for(UIWindow *window in scene.windows) if(!window.hidden && [window.accessibilityIdentifier isEqual:@"orbit.dock.launch-cover"]) return window;return nil; }
// Test-only gesture values exercise the actual installed handler/delegate,
// without private UIKit touch injection or a production testing API.
@interface FixturePan : UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState fixtureState;
@property(nonatomic) CGPoint fixtureTranslation, fixtureVelocity;
@property(nonatomic,weak) UIView *fixtureView;
@end
@implementation FixturePan
- (UIGestureRecognizerState)state { return self.fixtureState; }
- (CGPoint)translationInView:(UIView *)view { return self.fixtureTranslation; }
- (CGPoint)velocityInView:(UIView *)view { return self.fixtureVelocity; }
- (UIView *)view { return self.fixtureView; }
@end
@interface FixtureTap : UITapGestureRecognizer
@property(nonatomic,weak) UIView *fixtureView;
@end
@implementation FixtureTap
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateEnded; }
- (UIView *)view { return self.fixtureView; }
@end
static void Pump(NSTimeInterval seconds) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:end]; }
static UIPanGestureRecognizer *InstalledPan(UIView *card) { for(UIGestureRecognizer *gesture in card.gestureRecognizers)if([gesture isKindOfClass:UIPanGestureRecognizer.class])return (id)gesture;return nil; }
static void Pan(UIWindowScene *scene, NSString *token, UIGestureRecognizerState state, CGPoint translation, CGPoint velocity) {
    UIView *card=Find(Overview(scene),[@"orbit.task.card." stringByAppendingString:token]);UIPanGestureRecognizer *installed=InstalledPan(card);
    FixturePan *pan=[FixturePan new];pan.fixtureView=card;pan.fixtureState=state;pan.fixtureTranslation=translation;pan.fixtureVelocity=velocity;
    SEL action=NSSelectorFromString(@"cardPanned:");id target=installed.delegate;
    if([target respondsToSelector:action])((void(*)(id,SEL,id))objc_msgSend)(target,action,pan);
}
static void BeginTap(UIWindowScene *scene, NSString *token) {
    UIView *view=token?Find(Overview(scene),[@"orbit.task.card." stringByAppendingString:token]):Overview(scene).rootViewController.view;
    for(UIGestureRecognizer *gesture in view.gestureRecognizers)if([gesture isKindOfClass:UITapGestureRecognizer.class]) {
        FixtureTap *tap=[FixtureTap new];tap.fixtureView=view;id target=gesture.delegate;SEL action=NSSelectorFromString(token?@"cardTapped:":@"backgroundTapped:");
        if([target respondsToSelector:action])((void(*)(id,SEL,id))objc_msgSend)(target,action,tap);break;
    }
}
static void Tap(UIWindowScene *scene, NSString *token) { BeginTap(scene,token);Pump(.4); }
static NSUInteger ChromeCount(UIView *view) {
    for(NSDictionary *task in Tasks)if(view==((UIViewController *)task[@"window"]).view)return 0;
    if([view.accessibilityIdentifier hasPrefix:@"orbit.dock"])return 0;
    NSUInteger count=([view isKindOfClass:UIButton.class]||[view isKindOfClass:UIPageControl.class]||([view isKindOfClass:UILabel.class]&&![view.accessibilityIdentifier hasPrefix:@"orbit.task.name."]));
    for(UIView *child in view.subviews)count+=ChromeCount(child);return count;
}
static NSDictionary *Task(NSString *token, UIColor *color) {
    FixtureTaskController *controller=[FixtureTaskController new];controller.appSceneVC=[FixtureSceneController new];
    [Host.rootViewController addChildViewController:controller];
    controller.view.frame=Host.bounds;controller.view.backgroundColor=color;[Host.rootViewController.view addSubview:controller.view];[controller didMoveToParentViewController:Host.rootViewController];
    ((FixtureTaskView *)controller.view).originalParent=Host.rootViewController.view;
    UIStackView *content=[UIStackView new];content.axis=UILayoutConstraintAxisVertical;content.spacing=12;content.translatesAutoresizingMaskIntoConstraints=NO;[controller.view addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor constant:20],[content.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor constant:-20],[content.topAnchor constraintEqualToAnchor:controller.view.topAnchor constant:28]]];
    NSArray *lines=([token isEqual:@"A"]||[token isEqual:@"V1"])?@[@"阅读",@"把灵感留在今天",@"刚刚 · 继续上次阅读",@"在安静的午后，打开一篇还没读完的文章。切换回来时，内容和进度都留在原处。",@"今天想看的内容",@"01   设计里的日常细节",@"02   一段没有读完的旅行",@"03   收藏夹里的灵感",@"阅读进度  42%"]:@[@"待办清单",@"今天的安排",@"正在编辑 · 本地已保存",@"✓   整理本周的阅读笔记",@"○   给新想法留一点时间",@"○   继续昨天的项目",@"所有修改都会保留",@"上次更新  09:41"];
    if([token isEqual:@"V3"])lines=@[@"备忘录",@"周末的想法",@"今天 09:41",@"在城市里慢慢走",@"• 带一本还没读完的书",@"• 找一家安静的咖啡馆",@"• 记录路上遇到的小事",@"一切都可以从这一页开始。"] ;
    if([token isEqual:@"B"]||[token isEqual:@"V2"])lines=[lines subarrayWithRange:NSMakeRange(0,3)];
    for(NSUInteger line=0;line<lines.count;line++) { UILabel *label=[UILabel new];label.text=lines[line];label.numberOfLines=0;label.font=line==1?[UIFont systemFontOfSize:26 weight:UIFontWeightBold]:[UIFont systemFontOfSize:line==0?16:14 weight:line==0?UIFontWeightSemibold:UIFontWeightRegular];label.textColor=(line==0)?color:((line==2||line==lines.count-1)?UIColor.secondaryLabelColor:UIColor.labelColor);[content addArrangedSubview:label]; }
    if([token isEqual:@"B"]||[token isEqual:@"V2"]) {
        UITableView *list=[[UITableView alloc] initWithFrame:CGRectMake(20,132,controller.view.bounds.size.width-40,330) style:UITableViewStyleInsetGrouped];list.dataSource=controller;list.delegate=controller;list.rowHeight=56;list.sectionHeaderHeight=0;list.accessibilityIdentifier=[@"fixture.list." stringByAppendingString:token];[controller.view addSubview:list];
    }
    UIButton *embedded=[UIButton buttonWithType:UIButtonTypeSystem];embedded.frame=CGRectMake(20,([token isEqual:@"B"]||[token isEqual:@"V2"])?490:440,220,44);[embedded setTitle:@"打开内容 / 完成事项" forState:UIControlStateNormal];[embedded addTarget:controller action:NSSelectorFromString(@"embeddedPressed") forControlEvents:UIControlEventTouchUpInside];embedded.accessibilityIdentifier=[@"fixture.action." stringByAppendingString:token];[controller.view addSubview:embedded];
    controller.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:token];[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [@{@"CFBundleIdentifier":[@"fixture." stringByAppendingString:token],@"CFBundleIconFiles":@[@"Icon"]} writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES];
    UIGraphicsImageRendererFormat *iconFormat=[UIGraphicsImageRendererFormat defaultFormat];iconFormat.scale=1;
    UIGraphicsImageRenderer *iconRenderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64,64) format:iconFormat];
    UIImage *icon=[iconRenderer imageWithActions:^(UIGraphicsImageRendererContext *context){[color setFill];UIRectFill(CGRectMake(0,0,64,64));[token drawInRect:CGRectMake(12,10,50,50) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:30 weight:UIFontWeightBold],NSForegroundColorAttributeName:UIColor.whiteColor}];}];
    [UIImagePNGRepresentation(icon) writeToFile:[folder stringByAppendingPathComponent:@"LCAppIconLight.png"] atomically:YES];
    return @{@"path":[token stringByAppendingString:@".app"],@"uuid":token,@"folder":folder,@"title":[token isEqual:@"A"]?@"阅读 · 正在查看的长标题文章与收藏内容":[token isEqual:@"V1"]?@"阅读":[token isEqual:@"V3"]?@"备忘录":@"待办清单",@"identity":token,@"token":token,@"native":@NO,@"active":@([token isEqual:@"B"]||[token isEqual:@"V2"]),@"window":controller};
}
static void Screenshot(UIView *window, NSString *path) {
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
        NSArray *windows=[window.window.windowScene.windows sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a,UIWindow *b){return a.windowLevel>b.windowLevel?NSOrderedAscending:a.windowLevel<b.windowLevel?NSOrderedDescending:NSOrderedSame;}];
        for(UIWindow *layer in windows)if(!layer.hidden)[layer drawViewHierarchyInRect:layer.bounds afterScreenUpdates:YES]; }];
    [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
}
static void WriteReport(NSString *directory) {
    NSUInteger failures=0;for(NSDictionary *check in Results)if(![check[@"passed"] boolValue])failures++;
    NSDictionary *report=@{@"count":@(Results.count),@"failures":@(failures),@"results":Results,@"runtime":UIDevice.currentDevice.systemVersion,@"gestureEvidence":@"Installed real handlers/delegates driven by test-only recognizers, not synthetic system touches",@"landscapeEvidence":@"Synthetic 667x375 root-view layout; not hardware rotation",@"remoteSurfaceEvidence":@"Synthetic UIKit views only; on-device remote scene verification remains required"};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[directory stringByAppendingPathComponent:@"result.json"] atomically:YES];
}
static void Run(UIWindowScene *scene) {
    Results=[NSMutableArray array];Tasks=[NSMutableArray array];Class switcher=Switcher();Check(@"production-overview-class-is-linked",switcher!=Nil);
    NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TaskSwitcherEvidence"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSArray *visualStatusApps=nil;
    UIView *(^visualStatusIcons)(NSDictionary *,CGFloat,BOOL)=nil;
    if(switcher) {
        NSMutableDictionary *first=[Task(@"A",UIColor.systemIndigoColor) mutableCopy],*second=[Task(@"B",UIColor.systemTealColor) mutableCopy];first[@"active"]=@NO;second[@"active"]=@YES;[Tasks addObjectsFromArray:@[first,second]];
        UIViewController *a=first[@"window"],*b=second[@"window"];UIView *original=a.view.superview;
        a.view.bounds=CGRectMake(3,4,300,500);a.view.center=CGPointMake(170,280);a.view.transform=CGAffineTransformMakeScale(.9,.9);a.view.alpha=.37;a.view.hidden=YES;a.view.userInteractionEnabled=YES;a.view.autoresizingMask=UIViewAutoresizingFlexibleRightMargin;a.view.translatesAutoresizingMaskIntoConstraints=NO;
        NSLayoutConstraint *width=[a.view.widthAnchor constraintEqualToConstant:300];width.active=YES;
        NSLayoutConstraint *external=[a.view.leadingAnchor constraintEqualToAnchor:original.leadingAnchor constant:20];external.active=YES;
        NSLayoutConstraint *cross=[a.view.heightAnchor constraintEqualToAnchor:b.view.heightAnchor multiplier:500/Host.bounds.size.height];cross.priority=UILayoutPriorityDefaultLow;cross.active=YES;
        // Keep a valid layout when the referenced task closes. The previous
        // live-view borrower masked this fixture's missing fallback/position.
        NSLayoutConstraint *fallback=[a.view.heightAnchor constraintEqualToConstant:500];fallback.priority=UILayoutPriorityDefaultLow-1;fallback.active=YES;
        [a.view.centerYAnchor constraintEqualToAnchor:original.topAnchor constant:280].active=YES;
        [original layoutIfNeeded];
        a.view.layer.cornerRadius=9;a.view.layer.zPosition=.1;
        NSUInteger originalIndex=[original.subviews indexOfObjectIdenticalTo:a.view];CGRect bounds=a.view.bounds;CGPoint center=a.view.center;CGAffineTransform transform=a.view.transform;
        UITextField *input=[[UITextField alloc] initWithFrame:CGRectMake(20,60,150,40)];input.text=@"Input state";[b.view addSubview:input];[input becomeFirstResponder];
        NSUInteger movesBeforeOverview=HostMoves;
        CALayer *hostedLayer=[NSClassFromString(@"CALayerHost") layer];
        [b.view.layer addSublayer:hostedLayer];
        b.view.layer.allowsHitTesting=YES;hostedLayer.allowsHitTesting=YES;
        NSError *error=nil;BOOL shown=[switcher presentInScene:scene error:&error];UIWindow *overview=Overview(scene);
        UIView *activeCard=Find(overview,@"orbit.task.card.B");
        Pump(.08);
        CATransform3D shownTransform=activeCard.layer.presentationLayer.transform;
        CGFloat liveEntranceScale=b.view.layer.presentationLayer.transform.m11;
        Check(@"entrance-contracts-the-original-app-surface",shownTransform.m11>1.03&&liveEntranceScale>.70&&liveEntranceScale<1.01);
        Pump(.68);
        Check(@"keeps-live-scene-in-original-hierarchy",shown&&a.view.superview==original&&a.parentViewController==Host.rootViewController&&![a.view isDescendantOfView:overview]&&HostMoves==movesBeforeOverview);
        Check(@"keeps-logical-guest-bounds",CGRectEqualToRect(a.view.bounds,bounds));
        Check(@"preview-input-disabled-with-external-constraints-suspended",!a.view.userInteractionEnabled&&!external.active&&!cross.active);
        Check(@"preview-suppresses-layer-hit-testing-without-hiding-remote-content",!b.view.layer.allowsHitTesting&&hostedLayer&&!hostedLayer.allowsHitTesting&&!hostedLayer.hidden);
        Check(@"real-app-content-visible-in-original-host-window",!a.view.hidden&&!b.view.hidden&&a.view.alpha>0&&b.view.alpha>0&&b.view.window==Host&&![b.view isDescendantOfView:overview]);
        Check(@"transparent-input-window-stays-above-host-and-bead",!overview.isKeyWindow&&Host.isKeyWindow&&overview.windowLevel>Bead.windowLevel&&overview.rootViewController.view.backgroundColor.CGColor&&CGColorGetAlpha(overview.rootViewController.view.backgroundColor.CGColor)==0);
        UIVisualEffectView *backdrop=(id)Find(original,@"orbit.task.backdrop");
        Check(@"system-material-lives-behind-the-live-apps",[backdrop isKindOfClass:UIVisualEffectView.class]&&backdrop.effect!=nil&&[original.subviews indexOfObjectIdenticalTo:backdrop]<[original.subviews indexOfObjectIdenticalTo:a.view]&&[original.subviews indexOfObjectIdenticalTo:backdrop]<[original.subviews indexOfObjectIdenticalTo:b.view]);
        Check(@"only-app-identity-no-management-chrome",ChromeCount(overview.rootViewController.view)==0);
        Check(@"overview-transition-is-interactive",((UIScrollView *)Find(overview,@"orbit.task.pages")).layer.speed==1);
        UIScrollView *pages=(id)Find(overview,@"orbit.task.pages");CGFloat initialOffset=pages.contentOffset.x;Check(@"horizontal-inertial-scroll",pages.scrollEnabled&&!pages.pagingEnabled&&pages.contentSize.width>pages.bounds.size.width);
        UIView *cardA=Find(overview,@"orbit.task.card.A"),*cardB=Find(overview,@"orbit.task.card.B");
        Check(@"task-cards-do-not-cover-live-content",![Find(cardB,@"orbit.task.preview.B") isKindOfClass:UIVisualEffectView.class]);
        UIView *previewB=Find(cardB,@"orbit.task.preview.B");
        Check(@"card-preview-leaves-real-app-visible",previewB&&!previewB.hidden&&(!previewB.backgroundColor.CGColor||CGColorGetAlpha(previewB.backgroundColor.CGColor)<.05));
        Check(@"task-input-layer-is-transparent",Find(cardB,@"orbit.task.shield.B")!=nil&&CGColorGetAlpha(((UIView *)Find(cardB,@"orbit.task.shield.B")).backgroundColor.CGColor)==0);
        CGRect liveFrame=[b.view convertRect:b.view.bounds toView:overview],previewFrame=[previewB convertRect:previewB.bounds toView:overview];
        Check(@"live-app-fills-the-rounded-preview",CGRectEqualToRect(CGRectIntegral(liveFrame),CGRectIntegral(previewFrame))&&b.view.layer.cornerRadius>15&&b.view.clipsToBounds);
        Check(@"front-card-orders-real-surfaces-the-same-way",b.view.layer.zPosition>a.view.layer.zPosition&&b.view.alpha==1&&a.view.alpha==1);
        CGFloat behindGap=CGRectGetMidX(cardB.frame)-CGRectGetMidX(cardA.frame);
        Check(@"older-card-stacks-close-behind-at-slightly-smaller-scale",behindGap>35&&behindGap<pages.bounds.size.width*.22&&
            CGRectGetHeight(cardA.frame)<CGRectGetHeight(cardB.frame)&&
            fabs(CGRectGetMidY(cardA.frame)-CGRectGetMidY(cardB.frame))<5);
        Check(@"active-task-is-second-before-layout",[Tasks[1][@"active"] boolValue]);
        CGFloat stride=pages.contentSize.width-overview.bounds.size.width;
        CGPoint cardACenter=[cardA.superview convertPoint:cardA.center toView:overview],cardBCenter=[cardB.superview convertPoint:cardB.center toView:overview];
        Check(@"current-app-centered-at-original-slot-without-reordering",cardACenter.x<cardBCenter.x&&fabs(initialOffset-stride)<1);
        FailureDetails(@{@"cardAFrame":NSStringFromCGRect(cardA.frame),@"cardBFrame":NSStringFromCGRect(cardB.frame),@"initialOffset":@(initialOffset),@"offset":@(pages.contentOffset.x),@"boundsOrigin":@(pages.bounds.origin.x),@"stride":@(stride),@"safe":NSStringFromUIEdgeInsets(overview.safeAreaInsets)});
        CGPoint actualCenter=[b.view convertPoint:CGPointMake(CGRectGetMidX(b.view.bounds),CGRectGetMidY(b.view.bounds)) toView:overview];
        CGPoint expectedCenter=[cardB convertPoint:CGPointMake(cardB.bounds.size.width/2,34+(cardB.bounds.size.height-34)/2) toView:overview];
        Check(@"live-scene-aligns-with-transparent-preview-area",hypot(actualCenter.x-expectedCenter.x,actualCenter.y-expectedCenter.y)<1);
        CGPoint snap=CGPointMake(stride-.5,0);[pages.delegate scrollViewWillEndDragging:pages withVelocity:CGPointMake(-1,0) targetContentOffset:&snap];
        Check(@"directional-flick-advances-even-with-tiny-projection",fabs(snap.x)<1);
        Check(@"horizontal-settle-uses-short-native-deceleration-without-edge-bounce",pages.decelerationRate==UIScrollViewDecelerationRateFast&&!pages.bounces);
        if([pages.delegate respondsToSelector:@selector(scrollViewWillBeginDragging:)])[pages.delegate scrollViewWillBeginDragging:pages];
        pages.contentOffset=CGPointMake(stride*.63,0);[overview.rootViewController.view setNeedsLayout];[overview.rootViewController.view layoutIfNeeded];
        Check(@"horizontal-drag-layout-does-not-reset-offset",fabs(pages.contentOffset.x-stride*.63)<1);
        pages.contentOffset=CGPointMake(stride*.20,0);
        Check(@"scrolling-to-earlier-card-keeps-later-card-on-top",
            b.view.layer.zPosition>a.view.layer.zPosition&&[pages.subviews indexOfObjectIdenticalTo:cardB]>[pages.subviews indexOfObjectIdenticalTo:cardA]&&CGRectGetMinY(cardA.frame)>CGRectGetMinY(cardB.frame));
        if([pages.delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)])[pages.delegate scrollViewDidEndDragging:pages willDecelerate:NO];pages.contentOffset=CGPointMake(stride,0);
        Check(@"cards-overlap",cardA&&cardB&&CGRectIntersectsRect(cardA.frame,cardB.frame));
        Check(@"staircase-cards-remain-opaque",cardA.alpha==1&&cardB.alpha==1);
        UIView *shield=Find(cardB,@"orbit.task.shield.B");UIView *embedded=Find(b.view,@"fixture.action.B");
        b.view.userInteractionEnabled=YES;CGPoint buttonPoint=CGPointMake(CGRectGetMidX(shield.frame),CGRectGetMinY(shield.frame)+20);UIView *hit=[cardB hitTest:buttonPoint withEvent:nil];b.view.userInteractionEnabled=NO;
        Check(@"foreground-shield-blocks-app-button-area",embedded&&shield&&hit==shield&&!b.view.hidden&&b.view.window!=overview&&![b.view isDescendantOfView:cardB]);
        UITableView *liveList=(id)Find(b.view,@"fixture.list.B");CGPoint listPoint=CGPointMake(CGRectGetMidX(shield.frame),CGRectGetMidY(shield.frame));UIView *listHit=[cardB hitTest:listPoint withEvent:nil];
        Check(@"foreground-shield-blocks-app-list-area",liveList.numberOfSections>0&&[liveList numberOfRowsInSection:0]==5&&listHit==shield&&EmbeddedActions==0);
        BOOL fullSurface=YES;
        for(NSInteger y=0;y<3;y++)for(NSInteger x=0;x<3;x++)fullSurface=fullSurface&&[cardB hitTest:CGPointMake(CGRectGetMinX(shield.frame)+(x+.5)*shield.bounds.size.width/3,CGRectGetMinY(shield.frame)+(y+.5)*shield.bounds.size.height/3) withEvent:nil]==shield;
        Check(@"entire-app-content-area-is-a-task-gesture-surface",fullSurface&&[shield isDescendantOfView:pages]&&InstalledPan(cardB)!=nil);
        Check(@"unified-inventory-api-is-available",[switcher respondsToSelector:@selector(presentInScene:apps:launchHandler:error:)]);
        UIImageView *icon=(id)Find(overview,@"orbit.task.icon.A");Check(@"loads-real-lc-app-icon",CGSizeEqualToSize(icon.image.size,CGSizeMake(64,64)));
        UILabel *name=(id)Find(overview,@"orbit.task.name.A");Check(@"long-name-truncates-outside-preview",name.numberOfLines==1&&name.lineBreakMode==NSLineBreakByTruncatingTail&&![name isDescendantOfView:a.view.superview]);
        Check(@"escape-handled",[overview.rootViewController accessibilityPerformEscape]);
        Check(@"escape-restores-parent-order",a.view.superview==original&&a.parentViewController==Host.rootViewController&&[original.subviews indexOfObjectIdenticalTo:a.view]==originalIndex);
        Check(@"escape-restores-exact-geometry",CGRectEqualToRect(a.view.bounds,bounds)&&CGPointEqualToPoint(a.view.center,center)&&CGAffineTransformEqualToTransform(a.view.transform,transform));
        Check(@"dismiss-restores-layer-hit-testing",b.view.layer.allowsHitTesting&&hostedLayer.allowsHitTesting);
        Check(@"escape-restores-corners-depth-and-backdrop",a.view.layer.cornerRadius==9&&fabs(a.view.layer.zPosition-.1)<.001&&!backdrop.superview);
        FailureDetails(@{@"bounds":NSStringFromCGRect(a.view.bounds),@"expectedBounds":NSStringFromCGRect(bounds),@"center":NSStringFromCGPoint(a.view.center),@"expectedCenter":NSStringFromCGPoint(center)});
        Check(@"escape-restores-all-input-visibility-constraints",a.view.hidden&&fabs(a.view.alpha-.37)<.0001&&a.view.userInteractionEnabled&&!a.view.translatesAutoresizingMaskIntoConstraints&&a.view.autoresizingMask==UIViewAutoresizingFlexibleRightMargin&&width.active&&external.active&&cross.active&&input.isFirstResponder&&!b.view.hidden&&!Activated);
        Check(@"overview-never-detaches-remote-host-even-on-dismiss",HostMoves==movesBeforeOverview&&![switcher isPresentingWindow:a]&&Overview(scene)==nil&&Host.isKeyWindow);
        FixtureSceneController *remote=((FixtureTaskController *)b).appSceneVC;
        FixtureCapturedPresenter *modern=[FixtureCapturedPresenter new];remote.presenter=modern;
        NSError *captureError=nil;BOOL liveShown=[switcher presentInScene:scene error:&captureError];
        Check(@"failed-remote-snapshot-api-cannot-blank-live-preview",liveShown&&!captureError&&Overview(scene)&&!b.view.hidden&&b.view.window==Host&&![b.view isDescendantOfView:Overview(scene)]);
        [switcher dismiss];remote.presenter=nil;
        [switcher presentInScene:scene error:NULL];Tap(scene,@"A");
        Check(@"tap-resumes-exact-task-after-restoring",[Activated[@"token"] isEqual:@"A"]&&RestoredBeforeAction&&!a.view.hidden&&b.view.hidden);
        Check(@"task-resume-restores-exact-task",Activated[@"window"]==a);
        [switcher presentInScene:scene error:NULL];UIView *card=Find(Overview(scene),@"orbit.task.card.B");UIPanGestureRecognizer *installed=InstalledPan(card);
        Check(@"actual-card-pan-is-installed",installed!=nil&&installed.delegate!=nil);
        FixturePan *direction=[FixturePan new];direction.fixtureVelocity=CGPointMake(900,-30);direction.fixtureView=card;
        Check(@"horizontal-drag-rejected-by-close-recognizer",installed&&![installed.delegate gestureRecognizerShouldBegin:direction]);
        direction.fixtureVelocity=CGPointMake(20,-900);Check(@"vertical-drag-accepted-by-close-recognizer",installed&&[installed.delegate gestureRecognizerShouldBegin:direction]);
        Pan(scene,@"B",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(0,-100));Pan(scene,@"B",UIGestureRecognizerStateChanged,CGPointMake(0,-55),CGPointMake(0,-100));
        Check(@"card-follows-upward-finger",Find(Overview(scene),@"orbit.task.card.B").transform.ty< -20);
        UIView *dragCard=Find(Overview(scene),@"orbit.task.card.B");CGPoint liveDragCenter=[b.view convertPoint:CGPointMake(CGRectGetMidX(b.view.bounds),CGRectGetMidY(b.view.bounds)) toView:Overview(scene)];CGPoint dragCenter=[dragCard convertPoint:CGPointMake(dragCard.bounds.size.width/2,34+(dragCard.bounds.size.height-34)/2) toView:Overview(scene)];
        Check(@"live-content-follows-whole-card-upward-drag",hypot(liveDragCenter.x-dragCenter.x,liveDragCenter.y-dragCenter.y)<1);
        CGFloat draggedY=Find(Overview(scene),@"orbit.task.card.B").transform.ty;
        [Overview(scene).rootViewController.view setNeedsLayout];[Overview(scene).rootViewController.view layoutIfNeeded];
        Check(@"layout-refresh-preserves-in-progress-drag",fabs(Find(Overview(scene),@"orbit.task.card.B").transform.ty-draggedY)<1);
        Pan(scene,@"B",UIGestureRecognizerStateCancelled,CGPointMake(0,-400),CGPointMake(0,-1200));Pump(.5);
        Check(@"cancelled-flick-never-closes",CloseCalls==0&&Tasks.count==2&&fabs(Find(Overview(scene),@"orbit.task.card.B").transform.ty)<1);
        Pan(scene,@"B",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(0,-100));Pan(scene,@"B",UIGestureRecognizerStateEnded,CGPointMake(0,-35),CGPointMake(0,-100));Pump(.5);
        Check(@"short-flick-springs-back",CloseCalls==0&&fabs(Find(Overview(scene),@"orbit.task.card.B").transform.ty)<1);
        Pan(scene,@"B",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(0,300));Pan(scene,@"B",UIGestureRecognizerStateEnded,CGPointMake(0,400),CGPointMake(0,1400));Pump(.5);
        Check(@"downward-drag-does-not-close",CloseCalls==0&&Tasks.count==2);
        Pan(scene,@"B",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(900,-5));Pan(scene,@"B",UIGestureRecognizerStateEnded,CGPointMake(300,-80),CGPointMake(1200,-900));Pump(.4);
        Check(@"horizontal-scroll-does-not-close",CloseCalls==0&&Tasks.count==2);
        direction.fixtureVelocity=CGPointMake(900,-30);Check(@"horizontal-drag-is-routed-to-page-scroll",![installed.delegate gestureRecognizerShouldBegin:direction]);
        // Closing must update the existing task rail in place. Replacing the
        // overview tears down the rail and makes it flash on re-presentation.
        UIWindow *windowBeforeClose=Overview(scene);
        UIView *dockBeforeClose=Find(Overview(scene),@"orbit.dock");
        UIView *dockIconBeforeClose=Find(Overview(scene),@"orbit.dock.app.0");
        Pan(scene,@"B",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(0,-100));Pan(scene,@"B",UIGestureRecognizerStateEnded,CGPointMake(0,-400),CGPointMake(0,-150));
        for(NSUInteger attempt=0;attempt<45&&!CloseCalls;attempt++)Pump(.01);
        Pump(.04);
        CALayer *reflowingApp=a.view.layer.presentationLayer;
        Check(@"surviving-app-animates-from-its-previous-position",reflowingApp&&fabs(reflowingApp.position.x-a.view.center.x)>10);
        Pump(.35);
        Check(@"upward-distance-closes-only-exact-card",[Closed[@"token"] isEqual:@"B"]&&Tasks.count==1&&Tasks.firstObject==first&&CloseCalls==1);
        Check(@"close-reflow-has-no-ghost-view",Overview(scene)&&[switcher isPresentingWindow:a]&&!Find(Overview(scene),@"orbit.task.card.B"));
        Check(@"closing-one-task-keeps-overview-visible",Overview(scene)==windowBeforeClose&&Tasks.count==1&&Find(Overview(scene),@"orbit.task.card.A")!=nil);
        Check(@"closing-task-keeps-the-same-dock",Overview(scene)&&Find(Overview(scene),@"orbit.dock")==dockBeforeClose);
        Check(@"closing-task-keeps-the-same-dock-icons",Overview(scene)&&Find(Overview(scene),@"orbit.dock.app.0")==dockIconBeforeClose);
        Check(@"closing-task-keeps-dock-visible",Overview(scene)&&Find(Overview(scene),@"orbit.dock").alpha==1&&Find(Overview(scene),@"orbit.dock.scroll").alpha==1);
        FailureDetails(@{@"dockMatches":@(Find(Overview(scene),@"orbit.dock")==dockBeforeClose),@"dockAlpha":@(Find(Overview(scene),@"orbit.dock").alpha),@"scrollAlpha":@(Find(Overview(scene),@"orbit.dock.scroll").alpha),@"dockHidden":@(Find(Overview(scene),@"orbit.dock").hidden),@"overviewHidden":@(Overview(scene).hidden),@"overviewClass":NSStringFromClass(Overview(scene).rootViewController.class)});
        [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskConfigurationChangedNotification object:nil userInfo:@{@"exitedWindow":b}];
        Check(@"closed-process-exit-does-not-dismiss-surviving-cards",Find(Overview(scene),@"orbit.task.card.A")!=nil);
        if(!Overview(scene))[switcher presentInScene:scene error:NULL];
        RejectClose=YES;Pan(scene,@"A",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(0,-100));Pan(scene,@"A",UIGestureRecognizerStateEnded,CGPointMake(0,-15),CGPointMake(0,-1200));Pump(.5);
        Check(@"velocity-close-rejects-stale-target-without-other-close",CloseCalls==2&&Tasks.count==1&&[Overview(scene).rootViewController.presentedViewController isKindOfClass:UIAlertController.class]);
        FailureDetails(@{@"calls":@(CloseCalls),@"tasks":@(Tasks.count),@"restored":@(RestoredBeforeAction),@"bounds":NSStringFromCGRect(a.view.bounds),@"overview":@(Overview(scene)!=nil)});
        RejectClose=NO;[switcher dismiss];RejectAction=YES;[switcher presentInScene:scene error:NULL];Tap(scene,@"A");
        Check(@"rejected-open-reports-real-error-only",RestoredBeforeAction&&Tasks.count==1&&[Overview(scene).rootViewController.presentedViewController isKindOfClass:UIAlertController.class]);
        FailureDetails(@{@"restored":@(RestoredBeforeAction),@"bounds":NSStringFromCGRect(a.view.bounds),@"overview":@(Overview(scene)!=nil)});
        RejectAction=NO;[switcher dismiss];
        Activated=nil;[switcher presentInScene:scene error:NULL];BeginTap(scene,@"A");
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:UIApplication.sharedApplication];Pump(.4);
        Check(@"interrupted-selection-does-not-reactivate-task",Activated==nil&&Overview(scene)==nil&&a.view.superview==original);
        for(NSString *notification in @[UIApplicationWillResignActiveNotification,@"LCOrbitMultitaskConfigurationChanged",UISceneDidDisconnectNotification]) {
            [switcher presentInScene:scene error:NULL];[NSNotificationCenter.defaultCenter postNotificationName:notification object:[notification isEqual:UISceneDidDisconnectNotification]?scene:nil];
            Check([@"lifecycle-restores-" stringByAppendingString:notification],a.view.superview==original&&Overview(scene)==nil);
        }
        ((FixtureTaskController *)a).appSceneVC.shouldIgnoreSceneUpdates=YES;[switcher presentInScene:scene error:NULL];
        Check(@"pip-owned-content-never-borrowed",a.view.superview==original&&![switcher isPresentingWindow:a]&&Find(Overview(scene),@"orbit.task.pip.A")!=nil);[switcher dismiss];((FixtureTaskController *)a).appSceneVC.shouldIgnoreSceneUpdates=NO;
        [switcher presentInScene:scene error:NULL];Pump(.45);NSUInteger beforeHome=HomeCount;CGFloat restingScale=a.view.transform.a;BeginTap(scene,nil);Pump(.09);
        CALayer *exitingSurface=a.view.layer.presentationLayer;
        Check(@"background-dismiss-moves-the-live-surface-before-home",Overview(scene)!=nil&&HomeCount==beforeHome&&exitingSurface.opacity<.99&&exitingSurface.opacity>.05&&exitingSurface.affineTransform.a<restingScale);
        Pump(.4);
        Check(@"background-tap-restores-home-retains-task",HomeCount==beforeHome+1&&a.view.superview==original&&a.view.hidden&&Tasks.count==1&&Overview(scene)==nil);
        TaskRemovesViewOnClose=YES;NSDictionary *onlyTask=Tasks.firstObject;NSArray *onlyInventory=@[onlyTask];[switcher presentInScene:scene apps:onlyInventory launchHandler:nil error:NULL];
        UIWindow *emptyPage=Overview(scene);UIView *onlyCard=Find(emptyPage,@"orbit.task.card.A");
        Pan(scene,@"A",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(0,-100));Pan(scene,@"A",UIGestureRecognizerStateEnded,CGPointMake(0,-35),CGPointMake(0,-1200));Pump(.5);
        Check(@"closing-last-task-leaves-task-switcher",onlyCard!=nil&&Overview(scene)!=nil&&Find(Overview(scene),@"orbit.task.empty")!=nil&&Find(Overview(scene),@"orbit.dock.app.0")!=nil);
        TaskRemovesViewOnClose=NO;
        [Tasks removeAllObjects];beforeHome=HomeCount;[switcher presentInScene:scene error:NULL];Check(@"empty-overview-returns-home-without-panel",Overview(scene)==nil&&HomeCount==beforeHome+1);
        NSMutableDictionary *native=[Task(@"N",UIColor.systemGreenColor) mutableCopy];native[@"native"]=@YES;NSDictionary *detached=Task(@"D",UIColor.systemPinkColor);UIViewController *detachedController=detached[@"window"];[detachedController.view removeFromSuperview];[Tasks addObjectsFromArray:@[native,detached]];
        [switcher presentInScene:scene error:NULL];Check(@"native-and-unhosted-tasks-excluded",Overview(scene)==nil&&![switcher isPresentingWindow:native[@"window"]]&&![switcher isPresentingWindow:detachedController]);
        for(UIViewController *child in [Host.rootViewController.childViewControllers copy]){[child willMoveToParentViewController:nil];[child.view removeFromSuperview];[child removeFromParentViewController];}
        [Tasks removeAllObjects];for(NSString *token in @[@"V1",@"V2",@"V3"])[Tasks addObject:Task(token,[token isEqual:@"V1"]?UIColor.systemBlueColor:[token isEqual:@"V2"]?UIColor.systemOrangeColor:UIColor.systemGreenColor)];
        NSMutableArray *apps=[NSMutableArray arrayWithArray:Tasks];
        for(NSUInteger i=0;i<7;i++) { NSMutableDictionary *app=[Tasks[i%Tasks.count] mutableCopy];app[@"uuid"]=[NSString stringWithFormat:@"unused-%lu",(unsigned long)i];app[@"title"]=[NSString stringWithFormat:@"未运行 App %lu",(unsigned long)i];[app removeObjectForKey:@"window"];[apps addObject:app]; }
        VisualApps=[apps copy];
        __block NSDictionary *launched=nil;__block BOOL restoredForDock=NO;
        void(^launch)(NSDictionary *)=^(NSDictionary *app){launched=app;restoredForDock=Overview(scene)==nil;for(NSDictionary *task in Tasks)restoredForDock=restoredForDock&&((UIViewController *)task[@"window"]).parentViewController==Host.rootViewController;};
        BOOL unified=[switcher respondsToSelector:@selector(presentInScene:apps:launchHandler:error:)];
        NSUInteger readsBefore=InventoryReads;
        if(unified)[switcher presentInScene:scene apps:apps launchHandler:launch error:NULL];else [switcher presentInScene:scene error:NULL];Pump(.4);
        UIView *deck=Find(Overview(scene),@"orbit.task.pages");
        UIView *older=Find(deck,@"orbit.task.card.V1"),*focused=Find(deck,@"orbit.task.card.V2"),*newer=Find(deck,@"orbit.task.card.V3");
        CGFloat leftGap=CGRectGetMidX(focused.frame)-CGRectGetMidX(older.frame);
        CGFloat rightGap=CGRectGetMidX(newer.frame)-CGRectGetMidX(focused.frame);
        Check(@"middle-card-opens-toward-successor-with-older-cards-tucked-in",leftGap>0&&rightGap>leftGap*2&&
            CGRectGetHeight(older.frame)<CGRectGetHeight(focused.frame)&&CGRectGetHeight(newer.frame)>CGRectGetHeight(focused.frame));
        UIScrollView *dock=(id)Find(Overview(scene),@"orbit.dock.scroll");
        Check(@"dock-keeps-full-inventory-including-not-running",dock.subviews.count==apps.count);
        BOOL ordered=YES;for(NSUInteger i=0;i<apps.count;i++)ordered=ordered&&[Find(dock,[NSString stringWithFormat:@"orbit.dock.app.%lu",(unsigned long)i]).accessibilityLabel isEqual:apps[i][@"title"]];
        Check(@"dock-preserves-original-inventory-order",ordered&&dock!=nil);
        Check(@"dock-horizontal-overflow-is-scrollable",dock.scrollEnabled&&dock.contentSize.width>dock.bounds.size.width&&dock.showsHorizontalScrollIndicator==NO);
        CGPoint dockSnap=CGPointMake(123,0);[dock.delegate scrollViewWillEndDragging:dock withVelocity:CGPointMake(1,0) targetContentOffset:&dockSnap];Check(@"dock-scroll-never-snaps-deck",dock&&fabs(dockSnap.x-123)<.1);
        Pump(1.05);Check(@"supplied-inventory-avoids-running-task-rescan",unified&&InventoryReads==readsBefore&&[LastInventory isEqual:apps]);
        UIViewController *safeRoot=Overview(scene).rootViewController;safeRoot.additionalSafeAreaInsets=UIEdgeInsetsMake(0,0,20,0);[safeRoot.view setNeedsLayout];[safeRoot.view layoutIfNeeded];UIView *safeDock=Find(safeRoot.view,@"orbit.dock");
        Check(@"dock-adapts-to-safe-inset-change-without-bounds-change",safeDock&&CGRectGetMaxY(safeDock.frame)<=safeRoot.view.bounds.size.height-safeRoot.view.safeAreaInsets.bottom);safeRoot.additionalSafeAreaInsets=UIEdgeInsetsZero;[safeRoot.view setNeedsLayout];[safeRoot.view layoutIfNeeded];
        UIButton *dockButton=(id)Find(dock,@"orbit.dock.app.3");[dockButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        BOOL launchWaitedForExpansion=launched==nil&&Overview(scene)!=nil;
        Check(@"dock-launch-expands-before-callback",launchWaitedForExpansion);
        UIView *launchSurface=Find(Overview(scene),@"orbit.dock.launch");
        Pump(.10);CGFloat animatedWidth=launchSurface.layer.presentationLayer.bounds.size.width;
        Check(@"cold-launch-expands-from-dock-icon",animatedWidth>dockButton.bounds.size.width&&animatedWidth<Overview(scene).bounds.size.width);
        Pump(.5);
        Check(@"dock-control-restores-before-original-launch-callback",launched==apps[3]&&restoredForDock);
        if(unified)[switcher presentInScene:scene apps:apps launchHandler:launch error:NULL];
        EmbeddedActions=0;Activated=nil;Tap(scene,@"V2");Check(@"card-tap-only-resumes-without-embedded-action",[Activated[@"token"] isEqual:@"V2"]&&EmbeddedActions==0);
        if(unified)[switcher presentInScene:scene apps:apps launchHandler:launch error:NULL];
        RejectClose=YES;Pan(scene,@"V2",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(0,-100));Pan(scene,@"V2",UIGestureRecognizerStateEnded,CGPointMake(0,-400),CGPointMake(0,-1000));Pump(.4);
        Check(@"failed-close-keeps-original-dock-inventory",Find(Overview(scene),@"orbit.dock.app.9")!=nil);RejectClose=NO;[switcher dismiss];
        if(unified)[switcher presentInScene:scene apps:apps launchHandler:launch error:NULL];NSDictionary *lastTask=Tasks.lastObject;
        Pan(scene,@"V3",UIGestureRecognizerStateBegan,CGPointZero,CGPointMake(0,-100));Pan(scene,@"V3",UIGestureRecognizerStateEnded,CGPointMake(0,-400),CGPointMake(0,-1000));Pump(.4);
        Check(@"successful-close-keeps-full-dock-and-callback",Tasks.count==2&&Find(Overview(scene),@"orbit.dock.app.9")!=nil);
        launched=nil;[(UIButton *)Find(Overview(scene),@"orbit.dock.app.3") sendActionsForControlEvents:UIControlEventTouchUpInside];Pump(.5);Check(@"reopened-dock-retains-original-launch-handler",launched==apps[3]&&restoredForDock);[switcher dismiss];
        [Host.rootViewController.view addSubview:((UIViewController *)lastTask[@"window"]).view];[Tasks addObject:lastTask];
        NSArray *savedTasks=[Tasks copy];[Tasks removeAllObjects];
        if(unified)[switcher presentInScene:scene apps:apps launchHandler:launch error:NULL];
        Check(@"no-running-tasks-keeps-dock-without-management-message",Overview(scene)!=nil&&Overview(scene).rootViewController.view.window==Overview(scene));
        launched=nil;[(UIButton *)Find(Overview(scene),@"orbit.dock.app.4") sendActionsForControlEvents:UIControlEventTouchUpInside];Pump(.5);Check(@"empty-task-dock-still-launches-app",launched==apps[4]);[switcher dismiss];[Tasks addObjectsFromArray:savedTasks];
        if(unified)[switcher presentInScene:scene apps:apps launchHandler:launch error:NULL];else [switcher presentInScene:scene error:NULL];Pump(.4);Screenshot(Overview(scene),[directory stringByAppendingPathComponent:@"portrait.png"]);
        UIScrollView *visualPages=(id)Find(Overview(scene),@"orbit.task.pages");UIView *visualFirst=Find(Overview(scene),@"orbit.task.card.V1"),*visualSecond=Find(Overview(scene),@"orbit.task.card.V2");CGFloat visualStride=CGRectGetMinX(visualSecond.frame)-CGRectGetMinX(visualFirst.frame);visualPages.contentOffset=CGPointZero;Screenshot(Overview(scene),[directory stringByAppendingPathComponent:@"reading-focused.png"]);visualPages.contentOffset=CGPointMake(visualStride*2,0);Screenshot(Overview(scene),[directory stringByAppendingPathComponent:@"notes-focused.png"]);visualPages.contentOffset=CGPointMake(visualStride,0);
        UIViewController *root=Overview(scene).rootViewController;root.view.frame=CGRectMake(0,root.view.safeAreaInsets.top,667,375);[root.view setNeedsLayout];[root.view layoutIfNeeded];
        UIView *landscapeCard=Find(root.view,@"orbit.task.card.V2");CGRect visible=[landscapeCard.superview convertRect:landscapeCard.frame toView:root.view];Check(@"landscape-live-card-fits-safe-area",visible.origin.y>=root.view.safeAreaInsets.top&&CGRectGetMaxY(visible)<=root.view.bounds.size.height-root.view.safeAreaInsets.bottom&&ChromeCount(root.view)==0);
        UIView *landscapeDock=Find(root.view,@"orbit.dock");Check(@"landscape-dock-below-cards-and-safe-bottom",landscapeDock&&CGRectGetMaxY(visible)<CGRectGetMinY(landscapeDock.frame)&&CGRectGetMaxY(landscapeDock.frame)<=root.view.bounds.size.height-root.view.safeAreaInsets.bottom);
        Screenshot(root.view,[directory stringByAppendingPathComponent:@"landscape.png"]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [root viewWillTransitionToSize:CGSizeMake(375,667) withTransitionCoordinator:(id)nil];
#pragma clang diagnostic pop
        Check(@"rotation-restores-live-content",Overview(scene)==nil&&![switcher isPresentingWindow:Tasks[0][@"window"]]);
        [switcher dismiss];

        NSArray *moreTasks=@[Task(@"G4",UIColor.systemPinkColor),Task(@"G5",UIColor.systemPurpleColor)];
        [Tasks addObjectsFromArray:moreTasks];
        NSArray *extendedApps=[apps arrayByAddingObjectsFromArray:moreTasks];
        [switcher presentInScene:scene apps:extendedApps launchHandler:launch error:NULL];Pump(.45);
        UIScrollView *flickDeck=(id)Find(Overview(scene),@"orbit.task.pages");
        id<UIScrollViewDelegate> deckDelegate=flickDeck.delegate;
        CGFloat cardStride=(flickDeck.contentSize.width-flickDeck.bounds.size.width)/4;
        for(NSNumber *direction in @[@1,@-1]) {
            CGFloat sign=direction.doubleValue,start=sign>0?1:3;
            flickDeck.contentOffset=CGPointMake(start*cardStride,0);
            [deckDelegate scrollViewWillBeginDragging:flickDeck];
            flickDeck.contentOffset=CGPointMake((start+sign*.95)*cardStride,0);
            CGPoint projected=CGPointMake(sign>0?4*cardStride:0,0);
            [deckDelegate scrollViewWillEndDragging:flickDeck withVelocity:CGPointMake(sign*5,0) targetContentOffset:&projected];
            Check(sign>0?@"quick-forward-flick-stops-at-neighbor":@"quick-backward-flick-stops-at-neighbor",
                  cardStride>0&&fabs(projected.x-(start+sign)*cardStride)<1);
            [deckDelegate scrollViewDidEndDragging:flickDeck willDecelerate:YES];
            flickDeck.contentOffset=projected;
            [deckDelegate scrollViewDidEndDecelerating:flickDeck];

            CGFloat edge=sign>0?4:0;
            flickDeck.contentOffset=CGPointMake(edge*cardStride,0);
            [deckDelegate scrollViewWillBeginDragging:flickDeck];
            projected=CGPointMake((edge+sign)*cardStride,0);
            [deckDelegate scrollViewWillEndDragging:flickDeck withVelocity:CGPointMake(sign*5,0) targetContentOffset:&projected];
            Check(sign>0?@"right-edge-flick-stays-at-boundary":@"left-edge-flick-stays-at-boundary",
                  fabs(projected.x-edge*cardStride)<1);
            [deckDelegate scrollViewDidEndDragging:flickDeck willDecelerate:NO];
        }
        flickDeck.contentOffset=CGPointZero;
        [deckDelegate scrollViewWillBeginDragging:flickDeck];
        CGPoint longDrag=CGPointMake(cardStride*2.82,0);
        flickDeck.contentOffset=longDrag;
        CGPoint longTarget=CGPointMake(cardStride*4,0);
        [deckDelegate scrollViewWillEndDragging:flickDeck withVelocity:CGPointMake(5,0) targetContentOffset:&longTarget];
        Check(@"long-drag-can-cross-multiple-cards-before-release",fabs(longTarget.x-cardStride*3)<1);
        [deckDelegate scrollViewDidEndDragging:flickDeck willDecelerate:YES];
        [deckDelegate scrollViewDidEndDecelerating:flickDeck];
        Pump(.40);
        Check(@"deceleration-end-does-not-start-a-second-scroll",fabs(flickDeck.contentOffset.x-longDrag.x)<1);
        flickDeck.contentOffset=CGPointMake(cardStride,0);
        [deckDelegate scrollViewWillBeginDragging:flickDeck];
        flickDeck.contentOffset=CGPointMake(cardStride*1.4,0);
        CGPoint slowTarget=CGPointMake(cardStride*1.4,0);
        [deckDelegate scrollViewWillEndDragging:flickDeck withVelocity:CGPointZero targetContentOffset:&slowTarget];
        [deckDelegate scrollViewDidEndDragging:flickDeck willDecelerate:NO];
        Pump(.40);
        Check(@"drag-without-deceleration-aligns-to-nearest-card",fabs(slowTarget.x-cardStride)<1&&fabs(flickDeck.contentOffset.x-cardStride)<1);
        [switcher dismiss];

        GridPresentation=YES;
        [switcher presentInScene:scene apps:extendedApps launchHandler:launch error:NULL];Pump(.45);
        UIWindow *gridWindow=Overview(scene);
        UIView *gridA=Find(gridWindow,@"orbit.task.card.V1"),*gridB=Find(gridWindow,@"orbit.task.card.V2"),*gridC=Find(gridWindow,@"orbit.task.card.V3");
        Check(@"ipad-presentation-on-phone-shows-two-column-live-grid",gridA&&gridB&&gridC&&
            fabs(CGRectGetMidY(gridA.frame)-CGRectGetMidY(gridB.frame))<1&&
            CGRectGetMidY(gridC.frame)>CGRectGetMaxY(gridA.frame)&&
            CGRectGetMaxX(gridA.frame)<CGRectGetMinX(gridB.frame));
        UIScrollView *gridPages=(id)Find(gridWindow,@"orbit.task.pages");
        CGPoint gridTarget=CGPointMake(0,0);
        [gridPages.delegate scrollViewWillEndDragging:gridPages withVelocity:CGPointMake(1,0) targetContentOffset:&gridTarget];
        Check(@"grid-swipes-by-a-full-page-of-tasks",fabs(gridTarget.x-gridPages.bounds.size.width)<1&&gridTarget.x>0);
        [switcher dismiss];GridPresentation=NO;
        [Tasks removeObjectsInArray:moreTasks];
        for(NSDictionary *task in moreTasks) {
            UIViewController *controller=task[@"window"];
            [controller.view removeFromSuperview];
            [controller removeFromParentViewController];
        }

        SEL appearanceAPI=@selector(presentInScene:apps:dockIconSize:iconProvider:launchHandler:error:);
        __block BOOL markedCurrent=NO;
        if([switcher respondsToSelector:appearanceAPI]) {
            NSMutableArray *appearanceApps=[apps mutableCopy];
            NSMutableDictionary *jitApp=[appearanceApps[0] mutableCopy];
            jitApp[@"blockReason"]=@"needs-jit";jitApp[@"status"]=@"需要 JIT";
            appearanceApps[0]=jitApp;
            NSMutableDictionary *lockedApp=[appearanceApps[2] mutableCopy];
            lockedApp[@"locked"]=@YES;lockedApp[@"blockReason"]=@"locked";lockedApp[@"status"]=@"已锁定";
            appearanceApps[2]=lockedApp;
            visualStatusApps=appearanceApps;
            visualStatusIcons=^UIView *(NSDictionary *app,CGFloat size,BOOL current) {
                UIView *view=[[UIView alloc] initWithFrame:CGRectMake(0,0,size,size)];
                view.accessibilityIdentifier=[@"fixture.dock.art." stringByAppendingString:app[@"uuid"]];
                view.accessibilityValue=current?@"当前":app[@"status"];
                UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:[app[@"folder"] stringByAppendingPathComponent:@"LCAppIconLight.png"]]];
                icon.frame=view.bounds;icon.layer.cornerRadius=8;icon.clipsToBounds=YES;[view addSubview:icon];
                NSString *reason=app[@"blockReason"];
                if(reason) {
                    BOOL locked=[reason isEqual:@"locked"];
                    UIImageView *badge=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:locked?@"lock.circle.fill":@"bolt.circle.fill"]];
                    badge.tintColor=locked?UIColor.systemYellowColor:UIColor.systemPurpleColor;badge.frame=CGRectMake(size-13,size-13,13,13);
                    badge.accessibilityIdentifier=[@"fixture.dock.badge." stringByAppendingString:reason];[view addSubview:badge];
                }
                if([app[@"uuid"] isEqual:@"V2"])markedCurrent=current&&size==36;
                return view;
            };
            [switcher presentInScene:scene apps:visualStatusApps dockIconSize:36 iconProvider:visualStatusIcons launchHandler:launch error:NULL];
        }
        UIView *custom=Find(Overview(scene),@"fixture.dock.art.V2");
        UIView *customButton=Find(Overview(scene),@"orbit.dock.app.1");
        Check(@"dock-reuses-drawer-art-size-and-status",markedCurrent&&custom.bounds.size.width==36&&[customButton.accessibilityValue isEqual:@"当前"]&&!custom.userInteractionEnabled);
        UIView *jitButton=Find(Overview(scene),@"orbit.dock.app.0");
        UIView *jitArtwork=Find(jitButton,@"fixture.dock.art.V1");
        Check(@"dock-jit-keeps-badge-and-voiceover-without-caption",[jitButton.accessibilityValue isEqual:@"需要 JIT"]&&
            Find(jitButton,@"fixture.dock.badge.needs-jit")&&!Find(jitButton,@"orbit.dock.status")&&fabs(jitArtwork.center.y-custom.center.y)<.5);
        UIView *lockedButton=Find(Overview(scene),@"orbit.dock.app.2");
        Check(@"dock-lock-keeps-badge-and-voiceover-without-caption",[lockedButton.accessibilityValue isEqual:@"已锁定"]&&
            Find(lockedButton,@"fixture.dock.badge.locked")&&!Find(lockedButton,@"orbit.dock.status"));
        [switcher dismiss];

        NSMutableDictionary *cold=[Task(@"COLD",UIColor.systemPurpleColor) mutableCopy];
        FixtureTaskController *coldWindow=cold[@"window"];cold[@"launchable"]=@YES;
        coldWindow.view.hidden=YES;
        __block NSUUID *token=nil;
        void(^begin)(NSDictionary *)=^(NSDictionary *app){
            if([switcher respondsToSelector:@selector(dockLaunchTokenForApp:)]) {
                token=[switcher dockLaunchTokenForApp:app];[switcher beginDockLaunch:token];
            }
        };
        [switcher presentInScene:scene apps:@[cold] launchHandler:begin error:NULL];Pump(.4);
        [(UIButton *)Find(Overview(scene),@"orbit.dock.app.0") sendActionsForControlEvents:UIControlEventTouchUpInside];
        Pump(.55);
        Check(@"cold-launch-cover-survives-switcher-dismissal",token&&LaunchCover(scene)!=nil&&Overview(scene)==nil);
        DockActiveWindow=Tasks.firstObject[@"window"];Pump(.22);
        Check(@"unrelated-active-task-cannot-clear-cold-launch-cover",LaunchCover(scene)!=nil);
        [Tasks addObject:cold];DockActiveWindow=coldWindow;coldWindow.view.hidden=NO;Pump(.2);
        Check(@"running-target-without-mounted-content-keeps-launch-cover",LaunchCover(scene)!=nil);
        UIView *content=[[UIView alloc] initWithFrame:coldWindow.view.bounds];
        coldWindow.appSceneVC.contentView=content;[coldWindow.view addSubview:content];Pump(.45);
        Check(@"mounted-target-reveals-app-and-clears-cover",!LaunchCover(scene));
        [Tasks removeObjectIdenticalTo:cold];DockActiveWindow=nil;
        [switcher presentInScene:scene apps:@[cold] launchHandler:begin error:NULL];Pump(.4);
        [(UIButton *)Find(Overview(scene),@"orbit.dock.app.0") sendActionsForControlEvents:UIControlEventTouchUpInside];Pump(.55);
        BOOL coverBeforeCancel=LaunchCover(scene)!=nil;
        if(token)[switcher cancelDockLaunch:token];
        Check(@"failed-or-cancelled-launch-clears-cover",coverBeforeCancel&&!LaunchCover(scene));
        [coldWindow.view removeFromSuperview];[coldWindow removeFromParentViewController];
    }
    GridPresentation=[NSProcessInfo.processInfo.environment[@"ORBIT_GRID_SCREENSHOT"] boolValue];
    if(!GridPresentation&&visualStatusIcons)
        [switcher presentInScene:scene apps:visualStatusApps dockIconSize:36 iconProvider:visualStatusIcons launchHandler:nil error:NULL];
    else if([switcher respondsToSelector:@selector(presentInScene:apps:launchHandler:error:)])
        [switcher presentInScene:scene apps:VisualApps?:Tasks launchHandler:^(NSDictionary *app){} error:NULL];
    Pump(.4);
    WriteReport(directory);
}
@interface TaskSwitcherSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation TaskSwitcherSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    Host=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window=Host;Host.rootViewController=[UIViewController new];Host.rootViewController.view.backgroundColor=[UIColor colorWithRed:.22 green:.18 blue:.15 alpha:1];
    for(NSUInteger i=0;i<12;i++) { UIView *tile=[[UIView alloc] initWithFrame:CGRectMake(32+(i%4)*90,140+(i/4)*150,62,62)];tile.backgroundColor=@[UIColor.systemBlueColor,UIColor.systemOrangeColor,UIColor.systemGreenColor,UIColor.systemPurpleColor][i%4];tile.layer.cornerRadius=14;[Host.rootViewController.view addSubview:tile]; }
    [Host makeKeyAndVisible];Bead=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];Bead.windowLevel=UIWindowLevelNormal+75;Bead.rootViewController=[UIViewController new];Bead.rootViewController.view.backgroundColor=UIColor.clearColor;Bead.hidden=NO;
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer){Run((UIWindowScene *)scene);}];
}
@end
@interface TaskSwitcherDelegate : UIResponder <UIApplicationDelegate> @end
@implementation TaskSwitcherDelegate @end
static void FixtureException(NSException *exception) {
    if(!Results)Results=[NSMutableArray array];
    [Results addObject:@{@"name":@"uncaught-uikit-exception",@"passed":@NO,@"details":exception.reason?:exception.name}];
    NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TaskSwitcherEvidence"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *report=@{@"count":@(Results.count),@"failures":@([[Results filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *check,NSDictionary *bindings){return ![check[@"passed"] boolValue];}]] count]),@"results":Results};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[directory stringByAppendingPathComponent:@"result.json"] atomically:YES];
}
int main(int argc,char **argv) { @autoreleasepool { NSSetUncaughtExceptionHandler(FixtureException);return UIApplicationMain(argc,argv,nil,NSStringFromClass(TaskSwitcherDelegate.class)); } }
