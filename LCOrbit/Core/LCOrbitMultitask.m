#import "LCOrbitMultitask.h"
#import "LCOrbitHost.h"
#import "LCOrbitStorage.h"
#import <objc/message.h>

NSString *const LCOrbitMultitaskLaunchFailedNotification=@"LCOrbitMultitaskLaunchFailed";
NSString *const LCOrbitMultitaskMenuRequestedNotification=@"LCOrbitMultitaskMenuRequested";
NSString *const LCOrbitMultitaskConfigurationChangedNotification=@"LCOrbitMultitaskConfigurationChanged";
static NSString *const EnabledKey=@"LCFloatingMenu.fullscreenMultitask";
static NSString *const SystemMenuKey=@"LCFloatingMenu.systemMultitaskMenu";
static NSString *const PreviousModeKey=@"LCFloatingMenu.previousMultitaskMode";
static NSString *const AutoPiPKey=@"LCFloatingMenu.autoPiPApps";

@interface LCOrbitTaskWindow : NSObject
@property(nonatomic,weak) id window;
@property(nonatomic,copy) NSString *bundle, *container;
@property(nonatomic,copy) NSString *folder;
@end
@implementation LCOrbitTaskWindow @end

static NSMutableArray<LCOrbitTaskWindow *> *TaskWindows;
static __weak id ActiveWindow;
static NSUUID *PendingLaunch;
static NSDictionary *PendingGuest;

static id Call(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return [object respondsToSelector:selector]?((id(*)(id,SEL))objc_msgSend)(object,selector):nil;
}
static NSUserDefaults *SharedDefaults(void) { return Call(NSUserDefaults.class,@"lcSharedDefaults"); }
static BOOL Fail(NSError **error,NSString *message) {
    if(error) *error=[NSError errorWithDomain:@"LCOrbitMultitask" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static BOOL TaskPathComponent(id value) {
    return [value isKindOfClass:NSString.class] && [value length] &&
        ![value isEqualToString:@"."] && ![value isEqualToString:@".."] &&
        [value rangeOfString:@"/"].location==NSNotFound && [value rangeOfString:@"\\"].location==NSNotFound;
}
static NSString *CanonicalFolder(id path) {
    if(![path isKindOfClass:NSString.class] || ![path length]) return nil;
    return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}
static NSString *AutomaticPiPIdentity(NSDictionary *guest) {
    if(![guest isKindOfClass:NSDictionary.class] || [guest[@"builtin"] boolValue]) return nil;
    id identity=guest[@"identity"];
    if(![identity isKindOfClass:NSString.class]) return nil;
    NSArray *parts=[identity componentsSeparatedByString:@"/"];
    if(parts.count!=2 || ![@[@"private",@"shared"] containsObject:parts[0]] ||
       !TaskPathComponent(parts[1]) || ![parts[1] isEqual:guest[@"path"]]) return nil;
    return identity;
}
static void RefreshAutomaticPiP(void) {
    Class automatic=NSClassFromString(@"LCOrbitAutomaticPiP");
    SEL refresh=NSSelectorFromString(@"refresh");
    if([automatic respondsToSelector:refresh]) ((void(*)(id,SEL))objc_msgSend)(automatic,refresh);
}
static void SetVisible(id window,BOOL visible) {
    id scene=Call(window,@"appSceneVC");
    SEL pip=NSSelectorFromString(@"shouldIgnoreSceneUpdates");
    if([scene respondsToSelector:pip] && ((BOOL(*)(id,SEL))objc_msgSend)(scene,pip)) return;
    SEL selector=NSSelectorFromString(@"orbit_setVisible:");
    if([window respondsToSelector:selector]) ((void(*)(id,SEL,BOOL))objc_msgSend)(window,selector,visible);
}
static void FinishLaunch(NSUUID *token,NSNumber *pid,NSError *error) {
    if(PendingLaunch!=token) return;
    PendingLaunch=nil;
    PendingGuest=nil;
    if(!error && pid.intValue>0) { RefreshAutomaticPiP();return; }
    if(!error) Fail(&error,@"LC 未返回有效的多任务进程，请从 LC 检查应用。 ");
    [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskLaunchFailedNotification
        object:LCOrbitMultitask.class userInfo:@{@"error":error}];
}
@implementation LCOrbitMultitask
+ (BOOL)isEnabled {
    LCOrbitPreferences *defaults=[LCOrbitStorage preferences];
    id module=[defaults objectForKey:@"LCOrbit.module.FloatingMenu.enabled"];
    return [LCOrbitHost isHostUI] && (!module || [module boolValue]) && [defaults boolForKey:EnabledKey];
}
+ (BOOL)isManagingWindows {
    return [self isEnabled] && ![self usesSystemMenu] && SharedDefaults() &&
        [SharedDefaults() integerForKey:@"LCMultitaskMode"]==0;
}
+ (BOOL)usesSystemMenu { return [[LCOrbitStorage preferences] boolForKey:SystemMenuKey]; }
+ (BOOL)shouldShowFloatingMenu {
    id module=[[LCOrbitStorage preferences] objectForKey:@"LCOrbit.module.FloatingMenu.enabled"];
    return (!module || [module boolValue]) && !([self isEnabled] && [self usesSystemMenu]);
}
+ (BOOL)setUseSystemMenu:(BOOL)system error:(NSError **)error {
    if(!NSThread.isMainThread || ![LCOrbitHost isHostUI]) return Fail(error,@"请在 LC 主界面选择多任务菜单。");
    if(PendingLaunch) return Fail(error,@"应用正在启动，请稍后再选择多任务模式。");
    [[LCOrbitStorage preferences] setBool:system forKey:SystemMenuKey];
    NSError *writeError=[LCOrbitStorage lastError];
    if(writeError) { if(error) *error=writeError;return NO; }
    if([self respondsToSelector:@selector(refreshPresentation)]) [self refreshPresentation];
    [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskConfigurationChangedNotification object:self];
    RefreshAutomaticPiP();
    return YES;
}
+ (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
    if(!NSThread.isMainThread || ![LCOrbitHost isHostUI]) return Fail(error,@"请在 LC 主界面调整全屏多任务。");
    if(PendingLaunch) return Fail(error,@"应用正在启动，请稍后再调整多任务模式。");
    LCOrbitPreferences *defaults=[LCOrbitStorage preferences];
    if(enabled) {
        if(!SharedDefaults() || ![self respondsToSelector:@selector(installHooksWithError:)])
            return Fail(error,@"当前 LC 未提供可用的多任务接口。");
        if(![self installHooksWithError:error]) return NO;
        [defaults setBool:YES forKey:EnabledKey];
        NSError *writeError=[LCOrbitStorage lastError];
        if(writeError) { if(error) *error=writeError;return NO; }
    } else {
        [defaults setBool:NO forKey:EnabledKey];
        NSError *writeError=[LCOrbitStorage lastError];
        if(writeError) { if(error) *error=writeError;return NO; }
        // Restore window presentation without changing user-owned LC preferences.
        if([self respondsToSelector:@selector(refreshPresentation)]) [self refreshPresentation];
    }
    // Old releases forced LC's backend and saved a snapshot. Its provenance is
    // ambiguous after manual edits; never replay it over the user's current value.
    [[LCOrbitHost hostDefaults] removeObjectForKey:PreviousModeKey];
    if(enabled && [self respondsToSelector:@selector(refreshPresentation)]) [self refreshPresentation];
    [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskConfigurationChangedNotification object:self];
    RefreshAutomaticPiP();
    return YES;
}
+ (BOOL)automaticPiPEnabledForGuest:(NSDictionary *)guest {
    NSString *identity=AutomaticPiPIdentity(guest);
    id apps=[[LCOrbitStorage preferences] objectForKey:AutoPiPKey];
    return identity && [apps isKindOfClass:NSArray.class] && [apps containsObject:identity];
}
+ (BOOL)setAutomaticPiPEnabled:(BOOL)enabled forGuest:(NSDictionary *)guest error:(NSError **)error {
    if(!NSThread.isMainThread || ![LCOrbitHost isHostUI]) return Fail(error,@"请在 LC 应用管理中设置自动画中画。");
    NSString *identity=AutomaticPiPIdentity(guest);
    if(!identity) return Fail(error,@"该项目不是可设置的 App。");
    id stored=[[LCOrbitStorage preferences] objectForKey:AutoPiPKey];
    NSMutableArray *apps=[stored isKindOfClass:NSArray.class]?[stored mutableCopy]:[NSMutableArray array];
    [apps removeObject:identity];
    if(enabled) [apps addObject:identity];
    [[LCOrbitStorage preferences] setObject:apps forKey:AutoPiPKey];
    NSError *writeError=[LCOrbitStorage lastError];
    if(writeError) { if(error) *error=writeError;return NO; }
    RefreshAutomaticPiP();
    [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskConfigurationChangedNotification object:self];
    return YES;
}
+ (NSDictionary *)activeGuestForAutomaticPiP {
    if(!NSThread.isMainThread || ![self isEnabled]) return nil;
    id window=[self activeWindow],scene=Call(window,@"appSceneVC");
    SEL running=NSSelectorFromString(@"isAppRunning");
    if(![scene respondsToSelector:running] || !((BOOL(*)(id,SEL))objc_msgSend)(scene,running)) return nil;
    NSArray *inventory=Call(NSClassFromString(@"LCOrbitGuestService"),@"installedApps");
    for(LCOrbitTaskWindow *entry in TaskWindows) if(entry.window==window && entry.folder.length) {
        for(NSDictionary *guest in inventory) {
            if(AutomaticPiPIdentity(guest) && [entry.bundle isEqual:guest[@"path"]] &&
               [entry.folder isEqual:CanonicalFolder(guest[@"folder"])]) {
                // Settings belong to the App; the selected live window may use
                // a different container from the inventory's configured default.
                NSMutableDictionary *active=[guest mutableCopy];
                active[@"uuid"]=entry.container;
                return active;
            }
        }
    }
    return nil;
}
+ (NSArray *)windows {
    NSMutableArray *windows=[NSMutableArray array];
    for(LCOrbitTaskWindow *entry in [TaskWindows copy]) {
        id window=entry.window;
        if(window) [windows addObject:window]; else [TaskWindows removeObject:entry];
    }
    return windows;
}
+ (id)activeWindow { return [self isEnabled]?ActiveWindow:nil; }
+ (void)recordWindow:(id)window bundle:(NSString *)bundle container:(NSString *)container {
    if(!window || !TaskPathComponent(bundle) || !TaskPathComponent(container)) return;
    if(!TaskWindows) TaskWindows=[NSMutableArray array];
    for(LCOrbitTaskWindow *entry in [TaskWindows copy]) {
        if(!entry.window) [TaskWindows removeObject:entry];
        else if(entry.window==window) return;
    }
    LCOrbitTaskWindow *entry=[LCOrbitTaskWindow new];entry.window=window;
    if([PendingGuest[@"path"] isEqual:bundle] && [PendingGuest[@"uuid"] isEqual:container])
        entry.folder=CanonicalFolder(PendingGuest[@"folder"]);
    if(!entry.folder) {
        Class utils=NSClassFromString(@"LCSharedUtils");
        SEL find=NSSelectorFromString(@"findBundleWithBundleId:isSharedAppOut:");
        if([utils respondsToSelector:find]) {
            bool shared=false;
            NSBundle *bundleInfo=((id(*)(id,SEL,id,bool*))objc_msgSend)(utils,find,bundle,&shared);
            entry.folder=CanonicalFolder(bundleInfo.bundlePath);
        }
    }
    entry.bundle=bundle;entry.container=container;[TaskWindows addObject:entry];
}
+ (void)forgetWindow:(id)window {
    BOOL changed=NO;
    for(LCOrbitTaskWindow *entry in [TaskWindows copy]) {
        if(!entry.window || entry.window==window) {
            [TaskWindows removeObject:entry];
            changed=YES;
        }
    }
    if(ActiveWindow==window) { ActiveWindow=nil;changed=YES; }
    // Module shutdown calls forgetWindow:nil even if no weak entry expired.
    // Reconcile the auto-PiP opt-in immediately in that case as well.
    RefreshAutomaticPiP();
    if(changed) {
        // Scene cleanup may still be running. Redraw after LC finishes it.
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskConfigurationChangedNotification
                object:self];
        });
    }
}
+ (void)didActivateWindow:(id)window {
    if(![self isEnabled]) return;
    if([self isManagingWindows]) for(id other in [self windows]) if(other!=window) SetVisible(other,NO);
    ActiveWindow=window;
    RefreshAutomaticPiP();
    [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskMenuRequestedNotification
        object:self userInfo:@{@"expanded":@NO}];
}
+ (void)didHideWindow:(id)window {
    if(ActiveWindow!=window) return;
    ActiveWindow=nil;
    RefreshAutomaticPiP();
    if([self isEnabled]) [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskMenuRequestedNotification
        object:self userInfo:@{@"expanded":@NO}];
}
+ (void)requestMenu {
    if(!NSThread.isMainThread || ![self isEnabled] || [self usesSystemMenu]) return;
    [NSNotificationCenter.defaultCenter postNotificationName:LCOrbitMultitaskMenuRequestedNotification
        object:self userInfo:@{@"expanded":@YES}];
}
+ (BOOL)isCurrentGuest:(NSDictionary *)guest {
    if(![self isEnabled] || [guest[@"builtin"] boolValue]) return NO;
    for(LCOrbitTaskWindow *entry in TaskWindows)
        if(entry.window && entry.window==ActiveWindow && [entry.bundle isEqual:guest[@"path"]] &&
           [entry.container isEqual:guest[@"uuid"]] && [entry.folder isEqual:CanonicalFolder(guest[@"folder"])]) return YES;
    return NO;
}
// Use LC's own PiPManager rather than creating another AVKit controller.
// Only explicit user taps request PiP; switching apps never starts it silently.
+ (BOOL)togglePiPForActiveWindow:(NSError **)error {
    if(!NSThread.isMainThread || ![self isEnabled] || ![LCOrbitHost isHostUI])
        return Fail(error,@"请在 LC 多任务界面使用画中画。");
    if(@available(iOS 16.0,*)) {} else return Fail(error,@"此系统不支持 LC 画中画。");
    id window=[self activeWindow];
    id scene=Call(window,@"appSceneVC");
    SEL running=NSSelectorFromString(@"isAppRunning");
    if(!window || ![scene respondsToSelector:running] ||
       !((BOOL(*)(id,SEL))objc_msgSend)(scene,running))
        return Fail(error,@"没有正在播放的前台任务，请先打开目标 App。");
    Class manager=NSClassFromString(@"PiPManager");
    id pip=Call(manager,@"shared");
    SEL inspect=NSSelectorFromString(@"isPiPWithDecoratedVC:");
    SEL begin=NSSelectorFromString(@"startPiPWithVC:");
    SEL stop=NSSelectorFromString(@"stopPiP");
    if(!pip || ![pip respondsToSelector:inspect] ||
       ![pip respondsToSelector:begin] || ![pip respondsToSelector:stop])
        return Fail(error,@"当前 LC 未提供兼容的画中画管理器。");
    if(((BOOL(*)(id,SEL,id))objc_msgSend)(pip,inspect,window))
        ((void(*)(id,SEL))objc_msgSend)(pip,stop);
    else ((void(*)(id,SEL,id))objc_msgSend)(pip,begin,scene);
    return YES;
}
+ (void)showHome {
    if(![self isEnabled]) return;
    for(id window in [self windows]) SetVisible(window,NO);
    ActiveWindow=nil;
    RefreshAutomaticPiP();
}
+ (BOOL)isRunningGuest:(NSDictionary *)guest {
    if(!NSThread.isMainThread || ![self isEnabled] || ![guest isKindOfClass:NSDictionary.class] ||
       !TaskPathComponent(guest[@"path"]) || !TaskPathComponent(guest[@"uuid"])) return NO;
    NSString *folder=CanonicalFolder(guest[@"folder"]);
    if(!folder.length) return NO;
    for(LCOrbitTaskWindow *entry in [TaskWindows copy]) {
        id window=entry.window;
        if(!window || ![entry.bundle isEqual:guest[@"path"]] ||
           ![entry.container isEqual:guest[@"uuid"]] || ![entry.folder isEqual:folder]) continue;
        id scene=Call(window,@"appSceneVC");
        SEL isRunning=NSSelectorFromString(@"isAppRunning");
        if([scene respondsToSelector:isRunning] &&
           ((BOOL(*)(id,SEL))objc_msgSend)(scene,isRunning) &&
           [window respondsToSelector:NSSelectorFromString(@"closeWindow")]) return YES;
    }
    return NO;
}
+ (BOOL)closeGuest:(NSDictionary *)guest error:(NSError **)error {
    if(![self isRunningGuest:guest]) return Fail(error,@"目标任务未运行或身份已变化，未关闭其他任务。");
    NSString *folder=CanonicalFolder(guest[@"folder"]);
    for(LCOrbitTaskWindow *entry in [TaskWindows copy]) {
        id window=entry.window;
        if(!window || ![entry.bundle isEqual:guest[@"path"]] ||
           ![entry.container isEqual:guest[@"uuid"]] || ![entry.folder isEqual:folder]) continue;
        // Never substitute the active task if this target has already exited.
        id scene=Call(window,@"appSceneVC");
        SEL isRunning=NSSelectorFromString(@"isAppRunning"), close=NSSelectorFromString(@"closeWindow");
        if(![scene respondsToSelector:isRunning] ||
           !((BOOL(*)(id,SEL))objc_msgSend)(scene,isRunning) ||
           ![window respondsToSelector:close]) break;
        ((void(*)(id,SEL))objc_msgSend)(window,close);
        return YES;
    }
    return Fail(error,@"目标任务已退出，未执行关闭操作。");
}
+ (BOOL)closeCurrentGuest {
    id window=[self activeWindow];SEL close=NSSelectorFromString(@"closeWindow");
    if(!window || ![window respondsToSelector:close]) return NO;
    ((void(*)(id,SEL))objc_msgSend)(window,close);
    return YES;
}
+ (BOOL)launchGuest:(NSDictionary *)guest error:(NSError **)error {
    if(!NSThread.isMainThread || ![self isEnabled]) return Fail(error,@"全屏多任务仅在已启用的 LC 宿主中可用。");
    if(![guest isKindOfClass:NSDictionary.class] || !TaskPathComponent(guest[@"path"]) ||
       !TaskPathComponent(guest[@"uuid"]) || !CanonicalFolder(guest[@"folder"]) ||
       ![guest[@"launchable"] boolValue] || [guest[@"builtin"] boolValue])
        return Fail(error,@"应用暂不可多任务启动，请先从 LC 启动。");
    if(PendingLaunch) return Fail(error,@"另一个应用正在启动，请稍后再试。");
    if(![self usesSystemMenu] && [SharedDefaults() integerForKey:@"LCMultitaskMode"]!=0)
        return Fail(error,@"微珠全屏多任务需要虚拟窗口，请在 LC 多任务设置中选择虚拟窗口；系统模式保留 LC 当前设置。");
    for(LCOrbitTaskWindow *entry in [TaskWindows copy]) {
        if(!entry.window || ![entry.bundle isEqual:guest[@"path"]] || ![entry.container isEqual:guest[@"uuid"]]) continue;
        if(![entry.folder isEqual:CanonicalFolder(guest[@"folder"])])
            return Fail(error,@"同名容器已有其他作用域的任务，请从 LC 原入口处理。");
        id scene=Call(entry.window,@"appSceneVC");
        SEL running=NSSelectorFromString(@"isAppRunning"), activate=NSSelectorFromString(@"orbit_activate");
        if(![scene respondsToSelector:running] || !((BOOL(*)(id,SEL))objc_msgSend)(scene,running) ||
           ![entry.window respondsToSelector:activate]) return Fail(error,@"应用窗口尚未就绪，请稍后再试。");
        ((void(*)(id,SEL))objc_msgSend)(entry.window,activate);
        return YES;
    }
    Class sharedUtils=NSClassFromString(@"LCSharedUtils");
    SEL owner=NSSelectorFromString(@"getContainerUsingLCSchemeWithFolderName:");
    if(![sharedUtils respondsToSelector:owner]) return Fail(error,@"当前 LC 无法检查容器占用状态，请使用 LC 原入口启动。");
    if([((id(*)(id,SEL,id))objc_msgSend)(sharedUtils,owner,guest[@"uuid"]) length])
        return Fail(error,@"此容器已在其他 LC 或任务中运行，请从 LC 原入口切回。");
    Class utils=NSClassFromString(@"LCUtils");
    SEL launch=NSSelectorFromString(@"launchMultitaskGuestApp:completionHandler:");
    if(![utils respondsToSelector:launch] || ![Call(utils,@"liveProcessBundleIdentifier") length])
        return Fail(error,@"未找到 LC 多任务启动接口或 LiveProcess 扩展，请检查 LC 安装。");
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    if([defaults objectForKey:@"selected"] || [defaults objectForKey:@"selectedContainer"])
        return Fail(error,@"LC 中已有待处理的启动请求，请稍后再试。");
    [defaults setBool:NO forKey:@"LCOpenSideStore"];
    [defaults removeObjectForKey:@"launchAppUrlScheme"];
    [defaults setObject:guest[@"path"] forKey:@"selected"];
    [defaults setObject:guest[@"uuid"] forKey:@"selectedContainer"];
    NSUUID *token=NSUUID.UUID;PendingLaunch=token;PendingGuest=[guest copy];
    void (^completion)(NSNumber *,NSError *)=^(NSNumber *pid,NSError *failure) {
        if(NSThread.isMainThread) FinishLaunch(token,pid,failure);
        else dispatch_async(dispatch_get_main_queue(),^{FinishLaunch(token,pid,failure);});
    };
    ((void(*)(id,SEL,id,id))objc_msgSend)(utils,launch,guest[@"title"]?:guest[@"path"],completion);
    // LCUtils consumes both keys synchronously. Do not leave restart selections on error.
    if([[defaults stringForKey:@"selected"] isEqual:guest[@"path"]] &&
       [[defaults stringForKey:@"selectedContainer"] isEqual:guest[@"uuid"]]) {
        [defaults removeObjectForKey:@"selected"];[defaults removeObjectForKey:@"selectedContainer"];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(PendingLaunch==token) {
            NSError *timeout=nil;Fail(&timeout,@"多任务启动超时，请从 LC 检查应用状态。");
            FinishLaunch(token,nil,timeout);
        }
    });
    return YES;
}
@end
