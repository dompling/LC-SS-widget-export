#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "LCOrbitHost.h"
#import "LCOrbitGuestService.h"
#import "LCOrbitTweakCenter.h"
#import "LCOrbitTweakSync.h"
#import "LCOrbitTweakAudit.h"
#import "LCOrbitStorage.h"
@interface LCOrbitTweakSync (SaveContract)
+ (BOOL)setAutomaticSyncEnabled:(BOOL)enabled error:(NSError **)error;
+ (BOOL)automaticSyncEnabledForPlugin:(NSString *)name;
+ (BOOL)setAutomaticSyncEnabled:(BOOL)enabled forPlugin:(NSString *)name error:(NSError **)error;
@end

// Replace only the LC runtime and audit presentation. Production scanner,
// shared-file operations and metadata writes run unchanged.
static NSString *Home, *Group;
static BOOL HostMode=YES;
static NSUserDefaults *Defaults;
static NSUInteger Assertions, Failures;
static NSString *LatestAudit;
@implementation LCOrbitHost
+ (NSString *)appGroupPath { return Group; }
+ (NSUserDefaults *)hostDefaults { return Defaults; }
+ (NSDictionary *)guestInfo { return nil; }
+ (NSString *)guestIdentifier { return @"test.host"; }
+ (BOOL)isHostUI { return HostMode; }
+ (BOOL)isSupportedGuest { return !HostMode; }
+ (UIWindowScene *)activeScene { return nil; }
@end
@implementation NSUserDefaults (TweakCenterTestHost)
+ (NSBundle *)lcMainBundle { return nil; }
+ (NSString *)lcAppUrlScheme { return @"livecontainer"; }
@end
@implementation LCOrbitTweakAudit
+ (NSString *)logPath { return nil; }
+ (NSString *)captureSnapshot { return @""; }
+ (void)appendEvent:(NSString *)event { LatestAudit=[event copy]; }
+ (void)clearLogs {}
@end
static void Check(BOOL result,NSString *name) {
    Assertions++;
    if(!result) { Failures++;fprintf(stderr,"FAIL: %s\n",name.UTF8String); }
}
static NSString *Root(BOOL shared,NSString *kind) {
    return [[shared?Group:Home stringByAppendingPathComponent:shared?@"LiveContainer":@"Documents"] stringByAppendingPathComponent:kind];
}
static void Directory(NSString *path) {
    NSCAssert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil],@"fixture directory");
}
static BOOL Exists(NSString *path) { return [NSFileManager.defaultManager fileExistsAtPath:path]; }
static NSData *Bytes(NSString *path) { return [NSData dataWithContentsOfFile:path]; }
static NSDictionary *Info(NSString *folder) {
    return [NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:@"LCAppInfo.plist"]];
}
static NSString *Install(BOOL shared,NSString *name,NSDictionary *flags) {
    NSString *folder=[Root(shared,@"Applications") stringByAppendingPathComponent:name];Directory(folder);
    NSMutableDictionary *lc=[@{@"LCPatchRevision":@7,@"LCDataUUID":name,@"LCContainers":@[@{@"folderName":name}]} mutableCopy];
    [lc addEntriesFromDictionary:flags];
    NSDictionary *bundle=@{@"CFBundleName":name,@"CFBundleExecutable":@"Binary",@"CFBundleIdentifier":[@"test." stringByAppendingString:name]};
    NSCAssert([lc writeToFile:[folder stringByAppendingPathComponent:@"LCAppInfo.plist"] atomically:YES],@"fixture LC metadata");
    NSCAssert([bundle writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES],@"fixture Info metadata");
    NSCAssert([[@"fixture" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[folder stringByAppendingPathComponent:@"Binary"] atomically:YES],@"fixture executable");
    return folder;
}
static NSDictionary *Find(NSArray *list,NSString *field,NSString *value) {
    for(NSDictionary *item in list) if([item[field] isEqual:value]) return item;
    return nil;
}
static BOOL FailStageCopy;
@implementation NSFileManager (StagingFailureBoundary)
- (BOOL)orbit_copyItemAtPath:(NSString *)source toPath:(NSString *)destination error:(NSError **)error {
    if(FailStageCopy && [destination hasSuffix:@".tmp"]) {
        if(error) *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:nil];
        return NO;
    }
    return [self orbit_copyItemAtPath:source toPath:destination error:error];
}
@end
static void TestAutomaticSync(NSFileManager *fm,NSString *suite) {
    BOOL available=[LCOrbitTweakSync respondsToSelector:@selector(automaticSyncEnabledForPlugin:)] &&
        [LCOrbitTweakSync respondsToSelector:@selector(setAutomaticSyncEnabled:forPlugin:error:)];
    Check(available,@"per-plugin automatic sharing API is available");
    if(!available) return;
    NSString *source=[Root(NO,@"Tweaks") stringByAppendingPathComponent:@"A.dylib"];
    NSString *sourceB=[Root(NO,@"Tweaks") stringByAppendingPathComponent:@"B.dylib"];
    NSString *destination=[Root(YES,@"Tweaks") stringByAppendingPathComponent:@"A.dylib"];
    NSString *destinationB=[Root(YES,@"Tweaks") stringByAppendingPathComponent:@"B.dylib"];
    NSString *unloaded=[Root(NO,@"Tweaks") stringByAppendingPathComponent:@"Unloaded.dylib"];
    NSString *linked=[Root(NO,@"Tweaks") stringByAppendingPathComponent:@"Linked.dylib"];
    [Bytes(source) writeToFile:unloaded atomically:YES];
    [fm createSymbolicLinkAtPath:linked withDestinationPath:source error:nil];
    Check(![LCOrbitTweakSync automaticSyncEnabled] && ![LCOrbitTweakSync automaticSyncEnabledForPlugin:@"A.dylib"],@"per-plugin automatic sharing defaults off");
    [[LCOrbitStorage preferences] setBool:YES forKey:@"LCFloatingMenu.autoSyncSharedTweaks"];
    [LCOrbitTweakSync syncAutomaticallyIfNeeded];
    Check(![LCOrbitTweakSync automaticSyncEnabled] && !Exists(destination) && !Exists(destinationB),@"old global opt-in never auto-enrolls local plugins");
    NSError *legacyError=nil;
    Check(![LCOrbitTweakSync setAutomaticSyncEnabled:YES error:&legacyError] && legacyError!=nil &&
        ![LCOrbitTweakSync automaticSyncEnabled],@"legacy enable call cannot authorize all plugins");
    NSError *error=nil;
    Check([LCOrbitTweakSync setAutomaticSyncEnabled:YES forPlugin:@"A.dylib" error:&error],@"local plugin can individually opt in");
    Check([LCOrbitTweakSync automaticSyncEnabled] && [LCOrbitTweakSync automaticSyncEnabledForPlugin:@"A.dylib"] && ![LCOrbitTweakSync automaticSyncEnabledForPlugin:@"B.dylib"],@"selection is isolated per local plugin");
    NSUserDefaults *sameSuite=[[NSUserDefaults alloc] initWithSuiteName:suite];
    NSUserDefaults *previous=Defaults;Defaults=sameSuite;
    Check([LCOrbitTweakSync automaticSyncEnabledForPlugin:@"A.dylib"],@"per-plugin opt-in persists across defaults instances");Defaults=previous;
    Check(![LCOrbitTweakSync setAutomaticSyncEnabled:YES forPlugin:@"Linked.dylib" error:&error] &&
        ![LCOrbitTweakSync setAutomaticSyncEnabled:YES forPlugin:@"../A.dylib" error:&error] &&
        ![LCOrbitTweakSync setAutomaticSyncEnabled:YES forPlugin:@"Missing.dylib" error:&error],@"invalid linked or missing sources cannot enroll");
    Check([LCOrbitTweakSync setAutomaticSyncEnabled:YES forPlugin:@"Unloaded.dylib" error:&error],@"ordinary local plugin may opt in before its next host load");
    [LCOrbitTweakSync syncAutomaticallyIfNeeded];
    Check([Bytes(source) isEqual:Bytes(destination)] && !Exists(destinationB),@"automatic sharing copies only explicitly selected loaded plugin");
    Check(!Exists([Root(YES,@"Tweaks") stringByAppendingPathComponent:@"Unloaded.dylib"]),@"selected unloaded plugin is not copied until host loads it");
    Check([LCOrbitTweakSync setAutomaticSyncEnabled:YES forPlugin:@"B.dylib" error:&error],@"second plugin can independently opt in");
    [LCOrbitTweakSync syncAutomaticallyIfNeeded];
    Check([Bytes(sourceB) isEqual:Bytes(destinationB)],@"second selected plugin synchronizes independently");
    [LCOrbitTweakSync setAutomaticSyncEnabled:NO forPlugin:@"A.dylib" error:nil];
    Check(Exists(destination) && [LCOrbitTweakSync automaticSyncEnabled] && ![LCOrbitTweakSync automaticSyncEnabledForPlugin:@"A.dylib"],@"turning one plugin off preserves shared copy and other opt-ins");
    NSData *original=Bytes(source),*originalB=Bytes(sourceB);
    NSMutableData *updated=[original mutableCopy];[updated appendData:[@"updated fixture" dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableData *updatedB=[originalB mutableCopy];[updatedB appendData:[@"updated B" dataUsingEncoding:NSUTF8StringEncoding]];
    [updated writeToFile:source atomically:YES];[updatedB writeToFile:sourceB atomically:YES];
    [LCOrbitTweakSync syncAutomaticallyIfNeeded];
    Check([Bytes(destination) isEqual:original] && [Bytes(destinationB) isEqual:updatedB],@"disabled A cannot update while selected B continues updating");
    [LCOrbitTweakSync setAutomaticSyncEnabled:YES forPlugin:@"A.dylib" error:nil];
    FailStageCopy=YES;[LCOrbitTweakSync syncAutomaticallyIfNeeded];FailStageCopy=NO;
    Check([Bytes(destination) isEqual:original],@"failed staged copy preserves existing shared bytes");
    BOOL noTemporaryFiles=YES;
    for(NSString *name in [fm contentsOfDirectoryAtPath:Root(YES,@"Tweaks") error:nil])
        if([name hasSuffix:@".tmp"]) noTemporaryFiles=NO;
    Check(noTemporaryFiles,@"failed staging leaves no orphan temporary shared files");
    dispatch_apply(8,dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^(size_t index) {
        (void)index;[LCOrbitTweakSync syncAutomaticallyIfNeeded];
    });
    Check([Bytes(destination) isEqual:updated],@"concurrent automatic updates leave complete verified bytes");
    NSString *backupRoot=[Group stringByAppendingPathComponent:@"LiveContainer/LCFloatingMenu/TweakBackups"];
    Check(!Exists(backupRoot),@"automatic sharing does not create persistent history backups");
    NSString *disabled=[destination stringByAppendingString:@".disabled"];
    [fm moveItemAtPath:destination toPath:disabled error:nil];[original writeToFile:source atomically:YES];
    [LCOrbitTweakSync syncAutomaticallyIfNeeded];
    Check(!Exists(destination) && [Bytes(disabled) isEqual:updated],@"automatic sharing preserves intentionally disabled shared copy");
    HostMode=NO;
    Check(![LCOrbitTweakSync setAutomaticSyncEnabled:NO forPlugin:@"A.dylib" error:&error] && [LCOrbitTweakSync automaticSyncEnabledForPlugin:@"A.dylib"],@"guest cannot change host per-plugin opt-in");
    [fm removeItemAtPath:disabled error:nil];[LCOrbitTweakSync syncAutomaticallyIfNeeded];
    Check(!Exists(destination),@"guest cannot trigger automatic sharing");HostMode=YES;
    NSString *outside=[Home stringByAppendingPathComponent:@"outside-file"];
    NSData *sentinel=[@"outside untouched" dataUsingEncoding:NSUTF8StringEncoding];
    [sentinel writeToFile:outside atomically:YES];[fm createSymbolicLinkAtPath:destination withDestinationPath:outside error:nil];
    [LCOrbitTweakSync syncAutomaticallyIfNeeded];
    Check([Bytes(outside) isEqual:sentinel] && [[fm destinationOfSymbolicLinkAtPath:destination error:nil] isEqual:outside],@"automatic sharing rejects linked shared destination");
    [fm removeItemAtPath:destination error:nil];
    NSString *config=[[LCOrbitStorage rootPath] stringByAppendingPathComponent:@"config.json"];
    NSData *good=Bytes(config);[@"broken JSON" writeToFile:config atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *beforeAudit=LatestAudit;NSError *saveError=nil;
    Check(![LCOrbitTweakSync setAutomaticSyncEnabled:NO forPlugin:@"A.dylib" error:&saveError] && saveError!=nil,@"invalid JSON rejects individual switch save with error");
    Check([LCOrbitTweakSync automaticSyncEnabledForPlugin:@"A.dylib"] && [LatestAudit isEqual:beforeAudit],@"failed save retains effective choice without false success log");
    [good writeToFile:config atomically:YES];
    for(NSString *name in @[@"A.dylib",@"B.dylib",@"Unloaded.dylib"])
        [LCOrbitTweakSync setAutomaticSyncEnabled:NO forPlugin:name error:nil];
    Check(![LCOrbitTweakSync automaticSyncEnabled],@"no selected plugins disables automatic trigger");
    [LCOrbitTweakSync syncAutomaticallyIfNeeded];Check(!Exists(destination),@"disabled selections cannot recreate shared copy");
    NSString *sourceOff=[source stringByAppendingString:@".disabled"];
    [fm moveItemAtPath:source toPath:sourceOff error:nil];
    Check([LCOrbitTweakSync setAutomaticSyncEnabled:YES forPlugin:@"A.dylib" error:&error],@"disabled local plugin can retain a future-update opt-in");
    [LCOrbitTweakSync syncAutomaticallyIfNeeded];
    Check(!Exists(destination) && Exists(sourceOff),@"auto opt-in does not enable or copy disabled local plugin");
    [LCOrbitTweakSync setAutomaticSyncEnabled:NO forPlugin:@"A.dylib" error:nil];
    [fm moveItemAtPath:sourceOff toPath:source error:nil];
    [fm removeItemAtPath:destinationB error:nil];[fm removeItemAtPath:unloaded error:nil];[fm removeItemAtPath:linked error:nil];
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=3) return 2;
        NSString *temp=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"orbit-tweak-center-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        Home=[temp stringByAppendingPathComponent:@"host"];Group=[temp stringByAppendingPathComponent:@"group"];
        NSString *suite=[@"orbit.center.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        Defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];setenv("LC_HOME_PATH",Home.UTF8String,1);
        NSFileManager *fm=NSFileManager.defaultManager;
        void *handles[2]={NULL,NULL};
        @try {
            Directory(Root(NO,@"Tweaks"));Directory(Root(YES,@"Tweaks"));
            NSArray *names=@[@"A.dylib",@"B.dylib"];
            for(NSUInteger i=0;i<2;i++) {
                NSString *target=[Root(NO,@"Tweaks") stringByAppendingPathComponent:names[i]];
                NSCAssert([fm copyItemAtPath:[NSString stringWithUTF8String:argv[i+1]] toPath:target error:nil],@"fixture dylib copy");
                handles[i]=dlopen(target.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
                NSCAssert(handles[i]!=NULL,@"fixture dylib load");
            }
            Method copy=class_getInstanceMethod(NSFileManager.class,@selector(copyItemAtPath:toPath:error:));
            Method failedCopy=class_getInstanceMethod(NSFileManager.class,@selector(orbit_copyItemAtPath:toPath:error:));
            method_exchangeImplementations(copy,failedCopy);
            TestAutomaticSync(fm,suite);
            method_exchangeImplementations(copy,failedCopy);
            NSString *locked=Install(YES,@"Locked.app",@{@"isLocked":@YES});
            NSString *hidden=Install(NO,@"Hidden.app",@{@"isHidden":@YES});
            NSData *lockedBefore=Bytes([locked stringByAppendingPathComponent:@"LCAppInfo.plist"]);
            NSArray *inventory=[LCOrbitTweakSync pluginInventory];
            Check([Find(inventory,@"name",@"A.dylib")[@"canShare"] boolValue],@"loaded private plugin remains shareable");
            Check([Find(inventory,@"name",@"B.dylib")[@"canShare"] boolValue],@"second plugin remains batch-shareable");
            [LCOrbitTweakSync applyShare:YES names:names];
            for(NSString *name in names) Check([Bytes([Root(NO,@"Tweaks") stringByAppendingPathComponent:name]) isEqual:Bytes([Root(YES,@"Tweaks") stringByAppendingPathComponent:name])],[@"batch sharing preserves original bytes: " stringByAppendingString:name]);
            Check([lockedBefore isEqual:Bytes([locked stringByAppendingPathComponent:@"LCAppInfo.plist"])],@"global sharing never rewrites locked app configuration");
            Check([Find([LCOrbitTweakSync pluginInventory],@"name",@"A.dylib")[@"matches"] boolValue],@"shared inventory reports matching copy");
            [LCOrbitTweakSync applyShare:NO names:names];
            for(NSString *name in names) {
                Check(!Exists([Root(YES,@"Tweaks") stringByAppendingPathComponent:name]),[@"batch revocation removes only shared copy: " stringByAppendingString:name]);
                Check(Exists([Root(NO,@"Tweaks") stringByAppendingPathComponent:name]),[@"batch revocation keeps private original: " stringByAppendingString:name]);
            }
            NSString *historyRoot=[Group stringByAppendingPathComponent:@"LiveContainer/LCFloatingMenu/TweakBackups"];
            Check(!Exists(historyRoot),@"manual share and revoke do not create persistent history backups");
            Directory(historyRoot);NSString *historical=[historyRoot stringByAppendingPathComponent:@"existing.bak"];
            [@"keep historical file" writeToFile:historical atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [LCOrbitTweakSync applyShare:YES names:names];
            [LCOrbitTweakSync applyShare:NO names:@[@"B.dylib"]];
            Check([Bytes(historical) isEqual:[@"keep historical file" dataUsingEncoding:NSUTF8StringEncoding]] &&
                [fm contentsOfDirectoryAtPath:historyRoot error:nil].count==1,@"sharing never deletes historical backup files or adds new ones");
            [LCOrbitTweakSync applyShare:YES names:@[@"B.dylib"]];
            [LCOrbitTweakCenter setPlugin:@"A.dylib" enabled:NO shared:YES];
            Check(!Exists([Root(YES,@"Tweaks") stringByAppendingPathComponent:@"A.dylib"]) && Exists([Root(YES,@"Tweaks") stringByAppendingPathComponent:@"A.dylib.disabled"]),@"shared disable uses LC disabled suffix");
            Check([Find([LCOrbitTweakSync pluginInventory],@"name",@"A.dylib")[@"sharedDisabled"] boolValue],@"disabled plugin remains in management list");
            [LCOrbitTweakCenter setPlugin:@"A.dylib" enabled:YES shared:YES];
            Check([LCOrbitTweakCenter pluginInfo:@"A.dylib" shared:YES][@"enabled"]!=nil && [[LCOrbitTweakCenter pluginInfo:@"A.dylib" shared:YES][@"enabled"] boolValue],@"plugin re-enable and file info remain available");
            NSData *original=Bytes([Root(YES,@"Tweaks") stringByAppendingPathComponent:@"A.dylib"]);
            NSDictionary *details=[LCOrbitTweakCenter pluginInfo:@"A.dylib" shared:YES];
            Check([details[@"path"] hasSuffix:@"/LiveContainer/Tweaks/A.dylib"] && [details[@"size"] unsignedIntegerValue]==original.length,@"details report actual file path and size");
            NSString *privateJIT=Install(NO,@"JIT.app",@{@"isJITNeeded":@YES});
            NSString *sharedJIT=Install(YES,@"JIT.app",@{@"isJITNeeded":@YES});
            NSString *manual=Install(YES,@"Manual.app",@{@"dontSign":@YES});
            NSArray *guests=[LCOrbitTweakCenter guests];
            Check(Find(guests,@"folder",privateJIT)!=nil,@"private JIT guest remains assignable despite launch restriction");
            Check(Find(guests,@"folder",sharedJIT)!=nil,@"shared JIT namesake remains independently assignable");
            Check(Find(guests,@"folder",manual)!=nil,@"manual-signing guest remains in assignment list");
            Check(Find(guests,@"folder",locked)!=nil,@"locked app remains in assignment inventory");
            Check(Find(guests,@"folder",hidden)!=nil,@"hidden app remains in assignment inventory");
            NSArray *apps=[LCOrbitGuestService installedApps];
            for(NSString *folder in @[privateJIT,sharedJIT,manual,locked,hidden]) {
                NSDictionary *guest=Find(apps,@"folder",folder);
                if(guest) [LCOrbitTweakCenter assignPluginNames:@[@"A.dylib"] toGuest:guest];
                NSString *assigned=Info(folder)[@"LCTweakFolder"];
                Check([assigned hasPrefix:@"Orbit-"],[@"assignment persists for launch-blocked guest: " stringByAppendingString:folder.lastPathComponent]);
                BOOL shared=[folder hasPrefix:Group];
                NSString *copy=assigned?[[Root(shared,@"Tweaks") stringByAppendingPathComponent:assigned] stringByAppendingPathComponent:@"A.dylib"]:nil;
                Check(copy && [Bytes(copy) isEqual:Bytes([Root(shared,@"Tweaks") stringByAppendingPathComponent:@"A.dylib"])],@"assigned plugin uses correct scope and preserves bytes");
            }
            Check([Info(locked)[@"isLocked"] boolValue],@"plugin assignment never clears the LC lock flag");
            Check([Info(hidden)[@"isHidden"] boolValue],@"plugin assignment never clears the LC hidden flag");
            Check(![LCOrbitGuestService isEligibleGuestPath:@"Locked.app" uuid:@"Locked.app"],@"assigning plugins never grants a locked app launch permission");
            Check(![Info(privateJIT)[@"LCTweakFolder"] isEqual:Info(sharedJIT)[@"LCTweakFolder"]],@"private and shared same-name guests have distinct managed folders");
            Check(![LCOrbitGuestService isEligibleGuestPath:@"JIT.app" uuid:@"JIT.app"],@"plugin management does not bypass JIT launch checks");
            NSDictionary *privateGuest=Find([LCOrbitGuestService installedApps],@"folder",privateJIT);
            if(privateGuest) [LCOrbitTweakCenter assignPluginNames:@[] toGuest:privateGuest];
            Check(Info(privateJIT)[@"LCTweakFolder"]==nil,@"clearing an assignment works for JIT guest");
            Check([Info(sharedJIT)[@"LCTweakFolder"] hasPrefix:@"Orbit-"],@"clearing private assignment preserves shared namesake");
            NSString *configured=Install(NO,@"Existing.app",@{@"LCTweakFolder":@"UserFolder"});
            NSData *before=Bytes([configured stringByAppendingPathComponent:@"LCAppInfo.plist"]);
            NSDictionary *existing=Find([LCOrbitGuestService installedApps],@"folder",configured);
            if(existing) [LCOrbitTweakCenter assignPluginNames:@[@"B.dylib"] toGuest:existing];
            Check([before isEqual:Bytes([configured stringByAppendingPathComponent:@"LCAppInfo.plist"])],@"existing user-selected folder is never overwritten");
            HostMode=NO;
            Check([LCOrbitTweakCenter guests].count==0 && [LCOrbitTweakSync pluginInventory].count==0,@"file management remains restricted to opted-in host UI");
        } @catch(NSException *error) { Check(NO,[@"unexpected fixture exception: " stringByAppendingString:error.description]); }
        @finally {
            for(NSUInteger i=0;i<2;i++) if(handles[i]) dlclose(handles[i]);
            [fm removeItemAtPath:temp error:nil];[Defaults removePersistentDomainForName:suite];
        }
        printf("Tweak center behavior: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
