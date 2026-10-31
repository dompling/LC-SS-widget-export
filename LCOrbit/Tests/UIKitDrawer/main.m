#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "LCOrbit/Core/LCOrbitCore.h"
#import "LCOrbit/Core/LCOrbitStorage.h"
#import "LCOrbit/Core/LCOrbitGuestService.h"
#import "LCOrbit/Core/LCOrbitMultitask.h"
#import "LCOrbit/Core/LCOrbitHost.h"
#import "LCOrbit/Core/LCOrbitGitHub.h"
#import "LCOrbit/Core/LCOrbitPluginUpdater.h"
#import "LCOrbit/Core/LCOrbitTweakCenter.h"
#import "LCOrbit/Core/LCOrbitTweakCenterViews.h"
#import "LCOrbit/Core/LCOrbitSharedTweaksViewController.h"
#import "LCOrbit/Core/LCOrbitTweakSync.h"

// Only host/task/presentation boundaries are fixtures; layout and menu actions
// below execute the real LCFloatingMenu and Core linked into this simulator app.
@interface FMManager : NSObject
+ (instancetype)shared;
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *overlayView;
@property(nonatomic,strong) LCOrbitContext *orbitContext;
@property(nonatomic,strong) UIButton *orb;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIView *orbPreviewHost;
@property(nonatomic,strong) UIView *dimensionsPreview;
@property(nonatomic,strong) UIWindow *settingsWindow;
@property(nonatomic,strong) UINavigationController *settingsNavigation;
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
- (void)refreshSystemAppearance;
- (void)refreshAppsContent;
- (void)populateSettingsCategory:(NSString *)category stack:(UIStackView *)stack;
- (void)closeTaskFromButton:(UIControl *)sender;
- (void)closeMultitaskGuest;
- (void)automaticPiPChanged:(UISwitch *)control;
- (void)sortDrag:(UILongPressGestureRecognizer *)gesture;
- (void)pan:(UIPanGestureRecognizer *)gesture;
- (void)sliderChanged:(UISlider *)slider;
- (void)sliderFinished:(UISlider *)slider;
- (void)refreshOrbPreview;
- (void)themeColorChanged:(UIColorWell *)well;
- (void)resetMenuDimensions;
- (void)resetOrbDimensions;
@end
@interface FMSettingsRootController : UIViewController
- (void)tryAutomaticUpdatePrompt;
- (void)checkForUpdates;
- (void)rebuild;
@end
@interface FMSettingsSectionController : UIViewController
- (instancetype)initWithSection:(NSString *)key;
- (void)editGitHubCredentials;
- (void)verifyGitHubConnection;
- (void)clearGitHubCredentials;
- (void)rebuild;
@end
@interface NSUserDefaults (DrawerFixture) @end
@implementation NSUserDefaults (DrawerFixture)
+ (BOOL)isLiveProcess { return YES; } // Suppress injection bootstrap only.
@end
@interface LCOrbitTweakSync (PerPluginFixtureAPI)
+ (BOOL)automaticSyncEnabledForPlugin:(NSString *)name;
+ (BOOL)setAutomaticSyncEnabled:(BOOL)enabled forPlugin:(NSString *)name error:(NSError **)error;
@end
static NSArray *FixtureApps;
static BOOL FixtureCurrent, FixtureRunning=YES, FixtureHost=YES;
static CGFloat FixtureWidth=667;
static NSUInteger CloseCount, PositionWrites;
static NSMutableDictionary *AutoPiPStates;
static NSDictionary *LastAutoPiPTarget;
static BOOL RejectAutoPiP;
static UIAlertController *CapturedAlert;
static NSUInteger UpdatePromptPresentations,DownloadResumes,UpdateInstalls;
static BOOL RejectUpdateSkipSave;
static NSURLRequest *DownloadRequest;
static void (^DownloadCompletion)(NSData *,NSURLResponse *,NSError *);
static NSString *InstalledUpdateDigest;
static NSMutableDictionary *PluginAutoStates;
static NSString *LastPluginAutoName;
static NSUInteger PluginAutoSyncCalls,PluginAutoWrites;
static BOOL RejectPluginAutoSave;
@interface LCOrbitTweakSync (PluginManagementFixture) @end
@implementation LCOrbitTweakSync (PluginManagementFixture)
+ (NSArray *)fixturePluginInventory {
    return @[@{@"name":@"Local-A.dylib",@"private":@YES,@"shared":@YES,@"loaded":@YES,@"matches":@YES,@"canShare":@YES,@"canUnshare":@YES},
        @{@"name":@"Shared-Only.dylib",@"private":@NO,@"shared":@YES,@"loaded":@NO,@"canShare":@NO,@"canUnshare":@YES}];
}
+ (BOOL)fixtureAutomaticSyncEnabledForPlugin:(NSString *)name { return [PluginAutoStates[name] boolValue]; }
+ (BOOL)fixtureSetAutomaticSyncEnabled:(BOOL)enabled forPlugin:(NSString *)name error:(NSError **)error {
    PluginAutoWrites++;
    if(RejectPluginAutoSave) {
        if(error) *error=[NSError errorWithDomain:@"DrawerFixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Fixture plugin write rejected"}];
        return NO;
    }
    PluginAutoStates[name]=@(enabled);LastPluginAutoName=[name copy];return YES;
}
+ (NSString *)fixtureSyncAutomaticallyIfNeeded {
    @synchronized(self) { PluginAutoSyncCalls++; }
    return @"Fixture plugin synced";
}
@end
@interface LCOrbitTweakCenter (PluginManagementFixture) @end
@implementation LCOrbitTweakCenter (PluginManagementFixture)
+ (NSDictionary *)fixturePluginInfo:(NSString *)name shared:(BOOL)shared {
    BOOL exists=shared || [name isEqualToString:@"Local-A.dylib"];
    return @{@"exists":@(exists),@"enabled":@YES,@"size":@1234,@"date":NSDate.distantPast,@"path":@"/fixture/plugin.dylib"};
}
@end
static NSString *GitHubAccount;
static BOOL GitHubHasToken;
static NSUInteger GitHubCredentialReads,GitHubRequests,GitHubSaves,GitHubClears;
static BOOL GitHubSavedEmptyToken;
static NSString *GitHubRequestedURL;
static NSMutableArray *GitHubCompletions;
@interface FixtureDownloadTask : NSObject
- (void)resume;
@end
@implementation FixtureDownloadTask
- (void)resume { DownloadResumes++; }
@end
@interface FixtureDownloadSession : NSObject
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion;
@end
@implementation FixtureDownloadSession
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    DownloadRequest=request;DownloadCompletion=[completion copy];return [FixtureDownloadTask new];
}
@end
@interface NSURLSession (DrawerUpdateFixture) @end
@implementation NSURLSession (DrawerUpdateFixture)
+ (NSURLSession *)fixtureSharedSession { return (id)[FixtureDownloadSession new]; }
@end
@interface LCOrbitPluginUpdater (DrawerUpdateFixture) @end
@implementation LCOrbitPluginUpdater (DrawerUpdateFixture)
+ (BOOL)fixtureInstallDownloadedPlugin:(NSData *)binary expectedSHA256:(NSString *)digest error:(NSError **)error {
    UpdateInstalls++;InstalledUpdateDigest=digest;return YES;
}
@end
@interface LCOrbitStorage (DrawerUpdateFixture) @end
@implementation LCOrbitStorage (DrawerUpdateFixture)
+ (NSError *)fixtureLastError {
    if(RejectUpdateSkipSave) return [NSError errorWithDomain:@"DrawerFixture" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"Fixture skip write failed"}];
    return [self fixtureLastError];
}
@end
@interface LCOrbitGitHub (DrawerFixture) @end
@implementation LCOrbitGitHub (DrawerFixture)
+ (NSString *)fixtureAccountWithError:(NSError **)error { GitHubCredentialReads++;return GitHubAccount; }
+ (BOOL)fixtureHasTokenWithError:(NSError **)error { GitHubCredentialReads++;return GitHubHasToken; }
+ (BOOL)fixtureSaveAccount:(NSString *)account token:(NSString *)token error:(NSError **)error {
    GitHubSaves++;GitHubAccount=[account copy];GitHubSavedEmptyToken=token.length==0;
    if(token.length) GitHubHasToken=YES;return YES;
}
+ (BOOL)fixtureClearCredentialsWithError:(NSError **)error {
    GitHubClears++;GitHubAccount=nil;GitHubHasToken=NO;return YES;
}
+ (NSMutableURLRequest *)fixtureRequestForURL:(NSURL *)url timeout:(NSTimeInterval)timeout error:(NSError **)error {
    GitHubRequestedURL=url.absoluteString;return [NSMutableURLRequest requestWithURL:url];
}
+ (void)fixturePerformRequest:(NSURLRequest *)request completion:(void (^)(NSData *,NSHTTPURLResponse *,NSError *))completion {
    GitHubRequests++;[GitHubCompletions addObject:[completion copy]];
}
@end
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
    if(RejectUpdateSkipSave && [key isEqualToString:@"LCFloatingMenu.skippedUpdateVersion"]) return;
    [self fixtureSetObject:object forKey:key];
}
@end
@interface UIViewController (DrawerFixture) @end
@implementation UIViewController (DrawerFixture)
- (void)fixturePresent:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if([controller isKindOfClass:UIAlertController.class]) {
        CapturedAlert=(UIAlertController *)controller;
        for(UIAlertAction *action in CapturedAlert.actions) if([action.title isEqualToString:@"下载更新"]) UpdatePromptPresentations++;
        if(completion) completion();return;
    }
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
static void InvokeAlertAction(UIAlertController *alert,NSString *title) {
    for(UIAlertAction *action in alert.actions) if([action.title isEqualToString:title]) {
        void (^handler)(UIAlertAction *)=[action valueForKey:@"handler"];
        if(handler) handler(action);return;
    }
}
static void CompleteGitHub(NSString *login,NSInteger status) {
    if(!GitHubCompletions.count) return;
    void (^completion)(NSData *,NSHTTPURLResponse *,NSError *)=GitHubCompletions.firstObject;
    [GitHubCompletions removeObjectAtIndex:0];
    NSData *data=[NSJSONSerialization dataWithJSONObject:login?@{@"login":login}:@{} options:0 error:nil];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://api.github.com/user"]
        statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    completion(data,response,nil);
}
static NSDictionary *UpdateRelease(NSString *version) {
    return @{@"version":version,@"commit":@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        @"downloadURL":@"https://github.com/dompling/LC-SS-widget-export/releases/download/fm-latest/LCFloatingMenu.dylib",
        @"sha256":@"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        @"notes":@"更新说明：改善设置中的更新提醒。"};
}
static void AttemptAutomaticUpdate(FMSettingsRootController *root) {
    if([root respondsToSelector:@selector(tryAutomaticUpdatePrompt)]) [root tryAutomaticUpdatePrompt];
}
static void NotifyUpdate(NSDictionary *release) {
    [NSUserDefaults.standardUserDefaults setObject:release forKey:@"LCFloatingMenu.updateIndicator.release"];
    [NSNotificationCenter.defaultCenter postNotificationName:@"LCFloatingMenuUpdateReleaseAvailable" object:nil];
}
static void CompleteUpdateJSON(NSDictionary *json) {
    if(!GitHubCompletions.count) return;
    void (^completion)(NSData *,NSHTTPURLResponse *,NSError *)=GitHubCompletions.lastObject;
    [GitHubCompletions removeLastObject];
    completion([NSJSONSerialization dataWithJSONObject:json options:0 error:nil],
        [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://api.github.com/repos/dompling/LC-SS-widget-export/releases/tags/fm-latest"]
        statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}],nil);
}
static void CompleteUpdateRequest(NSString *version) {
    NSDictionary *release=UpdateRelease(version);
    NSString *body=[NSString stringWithFormat:@"FM_VERSION=%@\nFM_COMMIT=%@\n\n%@",version,release[@"commit"],release[@"notes"]];
    NSDictionary *json=@{@"body":body,@"assets":@[@{@"name":@"LCFloatingMenu.dylib",@"digest":release[@"sha256"],
        @"browser_download_url":release[@"downloadURL"]}]};
    CompleteUpdateJSON(json);
}
static void SetUpdateRoot(UINavigationController *nav,UIViewController *root,UIWindow *window) {
    [nav setViewControllers:@[root] animated:NO];
    [root loadViewIfNeeded];[window layoutIfNeeded];[nav.view layoutIfNeeded];[root.view layoutIfNeeded];
}
static void RunPluginManagementTests(void) {
    PluginAutoStates=[NSMutableDictionary dictionary];PluginAutoSyncCalls=0;PluginAutoWrites=0;
    UIColor *background=UIColor.systemBackgroundColor,*surface=UIColor.secondarySystemGroupedBackgroundColor;
    LCOrbitSharedTweaksViewController *manager=[[LCOrbitSharedTweaksViewController alloc]
        initWithBackground:background surface:surface text:UIColor.labelColor secondary:UIColor.secondaryLabelColor accent:UIColor.systemBlueColor];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:manager];
    UIWindow *window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.rootViewController=nav;window.hidden=NO;[window layoutIfNeeded];[manager loadViewIfNeeded];
    UITableView *inventory=[manager valueForKey:@"table"];
    id<UITableViewDataSource> listData=inventory.dataSource;
    UITableViewCell *assignment=[listData tableView:inventory cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    Check(@"plugin-manager-global-auto-switch-removed",[listData tableView:inventory numberOfRowsInSection:0]==1 &&
          ![assignment.accessoryView isKindOfClass:UISwitch.class] && [assignment.textLabel.text isEqual:@"按 App 分配插件"],nil);
    UIViewController *details=[LCOrbitTweakCenterViews pluginDetailsForName:@"Local-A.dylib"
        background:background surface:surface text:UIColor.labelColor secondary:UIColor.secondaryLabelColor accent:UIColor.systemBlueColor];
    SetUpdateRoot(nav,details,window);
    UITableView *table=[details valueForKey:@"table"];
    id<UITableViewDataSource> data=table.dataSource;
    BOOL backupsRemoved=details.navigationItem.rightBarButtonItems.count==0;
    for(NSInteger section=0;section<[data numberOfSectionsInTableView:table];section++) {
        NSString *heading=[data tableView:table titleForHeaderInSection:section];
        backupsRemoved &= ![heading containsString:@"备份"];
        for(NSInteger row=0;row<[data tableView:table numberOfRowsInSection:section];row++) {
            UITableViewCell *cell=[data tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
            backupsRemoved &= ![cell.textLabel.text containsString:@"备份"] && ![cell.textLabel.text containsString:@"恢复"];
        }
    }
    Check(@"plugin-detail-backup-restore-clear-ui-removed",backupsRemoved,nil);
    UITableViewCell *autoCell=[data tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    UISwitch *toggle=[autoCell.accessoryView isKindOfClass:UISwitch.class]?(UISwitch *)autoCell.accessoryView:nil;
    Check(@"plugin-detail-local-auto-sharing-switch",toggle && toggle.enabled && !toggle.on &&
          [autoCell.textLabel.text containsString:@"自动共享"],nil);
    UIViewController *shared=[LCOrbitTweakCenterViews pluginDetailsForName:@"Shared-Only.dylib"
        background:background surface:surface text:UIColor.labelColor secondary:UIColor.secondaryLabelColor accent:UIColor.systemBlueColor];
    [shared loadViewIfNeeded];UITableView *sharedTable=[shared valueForKey:@"table"];
    UITableViewCell *sharedAuto=[sharedTable.dataSource tableView:sharedTable cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    UISwitch *sharedToggle=[sharedAuto.accessoryView isKindOfClass:UISwitch.class]?(UISwitch *)sharedAuto.accessoryView:nil;
    Check(@"plugin-detail-shared-only-cannot-enable-auto-sharing",sharedToggle && !sharedToggle.enabled && !sharedToggle.on,nil);
    SEL changed=NSSelectorFromString(@"automaticSyncChanged:");
    if([details respondsToSelector:changed]) {
        RejectPluginAutoSave=YES;toggle.on=YES;CapturedAlert=nil;
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        Check(@"plugin-detail-auto-save-failure-rolls-back",!toggle.on && [CapturedAlert.title isEqual:@"配置未保存"],nil);
        RejectPluginAutoSave=NO;CapturedAlert=nil;toggle.on=YES;
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        NSUInteger writes=PluginAutoWrites;
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        Check(@"plugin-detail-auto-toggle-targets-one-plugin-and-debounces",[LastPluginAutoName isEqual:@"Local-A.dylib"] &&
              [PluginAutoStates[@"Local-A.dylib"] boolValue] && ![PluginAutoStates[@"Shared-Only.dylib"] boolValue] && PluginAutoWrites==writes,nil);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            Check(@"plugin-detail-enabling-immediately-syncs",PluginAutoSyncCalls==1,nil);
            UITableViewCell *refreshed=[data tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
            UISwitch *active=(UISwitch *)refreshed.accessoryView;
            active.on=NO;CapturedAlert=nil;[active sendActionsForControlEvents:UIControlEventValueChanged];
            Check(@"plugin-detail-disabling-keeps-shared-copy-without-sync",![PluginAutoStates[@"Local-A.dylib"] boolValue] && PluginAutoSyncCalls==1 &&
                  [[LCOrbitTweakCenter pluginInfo:@"Local-A.dylib" shared:YES][@"exists"] boolValue],nil);
            FixtureHost=NO;NSUInteger guestWrites=PluginAutoWrites;active.on=YES;
            [active sendActionsForControlEvents:UIControlEventValueChanged];
            Check(@"plugin-detail-guest-cannot-change-auto-sharing",PluginAutoWrites==guestWrites && !active.on,nil);
            FixtureHost=YES;window.hidden=YES;window.rootViewController=nil;
        });
    } else {window.hidden=YES;window.rootViewController=nil;}
}
static void RunUpdatePromptTests(void) {
    LCOrbitPreferences *prefs=[LCOrbitStorage preferences];
    [prefs setObject:nil forKey:@"LCFloatingMenu.skippedUpdateVersion"];
    [NSUserDefaults.standardUserDefaults setObject:UpdateRelease(@"9.0.8") forKey:@"LCFloatingMenu.updateIndicator.release"];
    CapturedAlert=nil;UpdatePromptPresentations=0;GitHubCompletions=[NSMutableArray array];
    FMSettingsRootController *root=[FMSettingsRootController new];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:root];
    UIWindow *window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.rootViewController=nav;window.hidden=NO;[window layoutIfNeeded];[root loadViewIfNeeded];
    AttemptAutomaticUpdate(root);
    NSArray *buttons=[CapturedAlert.actions valueForKey:@"title"];
    Check(@"update-auto-prompt-has-notes-and-two-actions",[CapturedAlert.title containsString:@"9.0.8"] &&
          [CapturedAlert.message containsString:@"改善设置中的更新提醒"] &&
          [buttons isEqual:@[@"跳过此版本",@"下载更新"]],nil);
    NSUInteger offered=UpdatePromptPresentations;
    AttemptAutomaticUpdate(root);NotifyUpdate(UpdateRelease(@"9.0.8"));
    Check(@"update-auto-same-version-once-per-controller",offered==1 && UpdatePromptPresentations==offered,nil);
    InvokeAlertAction(CapturedAlert,@"跳过此版本");
    Check(@"update-skip-persists-exact-version",[[prefs objectForKey:@"LCFloatingMenu.skippedUpdateVersion"] isEqual:@"9.0.8"],nil);
    CapturedAlert=nil;
    FMSettingsRootController *reopened=[FMSettingsRootController new];
    SetUpdateRoot(nav,reopened,window);AttemptAutomaticUpdate(reopened);
    Check(@"update-skipped-version-suppressed-after-reopen",!CapturedAlert,nil);
    [reopened checkForUpdates];CompleteUpdateRequest(@"9.0.8");
    dispatch_async(dispatch_get_main_queue(),^{
        Check(@"update-manual-check-ignores-skipped-version",[CapturedAlert.title containsString:@"9.0.8"] &&
              [[CapturedAlert.actions valueForKey:@"title"] containsObject:@"下载更新"],
              @{@"hasWindow":@(reopened.view.window!=nil),@"isTop":@(nav.topViewController==reopened),
                @"hidden":@(window.hidden),@"checking":[reopened valueForKey:@"checkingUpdate"],
                @"pendingRequests":@(GitHubCompletions.count),@"title":CapturedAlert.title?:@""});
        CapturedAlert=nil;NotifyUpdate(UpdateRelease(@"9.0.9"));AttemptAutomaticUpdate(reopened);
        Check(@"update-new-version-still-offered",[CapturedAlert.title containsString:@"9.0.9"],nil);
        RejectUpdateSkipSave=YES;InvokeAlertAction(CapturedAlert,@"跳过此版本");RejectUpdateSkipSave=NO;
        Check(@"update-failed-skip-reports-error",[CapturedAlert.title isEqual:@"跳过未保存"],nil);
        Check(@"update-failed-skip-not-persisted",[[prefs objectForKey:@"LCFloatingMenu.skippedUpdateVersion"] isEqual:@"9.0.8"],nil);
        CapturedAlert=nil;
        UIViewController *child=[UIViewController new];[nav pushViewController:child animated:NO];
        NotifyUpdate(UpdateRelease(@"9.0.10"));AttemptAutomaticUpdate(reopened);
        Check(@"update-notification-does-not-interrupt-child-page",!CapturedAlert,nil);
        [nav popViewControllerAnimated:NO];[window layoutIfNeeded];[nav.view layoutIfNeeded];AttemptAutomaticUpdate(reopened);
        Check(@"update-return-to-root-offers-late-version",[CapturedAlert.title containsString:@"9.0.10"],nil);
        CapturedAlert=nil;window.hidden=YES;
        NotifyUpdate(UpdateRelease(@"9.0.11"));AttemptAutomaticUpdate(reopened);
        Check(@"update-hidden-window-does-not-prompt",!CapturedAlert,nil);
        window.hidden=NO;
        FixtureHost=NO;AttemptAutomaticUpdate(reopened);
        Check(@"update-guest-does-not-auto-prompt",!CapturedAlert,nil);
        FixtureHost=YES;
        AttemptAutomaticUpdate(reopened);UIAlertController *downloadAlert=CapturedAlert;
        NSUInteger downloadsBefore=DownloadResumes;
        InvokeAlertAction(downloadAlert,@"下载更新");InvokeAlertAction(downloadAlert,@"下载更新");
        Check(@"update-download-action-starts-once-without-second-confirmation",DownloadResumes==downloadsBefore+1 &&
              [DownloadRequest.URL.absoluteString isEqual:UpdateRelease(@"9.0.11")[@"downloadURL"]] &&
              ![DownloadRequest valueForHTTPHeaderField:@"Authorization"],nil);
        CapturedAlert=nil;
        if(DownloadCompletion) {
            void (^completion)(NSData *,NSURLResponse *,NSError *)=DownloadCompletion;DownloadCompletion=nil;
            completion([@"fixture-binary" dataUsingEncoding:NSUTF8StringEncoding],
                [[NSHTTPURLResponse alloc] initWithURL:DownloadRequest.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}],nil);
        }
        dispatch_async(dispatch_get_main_queue(),^{
            Check(@"update-download-uses-existing-digest-install-boundary",UpdateInstalls==1 &&
                  [InstalledUpdateDigest isEqual:UpdateRelease(@"9.0.11")[@"sha256"]],nil);
            // No metadata: fetch once, leave the root before completion. The
            // late result is cacheable but cannot take over a child page.
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"LCFloatingMenu.updateIndicator.release"];
            NSUInteger before=GitHubRequests;
            FMSettingsRootController *late=[FMSettingsRootController new];
            SetUpdateRoot(nav,late,window);CapturedAlert=nil;
            AttemptAutomaticUpdate(late);AttemptAutomaticUpdate(late);
            Check(@"update-missing-metadata-fetches-once-per-controller",GitHubRequests==before+1,nil);
            [nav pushViewController:[UIViewController new] animated:NO];CompleteUpdateRequest(@"9.0.12");
            dispatch_async(dispatch_get_main_queue(),^{
                NSDictionary *cached=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"LCFloatingMenu.updateIndicator.release"];
                Check(@"update-late-response-caches-without-presenting",!CapturedAlert && [cached[@"version"] isEqual:@"9.0.12"],nil);
                [NSUserDefaults.standardUserDefaults removeObjectForKey:@"LCFloatingMenu.updateIndicator.release"];
                FMSettingsRootController *notesRoot=[FMSettingsRootController new];
                SetUpdateRoot(nav,notesRoot,window);AttemptAutomaticUpdate(notesRoot);
                NSDictionary *metadata=UpdateRelease(@"9.0.13");
                CompleteUpdateJSON(@{@"body":[NSString stringWithFormat:@"FM_VERSION=9.0.13\nFM_COMMIT=%@\nFM_TAG=fm-latest",metadata[@"commit"]],
                    @"assets":@[@{@"name":@"LCFloatingMenu.dylib",@"digest":metadata[@"sha256"],@"browser_download_url":metadata[@"downloadURL"]}]});
                dispatch_async(dispatch_get_main_queue(),^{
                    Check(@"update-metadata-only-fetches-version-tag-notes",[GitHubRequestedURL hasSuffix:@"/releases/tags/9.0.13"] && GitHubCompletions.count>0,nil);
                    CompleteUpdateJSON(@{@"tag_name":@"9.0.13",@"body":@"# 独立版本说明\n这里是正式更新说明。"});
                    dispatch_async(dispatch_get_main_queue(),^{
                        NSDictionary *enriched=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"LCFloatingMenu.updateIndicator.release"];
                        Check(@"update-version-tag-enriches-prompt-and-cache",[CapturedAlert.message containsString:@"正式更新说明"] &&
                              [enriched[@"notes"] containsString:@"正式更新说明"],nil);
                        // Two real checks finish out of order: the older
                        // result must not rewind cache or visible prompts.
                        [notesRoot checkForUpdates];
                        FMSettingsRootController *fast=[FMSettingsRootController new];
                        SetUpdateRoot(nav,fast,window);[fast checkForUpdates];
                        CapturedAlert=nil;CompleteUpdateRequest(@"9.0.21");CompleteUpdateRequest(@"9.0.20");
                        dispatch_async(dispatch_get_main_queue(),^{
                            NSDictionary *newest=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"LCFloatingMenu.updateIndicator.release"];
                            Check(@"update-out-of-order-release-never-rewinds-cache-or-prompt",[newest[@"version"] isEqual:@"9.0.21"] &&
                                  ![CapturedAlert.title containsString:@"9.0.20"],nil);
                            // Same artifact with complete cached notes must
                            // survive a later metadata-only fallback result.
                            [fast checkForUpdates];
                            NSDictionary *same=UpdateRelease(@"9.0.21");
                            NSDictionary *(^metadataOnly)(NSString *)=^NSDictionary *(NSString *commit) {
                                return @{@"body":[NSString stringWithFormat:@"FM_VERSION=9.0.21\nFM_COMMIT=%@",commit],
                                    @"assets":@[@{@"name":@"LCFloatingMenu.dylib",@"digest":same[@"sha256"],@"browser_download_url":same[@"downloadURL"]}]};
                            };
                            CompleteUpdateJSON(metadataOnly(same[@"commit"]));
                            CompleteUpdateJSON(@{@"tag_name":@"wrong-version",@"body":@"不应使用的说明"});
                            dispatch_async(dispatch_get_main_queue(),^{
                                NSDictionary *preserved=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"LCFloatingMenu.updateIndicator.release"];
                                Check(@"update-same-artifact-notes-never-downgrade-to-fallback",[preserved[@"notes"] containsString:@"改善设置中的更新提醒"],nil);
                                // Even equal versions can refer to distinct
                                // artifacts. Keep the first accepted artifact;
                                // never pair its binary with another's notes.
                                [notesRoot checkForUpdates];[fast checkForUpdates];
                                NSString *newCommit=@"cccccccccccccccccccccccccccccccccccccccc";
                                NSString *newBody=[NSString stringWithFormat:@"FM_VERSION=9.0.22\nFM_COMMIT=%@\n新构建对应说明",newCommit];
                                NSDictionary *asset=@{@"name":@"LCFloatingMenu.dylib",@"digest":same[@"sha256"],@"browser_download_url":same[@"downloadURL"]};
                                CompleteUpdateJSON(@{@"body":newBody,@"assets":@[asset]});
                                NSString *oldBody=[NSString stringWithFormat:@"FM_VERSION=9.0.22\nFM_COMMIT=%@",same[@"commit"]];
                                CompleteUpdateJSON(@{@"body":oldBody,@"assets":@[asset]});
                                CompleteUpdateJSON(@{@"tag_name":@"9.0.22",@"body":@"旧构建迟到的说明"});
                                dispatch_async(dispatch_get_main_queue(),^{
                                    NSDictionary *artifact=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"LCFloatingMenu.updateIndicator.release"];
                                    Check(@"update-same-version-artifact-keeps-matched-notes",[artifact[@"commit"] isEqual:newCommit] &&
                                          [artifact[@"notes"] containsString:@"新构建对应说明"] && ![artifact[@"notes"] containsString:@"旧构建"],nil);
                                    [fast checkForUpdates];
                                    NSString *rebuilt=@"dddddddddddddddddddddddddddddddddddddddd";
                                    NSString *rebuiltDigest=@"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
                                    CompleteUpdateJSON(@{@"body":[NSString stringWithFormat:@"FM_VERSION=9.0.22\nFM_COMMIT=%@\n同版本重新构建说明",rebuilt],
                                        @"assets":@[@{@"name":@"LCFloatingMenu.dylib",@"digest":rebuiltDigest,@"browser_download_url":same[@"downloadURL"]}]});
                                    dispatch_async(dispatch_get_main_queue(),^{
                                        NSDictionary *latestArtifact=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"LCFloatingMenu.updateIndicator.release"];
                                        Check(@"update-new-check-can-accept-same-version-rebuild",[latestArtifact[@"commit"] isEqual:rebuilt] &&
                                              [latestArtifact[@"sha256"] isEqual:rebuiltDigest] && [latestArtifact[@"notes"] containsString:@"重新构建"],nil);
                                        window.hidden=YES;window.rootViewController=nil;
                                        [prefs setObject:nil forKey:@"LCFloatingMenu.skippedUpdateVersion"];
                                        RunPluginManagementTests();
                                    });
                                });
                            });
                        });
                    });
                });
            });
        });
    });
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
static void RunShapePageTests(void) {
    FMManager *manager=[FMManager shared];
    UIWindow *oldWindow=manager.settingsWindow;
    UINavigationController *oldNavigation=manager.settingsNavigation;
    UIView *oldOrbHost=manager.orbPreviewHost,*oldDimensions=manager.dimensionsPreview;
    LCOrbitPreferences *prefs=[LCOrbitStorage preferences];
    id oldSide=[prefs objectForKey:@"LCFloatingMenu.onLeft"];
    [prefs setObject:@YES forKey:@"LCFloatingMenu.onLeft"];
    for(NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(320,320)],
                          [NSValue valueWithCGSize:CGSizeMake(375,667)],
                          [NSValue valueWithCGSize:CGSizeMake(844,390)]]) {
        CGSize bounds=size.CGSizeValue;
        GeometryWindow *window=[[GeometryWindow alloc] initWithFrame:(CGRect){CGPointZero,bounds}];
        window.fixtureSize=bounds;window.fixtureInsets=UIEdgeInsetsMake(0,0,21,0);
        UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
        window.rootViewController=nav;manager.settingsNavigation=nav;manager.settingsWindow=window;
        UIView *edge=[[UIView alloc] initWithFrame:window.bounds];[window addSubview:edge];manager.orbPreviewHost=edge;
        window.hidden=NO;
        FMSettingsSectionController *page=[[FMSettingsSectionController alloc] initWithSection:@"dimensions"];
        [nav pushViewController:page animated:NO];
        [window layoutIfNeeded];[page.view layoutIfNeeded];[page.view layoutIfNeeded];
        UIView *preview=[page.view viewWithTag:9220];
        UIScrollView *scroll=[page valueForKey:@"contentScroll"];
        CGRect fixed=preview.frame;
        Check([NSString stringWithFormat:@"native-shape-page-pinned-%@",size],preview.superview==page.view && manager.dimensionsPreview==preview && edge.hidden && CGRectGetMinY(scroll.frame)>=CGRectGetMaxY(preview.frame)-.5 && scroll.bounds.size.height>40,@{@"preview":NSStringFromCGRect(preview.frame),@"scroll":NSStringFromCGRect(scroll.frame)});
        [scroll setContentOffset:CGPointMake(0,MAX(0,scroll.contentSize.height-scroll.bounds.size.height)) animated:NO];
        [page.view layoutIfNeeded];
        Check([NSString stringWithFormat:@"native-shape-preview-stays-on-scroll-%@",size],CGRectEqualToRect(fixed,preview.frame) && [preview viewWithTag:9211]!=nil && [preview viewWithTag:9221]!=nil,nil);
        [nav popViewControllerAnimated:NO];[window layoutIfNeeded];
        Check([NSString stringWithFormat:@"native-shape-page-restores-edge-preview-%@",size],manager.dimensionsPreview==nil && !edge.hidden && [prefs boolForKey:@"LCFloatingMenu.onLeft"],nil);
        window.hidden=YES;window.rootViewController=nil;
    }
    [prefs setObject:oldSide forKey:@"LCFloatingMenu.onLeft"];
    manager.settingsWindow=oldWindow;manager.settingsNavigation=oldNavigation;
    manager.orbPreviewHost=oldOrbHost;manager.dimensionsPreview=oldDimensions;
}
static void RunTests(void) {
    UIEdgeInsets ordinary=UIEdgeInsetsMake(0,0,21,0);
    LCOrbitPreferences *prefs=[LCOrbitStorage preferences];
    // A Guest's forced appearance must never override the menu's selection.
    id savedAppearance=[prefs objectForKey:@"LCFloatingMenu.appearanceMode"];
    [prefs setObject:@2 forKey:@"LCFloatingMenu.appearanceMode"];
    FMManager *forcedNight=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    forcedNight.window.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;
    [forcedNight refreshSystemAppearance];
    UIView *nightGlass=[forcedNight.orb viewWithTag:9202];
    UIVisualEffectView *nightMaterial=nil;
    for(UIView *child in nightGlass.subviews)
        if([child isKindOfClass:UIVisualEffectView.class]) nightMaterial=(UIVisualEffectView *)child;
    Check(@"guest-forced-light-preserves-menu-dark",
          forcedNight.overlayView.overrideUserInterfaceStyle==UIUserInterfaceStyleDark &&
          nightGlass.overrideUserInterfaceStyle==UIUserInterfaceStyleDark &&
          nightMaterial.overrideUserInterfaceStyle==UIUserInterfaceStyleDark,
          @{@"overlay":@(forcedNight.overlayView.overrideUserInterfaceStyle),
            @"glass":@(nightGlass.overrideUserInterfaceStyle),
            @"material":@(nightMaterial.overrideUserInterfaceStyle)});
    [prefs setObject:@1 forKey:@"LCFloatingMenu.appearanceMode"];
    FMManager *forcedDay=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    forcedDay.window.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    [forcedDay refreshSystemAppearance];
    UIView *dayGlass=[forcedDay.orb viewWithTag:9202];
    Check(@"guest-forced-dark-preserves-menu-light",
          forcedDay.overlayView.overrideUserInterfaceStyle==UIUserInterfaceStyleLight &&
          dayGlass.overrideUserInterfaceStyle==UIUserInterfaceStyleLight,nil);
    [prefs setObject:@0 forKey:@"LCFloatingMenu.appearanceMode"];
    [forcedNight refreshSystemAppearance];
    UIUserInterfaceStyle screenStyle=UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    if(screenStyle==UIUserInterfaceStyleLight || screenStyle==UIUserInterfaceStyleDark)
        Check(@"follow-system-does-not-inherit-guest-light",
              forcedNight.overlayView.overrideUserInterfaceStyle==screenStyle &&
              [forcedNight.orb viewWithTag:9202].overrideUserInterfaceStyle==screenStyle,
              @{@"screen":@(screenStyle),@"guest":@(forcedNight.window.overrideUserInterfaceStyle)});
    if(savedAppearance) [prefs setObject:savedAppearance forKey:@"LCFloatingMenu.appearanceMode"];
    else [prefs removeObjectForKey:@"LCFloatingMenu.appearanceMode"];
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
    Check(@"bead-default-style-proportion",fabs(proportion.orb.bounds.size.width-14)<.01 &&
          fabs(proportion.orb.bounds.size.height-102)<.01,NSStringFromCGRect(proportion.orb.bounds));
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
        CGRect orb=Frame(m.orb,m);BOOL safe=left.boolValue?fabs(CGRectGetMinX(orb))<.01:fabs(CGRectGetMaxX(orb)-667)<.01;
        Check([NSString stringWithFormat:@"horizontal-edge-attached-handle-%@",left],safe,NSStringFromCGRect(orb));
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
    g.fixtureState=UIGestureRecognizerStateChanged;g.fixturePoint=CGPointMake(150,210);[pan pan:g];
    UIView *orbGlass=[pan.orb viewWithTag:9202];
    CAShapeLayer *neutralMask=(CAShapeLayer *)orbGlass.layer.mask;
    CGPathRef neutralPath=CGPathCreateCopy(neutralMask.path);
    CGFloat orbW=CGRectGetWidth(orbGlass.bounds),orbH=CGRectGetHeight(orbGlass.bounds);
    BOOL roundedTop=CGPathContainsPoint(neutralPath,NULL,CGPointMake(orbW*.5,.10),NO) &&
                    !CGPathContainsPoint(neutralPath,NULL,CGPointMake(orbW*.05,.10),NO);
    BOOL roundedBottom=CGPathContainsPoint(neutralPath,NULL,CGPointMake(orbW*.5,orbH-.10),NO) &&
                       !CGPathContainsPoint(neutralPath,NULL,CGPointMake(orbW*.95,orbH-.10),NO);
    Check(@"drag-capsule-not-trapezoid",roundedTop && roundedBottom,nil);
    g.fixtureState=UIGestureRecognizerStateChanged;g.fixturePoint=CGPointMake(520,210);[pan pan:g];
    Check(@"drag-crosses-screen-without-flip",CGPathEqualToPath(neutralPath,neutralMask.path) &&
          !pan.left,nil);
    CGPathRelease(neutralPath);
    NSUInteger cancelWrites=PositionWrites;g.fixtureState=UIGestureRecognizerStateCancelled;[pan pan:g];
    Check(@"cancelled-pan-does-not-save-position",PositionWrites==cancelWrites,nil);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.6*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Check(@"cancelled-pan-restores-position",CGRectEqualToRect(saved,pan.orb.frame),@{@"saved":NSStringFromCGRect(saved),@"actual":NSStringFromCGRect(pan.orb.frame),@"positionWrites":@(PositionWrites)});
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
    FMManager *style=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    UIStackView *styleStack=[UIStackView new];
    [style populateSettingsCategory:@"dimensions" stack:styleStack];
    NSMutableArray<UISlider *> *styleSliders=[NSMutableArray array];
    for(UIView *view in Views(styleStack)) if([view isKindOfClass:UISlider.class] && view.tag>=30 && view.tag<40) [styleSliders addObject:(UISlider *)view];
    Check(@"orb-style-has-ten-adjustments",styleSliders.count==10,@(styleSliders.count));
    UISlider *extension=nil;
    for(UISlider *slider in styleSliders) if(slider.tag==30) extension=slider;
    style.orbPreviewHost=[[UIView alloc] initWithFrame:CGRectMake(0,0,667,667)];
    style.orbPreviewHost.userInteractionEnabled=NO;
    [style.overlayView addSubview:style.orbPreviewHost];
    style.orbY=0;[style refreshOrbPreview];
    Check(@"orb-preview-works-before-overlay-install",fabs(CGRectGetMidY([style.orbPreviewHost viewWithTag:9211].frame)-333.5)<.01,nil);
    style.orbY=.5;
    extension.value=31;[style sliderChanged:extension];
    Check(@"orb-preview-live-before-slider-release",fabs([style.orbPreviewHost viewWithTag:9211].bounds.size.height-114)<.01,nil);
    [style sliderFinished:extension];
    Check(@"orb-style-slider-applies-and-persists",fabs(style.orb.bounds.size.height-114)<.01 &&
        [prefs doubleForKey:@"LCFloatingMenu.orbExtension"]==31,NSStringFromCGRect(style.orb.bounds));
    UIView *fixedPreview=[[UIView alloc] initWithFrame:CGRectMake(0,0,667,220)];
    [style.overlayView addSubview:fixedPreview];style.dimensionsPreview=fixedPreview;
    id savedSide=[prefs objectForKey:@"LCFloatingMenu.onLeft"];
    [prefs setObject:@YES forKey:@"LCFloatingMenu.onLeft"];
    NSUInteger previewWrites=PositionWrites;[style refreshOrbPreview];
    UIView *previewOrb=[fixedPreview viewWithTag:9211],*previewMenu=[fixedPreview viewWithTag:9221];
    Check(@"shape-preview-left-menu-right-orb",fabs(CGRectGetMaxX(previewOrb.frame)-667)<.01 && fabs(previewMenu.frame.origin.x)<.01,nil);
    Check(@"shape-preview-keeps-saved-docking-position",[prefs boolForKey:@"LCFloatingMenu.onLeft"] && previewWrites==PositionWrites,nil);
    Check(@"shape-preview-hides-duplicate-edge-capsule",style.orbPreviewHost.hidden,nil);
    [prefs setObject:savedSide forKey:@"LCFloatingMenu.onLeft"];
    UIStackView *reopened=[UIStackView new];[style populateSettingsCategory:@"dimensions" stack:reopened];
    BOOL restored=NO;for(UIView *view in Views(reopened)) if([view isKindOfClass:UISlider.class] && view.tag==30) restored=fabs(((UISlider *)view).value-31)<.01;
    Check(@"orb-style-restores-on-reopen",restored,nil);
    NSMutableArray<UISlider *> *menuSliders=[NSMutableArray array];
    for(UIView *view in Views(reopened)) if([view isKindOfClass:UISlider.class] && view.tag>=40 && view.tag<45) [menuSliders addObject:(UISlider *)view];
    Check(@"menu-dimensions-has-five-adjustments",menuSliders.count==5,@(menuSliders.count));
    UIView *oldPreview=style.dimensionsPreview.subviews.firstObject;
    for(UISlider *slider in menuSliders) {
        slider.value=slider.maximumValue;[style sliderChanged:slider];
    }
    Check(@"menu-preview-updates-during-sliding",oldPreview!=style.dimensionsPreview.subviews.firstObject,nil);
    Check(@"menu-dimensions-persist-independently",[prefs doubleForKey:@"LCFloatingMenu.menuExtension"]==44 && [prefs doubleForKey:@"LCFloatingMenu.menuCompactIconSize"]==50 && [prefs doubleForKey:@"LCFloatingMenu.orbExtension"]==31,nil);
    for(NSNumber *compact in @[@NO,@YES]) for(NSNumber *left in @[@NO,@YES]) {
        FMManager *extreme=Manager(compact.boolValue,1,667,ordinary,left.boolValue,YES,@"apps");
        Check([NSString stringWithFormat:@"menu-extreme-layout-%@-%@",compact,left],extreme.panel && extreme.appsScroll.bounds.size.height>0,nil);
        Snapshot(extreme,[NSString stringWithFormat:@"menu-extreme-%@-%@",compact,left]);
    }
    [style resetMenuDimensions];
    Check(@"menu-reset-preserves-orb",[prefs doubleForKey:@"LCFloatingMenu.menuExtension"]==28 && [prefs doubleForKey:@"LCFloatingMenu.orbExtension"]==31,nil);
    [prefs setObject:@33 forKey:@"LCFloatingMenu.menuExtension"];
    [style resetOrbDimensions];
    Check(@"orb-reset-preserves-menu",[prefs doubleForKey:@"LCFloatingMenu.orbExtension"]==25 && [prefs doubleForKey:@"LCFloatingMenu.menuExtension"]==33,nil);
    [style resetMenuDimensions];
    UIStackView *appearanceOnly=[UIStackView new];[style populateSettingsCategory:@"appearance" stack:appearanceOnly];
    BOOL relocated=YES;for(UIView *view in Views(appearanceOnly)) if([view isKindOfClass:UISlider.class] && (view.tag==11 || view.tag==14 || view.tag>=30)) relocated=NO;
    Check(@"dimensions-removed-from-appearance",relocated,nil);
    UIControl *entry=nil;for(UIView *view in Views(appearanceOnly)) if([view isKindOfClass:UIControl.class] && [[(UIControl *)view actionsForTarget:style forControlEvent:UIControlEventTouchUpInside] containsObject:@"openDimensions"]) entry=(UIControl *)view;
    BOOL entryHeight=NO;for(NSLayoutConstraint *constraint in entry.constraints) if(constraint.firstAttribute==NSLayoutAttributeHeight && constraint.constant==65) entryHeight=YES;
    Check(@"dimensions-entry-uses-settings-card",entryHeight && entry.layer.cornerRadius==16 && [entry viewWithTag:9235]!=nil,nil);
    NSUInteger resetCards=0;
    for(UIView *view in Views(reopened)) if([view isKindOfClass:UIControl.class]) {
        NSArray *actions=[(UIControl *)view actionsForTarget:style forControlEvent:UIControlEventTouchUpInside];
        if([actions containsObject:@"resetOrbDimensions"] || [actions containsObject:@"resetMenuDimensions"]) {
            UIView *card=view.superview;BOOL height=NO;
            for(NSLayoutConstraint *constraint in card.constraints) if(constraint.firstAttribute==NSLayoutAttributeHeight && constraint.constant==65) height=YES;
            if(height && card.layer.cornerRadius==16) resetCards++;
        }
    }
    Check(@"dimensions-reset-cards-match-root-style",resetCards==2,@(resetCards));
    BOOL concavityNamed=NO;for(UIView *view in Views(reopened)) if([view isKindOfClass:UISlider.class] && view.tag==36) concavityNamed=[view.accessibilityLabel isEqual:@"凹角弧度"];
    Check(@"orb-connection-renamed-concavity",concavityNamed,nil);
    for(NSNumber *compact in @[@NO,@YES]) for(NSNumber *width in @[@320,@667]) {
        [prefs setObject:compact forKey:@"LCFloatingMenu.compactMode"];
        fixedPreview.frame=CGRectMake(0,0,width.doubleValue,100);
        [style refreshOrbPreview];
        UIView *menu=[fixedPreview viewWithTag:9221],*orb=[fixedPreview viewWithTag:9211];
        Check([NSString stringWithFormat:@"shape-preview-fits-short-window-%@-%@",compact,width],CGRectContainsRect(fixedPreview.bounds,menu.frame) && CGRectContainsRect(fixedPreview.bounds,orb.frame) && CGRectGetMaxX(menu.frame)<CGRectGetMinX(orb.frame),nil);
    }
    style.dimensionsPreview=nil;[fixedPreview removeFromSuperview];[style refreshOrbPreview];
    Check(@"leaving-dimensions-restores-edge-preview",!style.orbPreviewHost.hidden && [style.orbPreviewHost viewWithTag:9211]!=nil,nil);

    [prefs removeObjectForKey:@"LCFloatingMenu.orbExtension"];
    id savedMode=[prefs objectForKey:@"LCFloatingMenu.appearanceMode"];
    id savedAccent=[prefs objectForKey:@"LCFloatingMenu.accentLight"];
    [prefs setObject:@1 forKey:@"LCFloatingMenu.appearanceMode"];
    FMManager *theme=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    CAGradientLayer *dayCapsule=nil;
    for(UIView *view in Views(theme.orb)) for(CALayer *layer in view.layer.sublayers)
        if([layer.name isEqualToString:@"fm.orb.capsule"]) dayCapsule=(CAGradientLayer *)layer;
    UIColor *dayEdge=dayCapsule.colors.count?[UIColor colorWithCGColor:(__bridge CGColorRef)dayCapsule.colors.firstObject]:nil;
    CGFloat dayWhite=1,dayAlpha=0;[dayEdge getWhite:&dayWhite alpha:&dayAlpha];
    Check(@"day-capsule-has-neutral-contrast",dayCapsule && dayWhite<.1 && dayAlpha>=.12,nil);
    theme.overlayView.backgroundColor=[UIColor colorWithWhite:.95 alpha:1];
    Snapshot(theme,@"collapsed-bead-light");
    UIViewController *themePage=[UIViewController new];UIStackView *themeStack=[UIStackView new];
    [themePage.view addSubview:themeStack];[theme populateSettingsCategory:@"appearance" stack:themeStack];
    theme.settingsNavigation=[[UINavigationController alloc] initWithRootViewController:themePage];
    theme.settingsWindow=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,667,667)];
    theme.settingsWindow.rootViewController=theme.settingsNavigation;
    theme.orbPreviewHost=[[UIView alloc] initWithFrame:theme.settingsWindow.bounds];
    theme.orbPreviewHost.userInteractionEnabled=NO;[theme.settingsWindow addSubview:theme.orbPreviewHost];
    UIColorWell *well=nil;UISlider *themeSlider=nil;
    for(UIView *view in Views(themeStack)) {
        if([view isKindOfClass:UIColorWell.class] && view.tag==200) well=(UIColorWell *)view;
        if([view isKindOfClass:UISlider.class] && view.tag==13) themeSlider=(UISlider *)view;
    }
    UIView *wellParent=well.superview;UIColor *green=[UIColor colorWithRed:0 green:1 blue:0 alpha:1];
    well.selectedColor=green;[theme themeColorChanged:well];
    Check(@"theme-color-applies-without-replacing-picker",[themeSlider.tintColor isEqual:green] && well.superview==wellParent && [prefs objectForKey:@"LCFloatingMenu.accentLight"]!=nil,nil);
    UIView *firstPreview=[theme.orbPreviewHost viewWithTag:9211];
    well.selectedColor=UIColor.redColor;[theme themeColorChanged:well];
    Check(@"theme-color-refreshes-preview-immediately",firstPreview!=[theme.orbPreviewHost viewWithTag:9211] && [themeSlider.tintColor isEqual:UIColor.redColor],nil);
    [prefs setObject:savedMode forKey:@"LCFloatingMenu.appearanceMode"];
    [prefs setObject:savedAccent forKey:@"LCFloatingMenu.accentLight"];
    theme.settingsWindow=nil;theme.settingsNavigation=nil;theme.orbPreviewHost=nil;
    dispatch_async(dispatch_get_main_queue(), ^{
    FMManager *snap=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    snap.window.hidden=NO;
    FixturePan *move=[FixturePan new];move.fixturePoint=CGPointMake(640,200);move.fixtureState=UIGestureRecognizerStateBegan;[snap pan:move];
    move.fixturePoint=CGPointMake(640,230);move.fixtureState=UIGestureRecognizerStateChanged;[snap pan:move];
    UIButton *movingOrb=snap.orb;
    Check(@"moving-orb-only-capsule",CGSizeEqualToSize(movingOrb.bounds.size,CGSizeMake(12,52)) && [movingOrb viewWithTag:9204].alpha==0,NSStringFromCGRect(movingOrb.bounds));
    move.fixturePoint=CGPointMake(10,230);[snap pan:move];move.fixtureState=UIGestureRecognizerStateEnded;[snap pan:move];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        UIView *glass=[snap.orb viewWithTag:9202];CALayer *capsule=nil;
        for(CALayer *layer in glass.layer.sublayers) if([layer.name isEqualToString:@"fm.orb.capsule"]) capsule=layer;
        CGFloat markerX=0;for(UIView *view in glass.subviews) if([view.accessibilityIdentifier isEqual:@"fm.orb.update-indicator"]) markerX=view.center.x;
        Check(@"snap-restores-new-side-layout",snap.left && snap.orb!=movingOrb && fabs(capsule.frame.origin.x-2)<.01 && fabs(markerX-8)<.01 && [snap.orb viewWithTag:9204].alpha==1,@{@"left":@(snap.left),@"new":@(snap.orb!=movingOrb),@"capsule":NSStringFromCGRect(capsule.frame),@"marker":@(markerX),@"backdrop":@([snap.orb viewWithTag:9204].alpha),@"orb":NSStringFromCGRect(snap.orb.bounds)});
        Snapshot(snap,@"orb-after-animated-snap");snap.window.hidden=YES;
    });
    });
    // Exercise the real native settings pages with credentials behind a
    // fixture boundary. A saved token must never become text-field content.
    FMManager *githubHost=Manager(NO,1,667,ordinary,NO,NO,@"apps");
    FMSettingsRootController *githubRoot=[FMSettingsRootController new];
    githubRoot.view.frame=githubHost.overlayView.bounds;
    [githubHost.overlayView addSubview:githubRoot.view];[githubRoot rebuild];
    BOOL hostEntry=NO;
    for(UIView *view in Views(githubRoot.view)) if([view isKindOfClass:UILabel.class])
        hostEntry |= [((UILabel *)view).text isEqual:@"GitHub 访问"];
    Check(@"github-host-access-entry",hostEntry,nil);
    FixtureHost=NO;[githubRoot rebuild];BOOL guestEntry=NO;
    for(UIView *view in Views(githubRoot.view)) if([view isKindOfClass:UILabel.class])
        guestEntry |= [((UILabel *)view).text isEqual:@"GitHub 访问"];
    Check(@"github-guest-access-entry-hidden",!guestEntry,nil);
    FixtureHost=YES;GitHubAccount=@"fixture-account";GitHubHasToken=YES;
    FMSettingsSectionController *githubPage=[[FMSettingsSectionController alloc] initWithSection:@"github"];
    UINavigationController *githubNavigation=[[UINavigationController alloc] initWithRootViewController:githubPage];
    // GeometryWindow intentionally keeps its root view detached for layout
    // fixtures. Credential actions require a presented native page, so give
    // this navigation stack its own visible UIWindow and real containment.
    UIWindow *githubWindow=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    githubWindow.rootViewController=githubNavigation;githubWindow.hidden=NO;
    [githubWindow layoutIfNeeded];[githubPage loadViewIfNeeded];[githubPage rebuild];
    Check(@"github-page-mounted-in-native-window",githubPage.view.window==githubWindow &&
          githubNavigation.topViewController==githubPage,nil);
    BOOL accountVisible=NO,tokenStatusVisible=NO;
    for(UIView *view in Views(githubPage.view)) if([view isKindOfClass:UILabel.class]) {
        accountVisible |= [((UILabel *)view).text containsString:@"fixture-account"];
        tokenStatusVisible |= [((UILabel *)view).text containsString:@"Token：已保存"];
    }
    Check(@"github-page-shows-account-and-token-status",[githubPage.title isEqual:@"GitHub 访问"] &&
          accountVisible && tokenStatusVisible,nil);
    CapturedAlert=nil;if([githubPage respondsToSelector:@selector(editGitHubCredentials)]) [githubPage editGitHubCredentials];
    NSArray<UITextField *> *credentialFields=CapturedAlert.textFields;
    Check(@"github-edit-token-secure-and-never-prefilled",credentialFields.count==2 &&
          [credentialFields[0].text isEqual:@"fixture-account"] && !credentialFields[0].secureTextEntry &&
          credentialFields[1].secureTextEntry && credentialFields[1].text.length==0,nil);
    credentialFields.firstObject.text=@"edited-account";
    InvokeAlertAction(CapturedAlert,@"保存");
    Check(@"github-empty-token-submitted-without-reading-saved-token",GitHubSaves==1 &&
          GitHubSavedEmptyToken && GitHubHasToken && [GitHubAccount isEqual:@"edited-account"],nil);
    if([githubPage respondsToSelector:@selector(clearGitHubCredentials)]) [githubPage clearGitHubCredentials];BOOL destructive=NO;
    for(UIAlertAction *action in CapturedAlert.actions) destructive |= action.style==UIAlertActionStyleDestructive;
    Check(@"github-clear-requires-destructive-confirmation",destructive &&
          [CapturedAlert.title isEqual:@"清除 GitHub 凭据？"],nil);
    InvokeAlertAction(CapturedAlert,@"清除");
    Check(@"github-clear-uses-credential-client",GitHubClears==1 && !GitHubHasToken && !GitHubAccount,nil);
    FixtureHost=NO;NSUInteger readsBefore=GitHubCredentialReads;
    [githubPage rebuild];CapturedAlert=nil;
    if([githubPage respondsToSelector:@selector(editGitHubCredentials)]) [githubPage editGitHubCredentials];
    if([githubPage respondsToSelector:@selector(verifyGitHubConnection)]) [githubPage verifyGitHubConnection];
    if([githubPage respondsToSelector:@selector(clearGitHubCredentials)]) [githubPage clearGitHubCredentials];
    Check(@"github-guest-never-reads-host-credentials",GitHubCredentialReads==readsBefore && !CapturedAlert,nil);
    FixtureHost=YES;GitHubAccount=@"fixture-account";GitHubHasToken=YES;GitHubCompletions=[NSMutableArray array];
    if([githubPage respondsToSelector:@selector(verifyGitHubConnection)]) {
        CapturedAlert=nil;NSUInteger requestsBefore=GitHubRequests;
        [githubPage verifyGitHubConnection];[githubPage verifyGitHubConnection];
        Check(@"github-verification-uses-user-endpoint-and-coalesces",GitHubRequests==requestsBefore+1 &&
              [GitHubRequestedURL isEqual:@"https://api.github.com/user"],nil);
        // Clear while the request is in flight, then deliver its old result.
        [githubPage clearGitHubCredentials];InvokeAlertAction(CapturedAlert,@"清除");CapturedAlert=nil;
        CompleteGitHub(@"fixture-account",200);
        dispatch_async(dispatch_get_main_queue(),^{
            BOOL staleShown=[CapturedAlert.title isEqual:@"GitHub 访问"];
            for(UIView *view in Views(githubPage.view)) if([view isKindOfClass:UILabel.class])
                staleShown |= [((UILabel *)view).text hasPrefix:@"连接成功"];
            Check(@"github-clearing-invalidates-in-flight-verification",!staleShown,nil);
            GitHubAccount=@"expected-account";GitHubHasToken=YES;
            [githubPage verifyGitHubConnection];CompleteGitHub(@"other-account",200);
            dispatch_async(dispatch_get_main_queue(),^{
                Check(@"github-verification-rejects-account-mismatch",[CapturedAlert.message containsString:@"账号不一致"],nil);
                CapturedAlert=nil;GitHubAccount=nil;
                [githubPage verifyGitHubConnection];CompleteGitHub(@"actual-account",200);
                dispatch_async(dispatch_get_main_queue(),^{
                    Check(@"github-verification-shows-actual-login",[CapturedAlert.message containsString:@"actual-account"],nil);
                    CapturedAlert=nil;githubWindow.hidden=YES;githubWindow.rootViewController=nil;
                    RunUpdatePromptTests();
                });
            });
        });
    } else {githubWindow.hidden=YES;githubWindow.rootViewController=nil;RunUpdatePromptTests();}
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
        RunShapePageTests();
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
    Results=[NSMutableArray array];Managers=[NSMutableArray array];AutoPiPStates=[NSMutableDictionary dictionary];GitHubCompletions=[NSMutableArray array];NSMutableArray *apps=[NSMutableArray array];
    for(NSUInteger i=0;i<8;i++) {NSString *folder=[home stringByAppendingFormat:@"/Documents/Fixture%lu.app",(unsigned long)i];[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];[@{@"CFBundleName":[NSString stringWithFormat:@"App %lu",(unsigned long)i]} writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES];[apps addObject:@{@"folder":folder,@"title":[NSString stringWithFormat:@"App %lu",(unsigned long)i],@"identity":folder,@"path":folder,@"launchable":@YES}];}FixtureApps=apps;
    SwapClass(LCOrbitGuestService.class,@selector(installedApps),@selector(fixtureApps));SwapClass(LCOrbitGuestService.class,@selector(isCurrentGuest:),@selector(fixtureCurrent:));
    SwapClass(LCOrbitMultitask.class,@selector(isCurrentGuest:),@selector(fixtureCurrent:));SwapClass(LCOrbitMultitask.class,@selector(isRunningGuest:),@selector(fixtureRunning:));SwapClass(LCOrbitMultitask.class,@selector(closeGuest:error:),@selector(fixtureClose:error:));SwapClass(LCOrbitMultitask.class,@selector(isEnabled),@selector(fixtureEnabled));SwapClass(LCOrbitHost.class,@selector(isHostUI),@selector(fixtureHost));
    SwapClass(LCOrbitMultitask.class,@selector(automaticPiPEnabledForGuest:),@selector(fixtureAutoPiP:));
    SwapClass(LCOrbitMultitask.class,@selector(setAutomaticPiPEnabled:forGuest:error:),@selector(fixtureSetAutoPiP:forGuest:error:));
    SwapClass(LCOrbitTweakSync.class,@selector(pluginInventory),@selector(fixturePluginInventory));
    if([LCOrbitTweakSync respondsToSelector:@selector(automaticSyncEnabledForPlugin:)])
        SwapClass(LCOrbitTweakSync.class,@selector(automaticSyncEnabledForPlugin:),@selector(fixtureAutomaticSyncEnabledForPlugin:));
    if([LCOrbitTweakSync respondsToSelector:@selector(setAutomaticSyncEnabled:forPlugin:error:)])
        SwapClass(LCOrbitTweakSync.class,@selector(setAutomaticSyncEnabled:forPlugin:error:),@selector(fixtureSetAutomaticSyncEnabled:forPlugin:error:));
    SwapClass(LCOrbitTweakSync.class,@selector(syncAutomaticallyIfNeeded),@selector(fixtureSyncAutomaticallyIfNeeded));
    SwapClass(LCOrbitTweakCenter.class,@selector(pluginInfo:shared:),@selector(fixturePluginInfo:shared:));
    SwapClass(NSURLSession.class,@selector(sharedSession),@selector(fixtureSharedSession));
    SwapClass(LCOrbitPluginUpdater.class,@selector(installDownloadedPlugin:expectedSHA256:error:),@selector(fixtureInstallDownloadedPlugin:expectedSHA256:error:));
    SwapClass(LCOrbitStorage.class,@selector(lastError),@selector(fixtureLastError));
    SwapClass(LCOrbitGitHub.class,@selector(accountWithError:),@selector(fixtureAccountWithError:));
    SwapClass(LCOrbitGitHub.class,@selector(hasTokenWithError:),@selector(fixtureHasTokenWithError:));
    SwapClass(LCOrbitGitHub.class,@selector(saveAccount:token:error:),@selector(fixtureSaveAccount:token:error:));
    SwapClass(LCOrbitGitHub.class,@selector(clearCredentialsWithError:),@selector(fixtureClearCredentialsWithError:));
    SwapClass(LCOrbitGitHub.class,@selector(requestForURL:timeout:error:),@selector(fixtureRequestForURL:timeout:error:));
    SwapClass(LCOrbitGitHub.class,@selector(performRequest:completion:),@selector(fixturePerformRequest:completion:));
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
