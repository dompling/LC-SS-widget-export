#import <Foundation/Foundation.h>
#import "LCOrbitStorage.h"
#import "LCOrbitHost.h"
#import "LCOrbitGuestService.h"
#import "LCOrbitMultitask.h"

@interface LCOrbitStorage (SnapshotContract)
+ (void)beginReadSnapshot:(NSDictionary *)values;
+ (void)endReadSnapshot;
@end

static NSUserDefaults *Defaults;
static NSUInteger Assertions,Failures;
extern NSUInteger OrbitTestDiskLoads;
@implementation LCOrbitHost
+ (NSUserDefaults *)hostDefaults { return Defaults; }
+ (BOOL)isHostUI { return YES; }
+ (NSString *)appGroupPath { return nil; }
+ (NSDictionary *)guestInfo { return nil; }
+ (NSString *)guestIdentifier { return @"storage.status.test"; }
+ (UIWindowScene *)activeScene { return nil; }
+ (BOOL)isSupportedGuest { return NO; }
@end
static void Expect(BOOL condition,NSString *name) {
    Assertions++;
    if(!condition) { Failures++;fprintf(stderr,"FAIL: %s\n",name.UTF8String); }
}
static BOOL RenderRowStatuses(NSDictionary *app) {
    BOOL unchanged=YES;
    for(NSUInteger row=0;row<50;row++) {
        // A noncurrent standard row asks for current state in its icon, visible
        // title and caption, enabled state, and accessibility caption.
        for(NSUInteger query=0;query<5;query++) unchanged=![LCOrbitGuestService isCurrentGuest:app] && unchanged;
        unchanged=![LCOrbitMultitask isRunningGuest:app] && unchanged;
    }
    return unchanged;
}
int main(void) { @autoreleasepool {
    NSString *home=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *suite=[@"orbit.storage.status." stringByAppendingString:NSUUID.UUID.UUIDString];
    Defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
    setenv("LC_HOME_PATH",home.UTF8String,1);
    NSFileManager *fm=NSFileManager.defaultManager;
    [fm createDirectoryAtPath:[LCOrbitStorage rootPath] withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableDictionary *values=[@{@"LCFloatingMenu.fullscreenMultitask":@YES} mutableCopy];
    for(NSUInteger i=0;i<100;i++) values[[NSString stringWithFormat:@"LCFloatingMenu.status.%lu",(unsigned long)i]]=@"representative configuration value";
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"schemaVersion":@1,@"preferences":values} options:0 error:nil];
    NSString *file=[[LCOrbitStorage rootPath] stringByAppendingPathComponent:@"config.json"];
    [data writeToFile:file atomically:YES];
    [LCOrbitStorage reloadWithError:nil];
    NSDictionary *app=@{@"path":@"A.app",@"uuid":@"A",@"folder":home};
    OrbitTestDiskLoads=0;CFTimeInterval start=NSDate.timeIntervalSinceReferenceDate;
    Expect(RenderRowStatuses(app),@"unscoped real status APIs preserve nonrunning app state");
    NSUInteger unscoped=OrbitTestDiskLoads;
    double unscopedMS=(NSDate.timeIntervalSinceReferenceDate-start)*1000;
    Expect(unscoped>1000,@"regression fixture exposes repeated physical storage loads without a scope");
    BOOL available=[LCOrbitStorage respondsToSelector:@selector(beginReadSnapshot:)] &&
        [LCOrbitStorage respondsToSelector:@selector(endReadSnapshot)];
    OrbitTestDiskLoads=0;start=NSDate.timeIntervalSinceReferenceDate;
    if(available) [LCOrbitStorage beginReadSnapshot:nil];
    Expect(RenderRowStatuses(app),@"scoped real status APIs preserve nonrunning app state");
    NSUInteger scoped=OrbitTestDiskLoads;
    double scopedMS=(NSDate.timeIntervalSinceReferenceDate-start)*1000;
    Expect(scoped==1,@"50 rows use one physical storage load inside an event scope");
    if(available) [LCOrbitStorage endReadSnapshot];
    if(available) {
        OrbitTestDiskLoads=0;
        [LCOrbitStorage beginReadSnapshot:values];
        Expect(RenderRowStatuses(app) && OrbitTestDiskLoads==0,@"a supplied event snapshot avoids all physical status-query loads");
        [LCOrbitStorage endReadSnapshot];
        OrbitTestDiskLoads=0;
        (void)[LCOrbitMultitask isEnabled];
        Expect(OrbitTestDiskLoads==2,@"status queries resume fresh physical reads after the event");
    }
    fprintf(stdout,"Status workload: unscoped=%lu loads %.3fms; scoped=%lu loads %.3fms\n",
        (unsigned long)unscoped,unscopedMS,(unsigned long)scoped,scopedMS);
    fprintf(stdout,"Storage status behavior: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
    [fm removeItemAtPath:home error:nil];
    [Defaults removePersistentDomainForName:suite];
    return Failures?1:0;
} }
