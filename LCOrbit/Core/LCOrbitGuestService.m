#import "LCOrbitGuestService.h"
#import "LCOrbitHost.h"
#import "LCOrbitMultitask.h"
#import <objc/message.h>
#import <stdlib.h>

static id HostCall(Class cls, NSString *name) {
    SEL sel=NSSelectorFromString(name);
    return [cls respondsToSelector:sel]?((id(*)(id,SEL))objc_msgSend)(cls,sel):nil;
}
static NSString *String(id value) {
    return [value isKindOfClass:NSString.class]?value:nil;
}
static BOOL Flag(id value) {
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}
static NSInteger Number(id value) {
    return [value respondsToSelector:@selector(integerValue)]?[value integerValue]:0;
}
static BOOL OrbitGuestPathComponent(NSString *value) {
    return String(value).length && ![value isEqualToString:@"."] && ![value isEqualToString:@".."] &&
        [value isEqualToString:value.lastPathComponent] && [value rangeOfString:@"/"].location==NSNotFound &&
        [value rangeOfString:@"\\"].location==NSNotFound;
}
static NSString *Canonical(NSString *path) {
    return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}
static NSString *SideStoreFramework(void) {
    NSBundle *host=HostCall(NSUserDefaults.class,@"lcMainBundle");
    if(![host isKindOfClass:NSBundle.class]) return nil;
    NSString *path=[host.bundlePath stringByAppendingPathComponent:@"Frameworks/SideStoreApp.framework"];
    BOOL directory=NO;
    if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] || !directory) return nil;
    return [NSFileManager.defaultManager fileExistsAtPath:
        [path stringByAppendingPathComponent:@"LCAppInfo.plist"]]?path:nil;
}
static NSString *Container(NSDictionary *lc, NSString **reason) {
    id raw=lc[@"LCDataUUID"];
    NSString *uuid=String(raw);
    if(uuid.length && OrbitGuestPathComponent(uuid)) return uuid;
    if(raw && (!uuid || uuid.length)) { *reason=@"invalid-container"; return @""; }
    // LC accepts an explicit selectedContainer. Only infer it when unambiguous.
    NSMutableSet<NSString *> *choices=[NSMutableSet set];
    id containers=lc[@"LCContainers"];
    if([containers isKindOfClass:NSArray.class]) for(id entry in containers) {
        if(![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *name=String(entry[@"folderName"]);
        if(OrbitGuestPathComponent(name)) [choices addObject:name];
    }
    if(choices.count==1) return choices.anyObject;
    *reason=choices.count?@"select-container":@"missing-container";
    return @"";
}
static NSString *Status(NSString *reason) {
    NSDictionary *labels=@{@"needs-jit":@"需要 JIT",@"needs-patch":@"需修复补丁",
        @"manual-signing":@"请从 LC 启动",@"loader-disabled":@"插件未启用",
        @"loader-unavailable":@"插件不可注入",@"missing-executable":@"文件不完整",
        @"invalid-container":@"容器异常",@"missing-container":@"缺少容器",
        @"select-container":@"需选择容器",@"private-name-conflict":@"同名冲突",
        @"locked":@"已锁定",@"hidden":@"已隐藏"};
    return labels[reason]?:@"";
}
static NSArray<NSDictionary *> *ScanInstalledApps(NSMutableArray<NSString *> *diagnostics) {
    NSMutableArray<NSDictionary *> *list=[NSMutableArray array];
    BOOL hostMultitask=[LCOrbitMultitask isEnabled];
    const char *raw=getenv("LC_HOME_PATH");
    NSString *home=(raw && raw[0])?[NSString stringWithUTF8String:raw]:nil;
    if(!home.length) { [diagnostics addObject:@"inventory-error reason=missing-host-home"]; return list; }
    NSString *privateRoot=[home stringByAppendingPathComponent:@"Documents/Applications"];
    NSMutableArray<NSDictionary *> *roots=[NSMutableArray arrayWithObject:
        @{@"path":privateRoot,@"shared":@NO}];
    NSString *group=String([LCOrbitHost appGroupPath]);
    if(group.length) [roots addObject:@{@"path":[group stringByAppendingPathComponent:@"LiveContainer/Applications"],@"shared":@YES}];
    else [diagnostics addObject:@"inventory-error scope=shared reason=missing-app-group"];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSMutableSet *seenFolders=[NSMutableSet set];
    for(NSDictionary *rootInfo in roots) {
        NSString *root=rootInfo[@"path"];
        BOOL shared=[rootInfo[@"shared"] boolValue];
        NSString *scope=shared?@"shared":@"private";
        NSError *error=nil;
        NSArray *entries=[fm contentsOfDirectoryAtPath:root error:&error];
        [diagnostics addObject:[NSString stringWithFormat:@"inventory-root scope=%@ count=%lu error=%ld path=%@",
            scope,(unsigned long)entries.count,(long)error.code,root]];
        for(NSString *entry in [entries sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
            if(!OrbitGuestPathComponent(entry) || ![entry hasSuffix:@".app"]) continue;
            NSString *folder=[root stringByAppendingPathComponent:entry];
            NSDictionary *lc=[NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:@"LCAppInfo.plist"]];
            if(![lc isKindOfClass:NSDictionary.class]) {
                [diagnostics addObject:[NSString stringWithFormat:@"inventory-skip scope=%@ app=%@ reason=unreadable-lc-info",scope,entry]];
                continue;
            }
            // The user's all-app inventory includes hidden and locked apps.
            // Preserve their flags; visibility never grants launch permission.
            BOOL hidden=Flag(lc[@"isHidden"]),locked=Flag(lc[@"isLocked"]);
            NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:@"Info.plist"]];
            if(![info isKindOfClass:NSDictionary.class]) {
                [diagnostics addObject:[NSString stringWithFormat:@"inventory-skip scope=%@ app=%@ reason=unreadable-info",scope,entry]];
                continue;
            }
            NSString *canonical=Canonical(folder);
            if([seenFolders containsObject:canonical]) continue;
            [seenFolders addObject:canonical];
            NSString *reason=@"";
            NSString *uuid=Container(lc,&reason);
            if(Flag(lc[@"isJITNeeded"]) || Flag(lc[@"is32bit"])) reason=@"needs-jit";
            else if(Number(lc[@"LCPatchRevision"])<7) reason=@"needs-patch";
            else if(Flag(lc[@"dontSign"])) reason=@"manual-signing";
            // The host owns the fullscreen switcher. Its child tasks do not
            // need a loader or a per-Guest copy of this plugin to participate.
            else if(!hostMultitask && Flag(lc[@"LCTweakLoaderCantInject"])) reason=@"loader-unavailable";
            else if(!hostMultitask && (Flag(lc[@"dontLoadTweakLoader"]) || Flag(lc[@"dontInjectTweakLoader"]))) reason=@"loader-disabled";
            NSString *exec=String(info[@"CFBundleExecutable"]);
            BOOL executableDirectory=NO;
            if(!OrbitGuestPathComponent(exec) || ![fm fileExistsAtPath:[folder stringByAppendingPathComponent:exec]
                isDirectory:&executableDirectory] || executableDirectory) reason=@"missing-executable";
            // Stock LC resolves a bundle name private-first. Merely showing both
            // entries must never turn selecting shared into launching private.
            NSString *privateFolder=[privateRoot stringByAppendingPathComponent:entry];
            if(shared && [fm fileExistsAtPath:privateFolder] && ![Canonical(privateFolder) isEqualToString:canonical])
                reason=@"private-name-conflict";
            if(locked) reason=@"locked";
            else if(hidden) reason=@"hidden";
            NSString *bundle=Flag(lc[@"doUseLCBundleId"])?String(lc[@"LCOrignalBundleIdentifier"]):nil;
            if(!bundle.length) bundle=String(info[@"CFBundleIdentifier"]);
            NSString *title=String(info[@"CFBundleDisplayName"]);
            if(!title.length) title=String(info[@"CFBundleName"]);
            if(!title.length) title=entry.stringByDeletingPathExtension;
            NSDictionary *classicCache=[lc[@"LCClassicModeCache"] isKindOfClass:NSDictionary.class]?lc[@"LCClassicModeCache"]:nil;
            NSNumber *cachedMode=classicCache[@"defaultClassicMode"], *cachedSystem=classicCache[@"systemMajorVersion"];
            BOOL knownMode=[cachedMode isKindOfClass:NSNumber.class] && [cachedSystem isKindOfClass:NSNumber.class] &&
                cachedSystem.integerValue==NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
            BOOL classicOnly=Flag(lc[@"classicMode"]) && (!knownMode || cachedMode.unsignedIntegerValue!=0);
            [list addObject:@{@"path":entry,@"title":title,@"uuid":uuid?:@"",@"classicOnly":@(classicOnly),
                @"bundle":bundle?:@"",@"folder":folder,@"shared":@(shared),
                @"hidden":@(hidden),@"locked":@(locked),
                @"identity":[NSString stringWithFormat:@"%@/%@",scope,entry],
                @"launchable":@(!reason.length),@"blockReason":reason,@"status":Status(reason)}];
            [diagnostics addObject:[NSString stringWithFormat:@"inventory-app scope=%@ app=%@ launch=%@",
                scope,entry,reason.length?reason:@"ready"]];
        }
    }
    NSString *sideStore=SideStoreFramework();
    if(sideStore.length) [list addObject:@{@"path":@"builtinSideStore",@"title":@"SideStore",
        @"uuid":@"builtin",@"bundle":@"builtinSideStore",@"folder":sideStore,
        @"identity":@"builtin/SideStore",@"builtin":@YES,@"launchable":@YES,@"status":@""}];
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSComparisonResult order=[a[@"title"] localizedStandardCompare:b[@"title"]];
        return order==NSOrderedSame?[a[@"identity"] compare:b[@"identity"]]:order;
    }];
    return list;
}
static NSError *GuestError(LCOrbitGuestError code, NSString *description) {
    return [NSError errorWithDomain:LCOrbitGuestErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:description}];
}
static BOOL Fail(NSError **error, LCOrbitGuestError code, NSString *message) {
    if(error) *error=GuestError(code,message);
    return NO;
}
static NSDictionary *LegacyTarget(NSString *path,NSString *uuid) {
    if(!OrbitGuestPathComponent(path) || !OrbitGuestPathComponent(uuid) || [path isEqualToString:@"builtinSideStore"]) return nil;
    NSDictionary *match=nil;
    for(NSDictionary *item in ScanInstalledApps(nil)) {
        if(![item[@"path"] isEqualToString:path] || ![item[@"uuid"] isEqualToString:uuid]) continue;
        if(match) return nil; // Legacy path+container cannot disambiguate two roots.
        match=item;
    }
    return Flag(match[@"launchable"])?match:nil;
}
static BOOL LaunchTarget(NSDictionary *target,NSError **error) {
    if(!Flag(target[@"launchable"]))
        return Fail(error,LCOrbitGuestErrorIneligible,@"请先从 LC 启动此 App。");
    if([LCOrbitMultitask isEnabled]) {
        if(Flag(target[@"classicOnly"]))
            return Fail(error,LCOrbitGuestErrorIneligible,@"此 App 使用经典兼容模式，请从 LC 原入口启动。");
        return [LCOrbitMultitask launchGuest:target error:error];
    }
    Class utils=NSClassFromString(@"LCSharedUtils");
    SEL launch=NSSelectorFromString(@"launchToGuestAppWithURL:");
    if(![utils respondsToSelector:launch])
        return Fail(error,LCOrbitGuestErrorMissingAPI,@"当前 LC 版本不提供启动接口。");
    NSURLComponents *url=[NSURLComponents new];
    url.scheme=String(HostCall(NSUserDefaults.class,@"lcAppUrlScheme"));
    if(!url.scheme.length) return Fail(error,LCOrbitGuestErrorMissingScheme,@"无法确认当前 LC 的 URL Scheme。");
    url.host=@"livecontainer-launch";
    url.queryItems=@[[NSURLQueryItem queryItemWithName:@"bundle-name" value:target[@"path"]],
        [NSURLQueryItem queryItemWithName:@"container-folder-name" value:target[@"uuid"]]];
    if(!url.URL) return Fail(error,LCOrbitGuestErrorInvalidURL,@"目标 URL 不合法。");
    NSUserDefaults *host=[LCOrbitHost hostDefaults];
    [host setBool:NO forKey:@"LCOpenSideStore"];
    [host removeObjectForKey:@"launchAppUrlScheme"];
    BOOL accepted=((BOOL(*)(id,SEL,NSURL*))objc_msgSend)(utils,launch,url.URL);
    if(!accepted) {
        [host removeObjectForKey:@"selected"];[host removeObjectForKey:@"selectedContainer"];
        return Fail(error,LCOrbitGuestErrorRejected,@"LC 未能接受启动请求。");
    }
    return YES;
}
NSString *const LCOrbitGuestErrorDomain=@"LCOrbitGuestErrorDomain";
@implementation LCOrbitGuestService
+ (NSArray<NSDictionary *> *)installedApps { return ScanInstalledApps(nil); }
+ (NSArray<NSDictionary *> *)launchableApps {
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *app in ScanInstalledApps(nil)) if(Flag(app[@"launchable"])) [result addObject:app];
    return result;
}
+ (NSArray<NSString *> *)inventoryDiagnostics {
    NSMutableArray *lines=[NSMutableArray array];ScanInstalledApps(lines);return lines;
}
+ (BOOL)isCurrentGuest:(NSDictionary *)app {
    if([LCOrbitMultitask isEnabled]) return [LCOrbitMultitask isCurrentGuest:app];
    if(![app isKindOfClass:NSDictionary.class] || Flag(app[@"builtin"]) || ![LCOrbitHost guestInfo]) return NO;
    NSString *folder=String(app[@"folder"]);
    if(folder.length && [Canonical(folder) isEqualToString:Canonical(NSBundle.mainBundle.bundlePath)]) return YES;
    // Fallback for LC versions whose main bundle has not been swapped yet.
    if(![String(app[@"bundle"]) isEqualToString:[LCOrbitHost guestIdentifier]]) return NO;
    SEL selector=NSSelectorFromString(@"isSharedApp");
    if(![NSUserDefaults respondsToSelector:selector]) return NO;
    BOOL shared=((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,selector);
    if(shared!=Flag(app[@"shared"])) return NO;
    NSString *uuid=String([LCOrbitHost guestInfo][@"LCDataUUID"]);
    return uuid.length && [uuid isEqualToString:app[@"uuid"]];
}
+ (BOOL)isBuiltInSideStoreAvailable { return SideStoreFramework().length>0; }
+ (BOOL)isEligibleGuestPath:(NSString *)path uuid:(NSString *)uuid { return LegacyTarget(path,uuid)!=nil; }
+ (BOOL)launchGuest:(NSDictionary *)app error:(NSError **)error {
    if(![app isKindOfClass:NSDictionary.class] || !OrbitGuestPathComponent(String(app[@"path"])) ||
       !OrbitGuestPathComponent(String(app[@"uuid"])) || !String(app[@"identity"]).length || !String(app[@"folder"]).length)
        return Fail(error,LCOrbitGuestErrorInvalidTarget,@"应用信息已失效，请刷新列表。");
    for(NSDictionary *fresh in ScanInstalledApps(nil)) {
        if(![fresh[@"identity"] isEqualToString:app[@"identity"]] ||
           ![fresh[@"folder"] isEqualToString:app[@"folder"]]) continue;
        if(![fresh[@"uuid"] isEqualToString:app[@"uuid"]])
            return Fail(error,LCOrbitGuestErrorIneligible,@"应用容器已改变，请刷新列表。");
        if(!Flag(fresh[@"launchable"]))
            return Fail(error,LCOrbitGuestErrorIneligible,
                [NSString stringWithFormat:@"%@，请从 LC 处理。",fresh[@"status"]]);
        return LaunchTarget(fresh,error);
    }
    return Fail(error,LCOrbitGuestErrorIneligible,@"应用已移走或信息失效，请刷新列表。");
}
+ (BOOL)launchGuestPath:(NSString *)path uuid:(NSString *)uuid error:(NSError **)error {
    if(![path isEqualToString:@"ui"]) {
        NSDictionary *target=LegacyTarget(path,uuid);
        return target?LaunchTarget(target,error):Fail(error,LCOrbitGuestErrorIneligible,@"应用暂不可快捷切换，请从 LC 启动。");
    }
    Class utils=NSClassFromString(@"LCSharedUtils");
    SEL home=NSSelectorFromString(@"launchToGuestAppWithClassicMode:");
    if(![utils respondsToSelector:home]) return Fail(error,LCOrbitGuestErrorMissingAPI,@"当前 LC 不支持经典模式返回。");
    NSUserDefaults *host=[LCOrbitHost hostDefaults];
    [host setObject:@"ui" forKey:@"selected"];[host removeObjectForKey:@"selectedContainer"];
    [host setBool:NO forKey:@"LCOpenSideStore"];
    BOOL accepted=((BOOL(*)(id,SEL,NSUInteger))objc_msgSend)(utils,home,0);
    if(!accepted) [host removeObjectForKey:@"selected"];
    return accepted?YES:Fail(error,LCOrbitGuestErrorRejected,@"LC 未能接受返回首页请求。");
}
+ (BOOL)launchBuiltInSideStoreWithError:(NSError **)error {
    if(![self isBuiltInSideStoreAvailable]) return Fail(error,LCOrbitGuestErrorSideStoreMissing,@"当前 LC+SS 没有可用的内置 SideStore。");
    Class utils=NSClassFromString(@"LCSharedUtils");
    SEL launch=NSSelectorFromString(@"launchToGuestAppWithClassicMode:");
    if(![utils respondsToSelector:launch]) return Fail(error,LCOrbitGuestErrorMissingAPI,@"当前 LC 缺少内置应用启动接口。");
    NSUserDefaults *host=[LCOrbitHost hostDefaults];
    [host setBool:NO forKey:@"LCOpenSideStore"];[host setObject:@"builtinSideStore" forKey:@"selected"];
    [host removeObjectForKey:@"selectedContainer"];[host removeObjectForKey:@"launchAppUrlScheme"];
    BOOL accepted=((BOOL(*)(id,SEL,NSUInteger))objc_msgSend)(utils,launch,0);
    if(!accepted) { [host removeObjectForKey:@"selected"];return Fail(error,LCOrbitGuestErrorRejected,@"LC 没有接受 SideStore 启动请求。"); }
    return YES;
}
@end
