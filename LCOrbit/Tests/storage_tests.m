#import <Foundation/Foundation.h>
#import "LCOrbitStorage.h"
#import "LCOrbitHost.h"

@interface LCOrbitStorage (StorageContract)
+ (id)preferences;
+ (NSString *)rootPath;
+ (BOOL)reloadWithError:(NSError **)error;
+ (NSError *)lastError;
+ (void)beginReadSnapshot:(NSDictionary *)values;
+ (void)endReadSnapshot;
@end
static NSUserDefaults *Legacy;
static NSUInteger Assertions,Failures;
@implementation LCOrbitHost
+ (NSUserDefaults *)hostDefaults { return Legacy; }
+ (BOOL)isHostUI { return YES; }
+ (NSString *)appGroupPath { return nil; }
+ (NSDictionary *)guestInfo { return nil; }
+ (NSString *)guestIdentifier { return @"storage.test"; }
+ (UIWindowScene *)activeScene { return nil; }
+ (BOOL)isSupportedGuest { return NO; }
@end
static void Expect(BOOL condition,NSString *name) {
    Assertions++;if(!condition) { Failures++;fprintf(stderr,"FAIL: %s\n",name.UTF8String); }
}
static NSDictionary *Document(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
}
static void Write(NSString *path,id document) {
    [[NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted error:nil]
        writeToFile:path atomically:YES];
}
static void TestReadSnapshots(NSString *home,NSString *file,id prefs) {
    BOOL available=[LCOrbitStorage respondsToSelector:@selector(beginReadSnapshot:)] &&
        [LCOrbitStorage respondsToSelector:@selector(endReadSnapshot)];
    Expect(available,@"event-scoped preference reads are available");
    if(!available) return;
    NSData *original=[NSData dataWithContentsOfFile:file];
    NSString *key=@"LCFloatingMenu.snapshot",*other=@"LCFloatingMenu.external";
    [prefs setObject:@"disk" forKey:key];
    NSMutableDictionary *supplied=[[prefs dictionaryRepresentation] mutableCopy];
    supplied[key]=@"outer";
    [LCOrbitStorage beginReadSnapshot:supplied];
    supplied[key]=@"caller-mutated";
    Expect([[prefs objectForKey:key] isEqual:@"outer"],@"supplied snapshot copies its caller's dictionary");
    [Legacy setInteger:2 forKey:@"LCMultitaskMode"];
    Expect([prefs integerForKey:@"LCMultitaskMode"]==2,@"scoped reads keep native preferences delegated to LC");
    NSMutableDictionary *external=[Document(file)[@"preferences"] mutableCopy];
    external[key]=@"external";external[other]=@"preserved";
    Write(file,@{@"schemaVersion":@1,@"preferences":external});
    Expect([[prefs objectForKey:key] isEqual:@"outer"],@"scope keeps external edits out of an in-progress event");
    __block BOOL isolated=NO;
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        isolated=[[prefs objectForKey:key] isEqual:@"external"];
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
    Expect(isolated,@"read snapshots stay on their owning thread");
    [LCOrbitStorage beginReadSnapshot:@{key:@"inner"}];
    Expect([[prefs objectForKey:key] isEqual:@"inner"],@"nested explicit snapshot controls its own reads");
    [prefs setObject:@"written" forKey:key];
    Expect([[prefs objectForKey:key] isEqual:@"written"] &&
        [[prefs objectForKey:other] isEqual:@"preserved"],@"scope writes merge fresh disk values and refresh the inner snapshot");
    [LCOrbitStorage endReadSnapshot];
    Expect([[prefs objectForKey:key] isEqual:@"written"],@"successful writes refresh every same-root nested snapshot");
    [prefs removeObjectForKey:key];
    Expect([prefs objectForKey:key]==nil && Document(file)[@"preferences"][key]==nil,@"scope deletion updates the snapshot after durable removal");
    [prefs setObject:@"stable" forKey:key];
    [prefs setObject:@"invalid" forKey:@"LCFloatingMenu.idleAlpha"];
    Expect([LCOrbitStorage lastError]!=nil && [[prefs objectForKey:key] isEqual:@"stable"] &&
        [LCOrbitStorage lastError]!=nil,@"scoped reads retain validation errors from failed writes");
    [@"broken scoped JSON" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [prefs setObject:@"rejected" forKey:key];
    Expect([LCOrbitStorage lastError]!=nil && [[prefs objectForKey:key] isEqual:@"stable"],@"failed disk validation leaves the scoped value unchanged");
    NSError *error=nil;
    Expect(![LCOrbitStorage reloadWithError:&error] && error!=nil &&
        [[prefs objectForKey:key] isEqual:@"stable"],@"explicit invalid reload bypasses the scope but keeps its prior values");
    external[key]=@"reloaded";
    Write(file,@{@"schemaVersion":@1,@"preferences":external});
    [LCOrbitStorage beginReadSnapshot:@{key:@"nested stale"}];
    Expect([LCOrbitStorage reloadWithError:nil] && [[prefs objectForKey:key] isEqual:@"reloaded"],@"valid explicit reload refreshes the inner scope");
    [LCOrbitStorage endReadSnapshot];
    Expect([[prefs objectForKey:key] isEqual:@"reloaded"],@"valid explicit reload refreshes the outer scope");
    external[key]=@"nested-disk";
    Write(file,@{@"schemaVersion":@1,@"preferences":external});
    [LCOrbitStorage beginReadSnapshot:nil];
    Expect([[prefs objectForKey:key] isEqual:@"nested-disk"],@"nil nested snapshot reads the current disk configuration");
    [LCOrbitStorage endReadSnapshot];
    Expect([[prefs objectForKey:key] isEqual:@"reloaded"],@"ending a nested scope restores its outer event values");
    NSString *secondHome=[home stringByAppendingPathComponent:@"second-home"];
    setenv("LC_HOME_PATH",secondHome.UTF8String,1);
    [prefs setObject:@"second-root" forKey:key];
    Expect([[prefs objectForKey:key] isEqual:@"second-root"],@"an unrelated root never uses a scoped root's values");
    [LCOrbitStorage beginReadSnapshot:nil];
    [prefs setObject:@"second-written" forKey:key];
    setenv("LC_HOME_PATH",home.UTF8String,1);
    Expect([[prefs objectForKey:key] isEqual:@"reloaded"],@"writes update only snapshots for their current root");
    [LCOrbitStorage endReadSnapshot];
    [LCOrbitStorage endReadSnapshot];
    external[key]=@"after-event";
    Write(file,@{@"schemaVersion":@1,@"preferences":external});
    Expect([[prefs objectForKey:key] isEqual:@"after-event"],@"ending a scope restores fresh external reads");
    [LCOrbitStorage endReadSnapshot]; // An unmatched cleanup must not create a lingering scope.
    [original writeToFile:file atomically:YES];
    [LCOrbitStorage reloadWithError:nil];
}
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc>=5) {
        NSString *mode=@(argv[1]);
        Legacy=[[NSUserDefaults alloc] initWithSuiteName:[@"orbit.storage.child." stringByAppendingString:NSUUID.UUID.UUIDString]];
        setenv("LC_HOME_PATH",argv[2],1);
        id prefs=[LCOrbitStorage preferences];NSString *key=@(argv[3]),*value=@(argv[4]);
        if([mode isEqual:@"--write"]) { [prefs setObject:value forKey:key];return [LCOrbitStorage lastError]?1:0; }
        return [[[prefs objectForKey:key] description] isEqual:value]?0:1;
    }
    NSString *home=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *suite=[@"orbit.storage.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    Legacy=[[NSUserDefaults alloc] initWithSuiteName:suite];
    setenv("LC_HOME_PATH",home.UTF8String,1);
    [Legacy setObject:@[@"private/A.app"] forKey:@"LCFloatingMenu.favoritePaths"];
    [Legacy setObject:@[@"shared/B.app",@"private/A.app"] forKey:@"LCFloatingMenu.menuOrder"];
    [Legacy setBool:YES forKey:@"LCFloatingMenu.autoSyncSharedTweaks"];
    [Legacy setDouble:.4 forKey:@"LCFloatingMenu.appAlpha.test.app"];
    [Legacy setBool:NO forKey:@"LCOrbit.module.FloatingMenu.enabled"];
    [Legacy setObject:@"Aurora" forKey:@"LCFloatingMenu.theme"];
    [Legacy setInteger:1 forKey:@"LCMultitaskMode"];
    [Legacy setObject:@"not-for-export" forKey:@"LCCertificatePassword"];
    [Legacy setInteger:1 forKey:@"LCFloatingMenu.previousMultitaskMode"];
    Expect([LCOrbitStorage respondsToSelector:@selector(preferences)],@"JSON preferences facade exists");
    if(Failures) return 1;
    id prefs=[LCOrbitStorage preferences];
    NSString *file=[[LCOrbitStorage rootPath] stringByAppendingPathComponent:@"config.json"];
    Expect([[prefs arrayForKey:@"LCFloatingMenu.favoritePaths"] isEqual:@[@"private/A.app"]],@"migrates favorites without changing identity");
    Expect([prefs boolForKey:@"LCFloatingMenu.autoSyncSharedTweaks"] && [prefs doubleForKey:@"LCFloatingMenu.appAlpha.test.app"]==.4,@"migrates automatic sync and per-app preferences");
    NSDictionary *doc=Document(file), *values=doc[@"preferences"];
    Expect([doc[@"schemaVersion"] integerValue]==1 && values.count==6,@"writes versioned plugin-only JSON");
    Expect([values[@"LCFloatingMenu.theme"] isEqual:@"Aurora"],@"historical plugin values remain readable after migration");
    Expect(values[@"LCCertificatePassword"]==nil && values[@"LCMultitaskMode"]==nil && values[@"LCFloatingMenu.previousMultitaskMode"]==nil,@"does not export secrets/native settings/recovery snapshots");
    Expect([Legacy objectForKey:@"LCFloatingMenu.favoritePaths"]!=nil,@"migration leaves legacy recovery data intact");
    [prefs removeObjectForKey:@"LCFloatingMenu.favoritePaths"];
    [LCOrbitStorage reloadWithError:nil];
    Expect([prefs objectForKey:@"LCFloatingMenu.favoritePaths"]==nil,@"deleting JSON key does not resurrect legacy value");
    [prefs setBool:NO forKey:@"LCFloatingMenu.autoSyncSharedTweaks"];
    Expect(![Document(file)[@"preferences"][@"LCFloatingMenu.autoSyncSharedTweaks"] boolValue],@"setter persists JSON immediately");
    NSMutableDictionary *external=[Document(file)[@"preferences"] mutableCopy];
    external[@"LCFloatingMenu.idleAlpha"]=@.23;
    external[@"LCFloatingMenu.orbHandleReach"]=@31;
    external[@"LCFloatingMenu.orbGlowBrightness"]=@.22;
    Write(file,@{@"schemaVersion":@1,@"preferences":external});
    Expect([LCOrbitStorage reloadWithError:nil] && [prefs doubleForKey:@"LCFloatingMenu.idleAlpha"]==.23,@"valid external JSON changes become effective");
    Expect([prefs doubleForKey:@"LCFloatingMenu.orbHandleReach"]==31 && [prefs doubleForKey:@"LCFloatingMenu.orbGlowBrightness"]==.22,@"orb style settings reload from JSON");
    NSString *executable=NSProcessInfo.processInfo.arguments.firstObject;
    NSTask *fresh=[NSTask new];fresh.executableURL=[NSURL fileURLWithPath:executable];
    fresh.arguments=@[@"--read",home,@"LCFloatingMenu.idleAlpha",@"0.23"];
    [fresh launchAndReturnError:nil];[fresh waitUntilExit];
    Expect(fresh.terminationStatus==0,@"fresh process reads JSON without legacy preferences");
    NSData *valid=[NSData dataWithContentsOfFile:file];
    [@"broken JSON" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSError *error=nil;
    Expect(![LCOrbitStorage reloadWithError:&error] && error!=nil,@"invalid JSON is reported");
    Expect([prefs doubleForKey:@"LCFloatingMenu.idleAlpha"]==.23,@"invalid JSON preserves last-known-good values");
    fresh=[NSTask new];fresh.executableURL=[NSURL fileURLWithPath:executable];
    fresh.arguments=@[@"--read",home,@"LCFloatingMenu.idleAlpha",@"0.23"];
    [fresh launchAndReturnError:nil];[fresh waitUntilExit];
    Expect(fresh.terminationStatus==0,@"fresh process recovers last-known-good backup after corrupt external edit");
    [prefs setBool:YES forKey:@"LCFloatingMenu.autoSyncSharedTweaks"];
    Expect([[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] isEqual:@"broken JSON"],@"ordinary setters do not overwrite invalid config");
    Expect([LCOrbitStorage lastError]!=nil,@"failed setter exposes diagnostic error");
    [valid writeToFile:file atomically:YES];
    external=[Document(file)[@"preferences"] mutableCopy];
    external[@"LCFloatingMenu.idleAlpha"]=@"wrong type";
    Write(file,@{@"schemaVersion":@1,@"preferences":external});
    Expect(![LCOrbitStorage reloadWithError:nil] && [prefs doubleForKey:@"LCFloatingMenu.idleAlpha"]==.23,@"wrong preference types cannot replace working config");
    Write(file,@{@"schemaVersion":@99,@"preferences":@{}});
    Expect(![LCOrbitStorage reloadWithError:nil],@"future schema is rejected without overwriting");
    [valid writeToFile:file atomically:YES];
    [LCOrbitStorage reloadWithError:nil];
    dispatch_apply(20,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i) {
        [prefs setObject:@(i) forKey:[NSString stringWithFormat:@"LCFloatingMenu.parallel.%zu",i]];
    });
    values=Document(file)[@"preferences"];
    BOOL retained=YES;
    for(NSUInteger i=0;i<20;i++) if(![values[[NSString stringWithFormat:@"LCFloatingMenu.parallel.%lu",(unsigned long)i]] isEqual:@(i)]) retained=NO;
    Expect(retained,@"concurrent read-modify-write preserves every independent key");
    NSMutableArray<NSTask *> *writers=[NSMutableArray array];
    for(NSUInteger i=0;i<8;i++) {
        NSTask *writer=[NSTask new];writer.executableURL=[NSURL fileURLWithPath:executable];
        writer.arguments=@[@"--write",home,[NSString stringWithFormat:@"LCFloatingMenu.process.%lu",(unsigned long)i],@"written"];
        [writers addObject:writer];[writer launchAndReturnError:nil];
    }
    BOOL completed=YES;
    for(NSTask *writer in writers) { [writer waitUntilExit];completed=completed && writer.terminationStatus==0; }
    values=Document(file)[@"preferences"];
    for(NSUInteger i=0;i<8;i++) completed=completed && [values[[NSString stringWithFormat:@"LCFloatingMenu.process.%lu",(unsigned long)i]] isEqual:@"written"];
    Expect(completed,@"separate processes merge writes without dropping independent keys");
    [prefs objectForKey:@"LCFloatingMenu.idleAlpha"]; // Keep this process warm before another writer.
    NSTask *latest=[NSTask new];latest.executableURL=[NSURL fileURLWithPath:executable];
    latest.arguments=@[@"--write",home,@"LCFloatingMenu.crossprocess",@"latest"];
    [latest launchAndReturnError:nil];[latest waitUntilExit];
    [@"broken after child write" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Expect([[prefs objectForKey:@"LCFloatingMenu.crossprocess"] isEqual:@"latest"],@"warm process recovery prefers newer shared backup over stale memory");
    [NSFileManager.defaultManager removeItemAtPath:file error:nil];
    [prefs objectForKey:@"LCFloatingMenu.crossprocess"];
    Expect([Document(file)[@"preferences"][@"LCFloatingMenu.crossprocess"] isEqual:@"latest"],@"missing-file recovery preserves another process's durable update");
    NSData *beforeLink=[NSData dataWithContentsOfFile:file];
    NSString *outside=[home stringByAppendingPathComponent:@"unrelated.json"];
    [@"untouched" writeToFile:outside atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [NSFileManager.defaultManager removeItemAtPath:file error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:file withDestinationPath:outside error:nil];
    [prefs setBool:YES forKey:@"LCFloatingMenu.autoSyncSharedTweaks"];
    Expect([LCOrbitStorage lastError]!=nil && [[NSString stringWithContentsOfFile:outside encoding:NSUTF8StringEncoding error:nil] isEqual:@"untouched"],@"config symlink cannot overwrite unrelated file");
    [NSFileManager.defaultManager removeItemAtPath:file error:nil];
    [beforeLink writeToFile:file atomically:YES];
    [prefs setInteger:0 forKey:@"LCMultitaskMode"];
    Expect([Legacy integerForKey:@"LCMultitaskMode"]==0 && Document(file)[@"preferences"][@"LCMultitaskMode"]==nil,@"native keys stay delegated to native defaults");
    TestReadSnapshots(home,file,prefs);
    Write(file,@{@"schemaVersion":@1,@"preferences":@{@"LCMultitaskMode":@1}});
    Expect(![LCOrbitStorage reloadWithError:nil],@"external JSON cannot import native keys");
    NSMutableData *oversized=[NSMutableData dataWithLength:1048577];
    [oversized writeToFile:file atomically:YES];
    Expect(![LCOrbitStorage reloadWithError:nil] && [prefs doubleForKey:@"LCFloatingMenu.idleAlpha"]==.23,@"oversized config cannot displace effective preferences");
    BOOL beforeUnavailable=[prefs boolForKey:@"LCFloatingMenu.autoSyncSharedTweaks"];
    BOOL legacyBeforeUnavailable=[Legacy boolForKey:@"LCFloatingMenu.autoSyncSharedTweaks"];
    NSString *root=[LCOrbitStorage rootPath],*redirect=[home stringByAppendingPathComponent:@"redirect"];
    [NSFileManager.defaultManager createDirectoryAtPath:redirect withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager moveItemAtPath:root toPath:[root stringByAppendingString:@"-saved"] error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:root withDestinationPath:redirect error:nil];
    Expect([prefs boolForKey:@"LCFloatingMenu.autoSyncSharedTweaks"]==beforeUnavailable,@"temporarily unsafe root preserves warm configuration instead of stale legacy defaults");
    [prefs setBool:!beforeUnavailable forKey:@"LCFloatingMenu.autoSyncSharedTweaks"];
    Expect([LCOrbitStorage lastError]!=nil && [Legacy boolForKey:@"LCFloatingMenu.autoSyncSharedTweaks"]==legacyBeforeUnavailable,@"failed warm save does not mutate legacy fallback behind JSON configuration");
    [NSFileManager.defaultManager removeItemAtPath:home error:nil];
    [Legacy removePersistentDomainForName:suite];
    fprintf(stdout,"JSON preference behavior: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
    return Failures?1:0;
} }
