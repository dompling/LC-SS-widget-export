#import <Foundation/Foundation.h>
#import "LCOrbitLog.h"
#import "LCOrbitStorage.h"
#import "LCOrbitHost.h"

static NSString *Home, *Group;
static NSUInteger Assertions, Failures;
@implementation LCOrbitStorage
+ (NSString *)rootPath { return [Home stringByAppendingPathComponent:@"Documents/LCOrbit"]; }
+ (NSString *)key:(NSString *)key forModule:(NSString *)module { return @""; }
+ (id)objectForKey:(NSString *)key module:(NSString *)module { return nil; }
+ (void)setObject:(id)object forKey:(NSString *)key module:(NSString *)module { }
@end
@implementation LCOrbitHost
+ (NSString *)appGroupPath { return Group; }
+ (NSUserDefaults *)hostDefaults { return NSUserDefaults.standardUserDefaults; }
+ (NSDictionary *)guestInfo { return nil; }
+ (NSString *)guestIdentifier { return @"test.host"; }
+ (UIWindowScene *)activeScene { return nil; }
+ (BOOL)isHostUI { return YES; }
+ (BOOL)isSupportedGuest { return NO; }
@end
static void Check(BOOL ok,NSString *message) {
    Assertions++;if(!ok) {Failures++;fprintf(stderr,"FAIL: %s\n",message.UTF8String);}
}
static NSDictionary *Read(id logger,NSString *kind) {
    return [NSJSONSerialization JSONObjectWithData:[logger dataForKind:kind] options:0 error:nil];
}
static NSString *LogPath(id logger,NSString *kind) { return [logger pathForKind:kind]; }
static void Write(NSString *path,NSString *value) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [value writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
int main(int argc,const char **argv) { @autoreleasepool {
    id logger=NSClassFromString(@"LCOrbitLog");
    if(argc==3) {
        Home=@(argv[1]);Group=[Home stringByAppendingPathComponent:@"group"];
        for(int index=0;index<30;index++) [logger appendEvent:@"child" details:@(index) kind:@"runtime"];
        return 0;
    }
    Home=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"orbit-log-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    Group=[Home stringByAppendingPathComponent:@"group"];setenv("LC_HOME_PATH",Home.UTF8String,1);
    Check(logger!=nil,@"structured log service exists");if(!logger) return 1;
    NSString *legacy=[Group stringByAppendingPathComponent:@"LiveContainer/LCFloatingMenu/diagnostics.log"];
    Write([legacy stringByAppendingString:@".old"],@"older line\n");Write(legacy,@"legacy line\n");
    NSString *escaped=@"quote \" newline\n中文 \\ slash";
    [logger appendEvent:@"test" details:@{@"text":escaped} kind:@"runtime"];
    NSDictionary *document=Read(logger,@"runtime");NSArray *events=document[@"events"];
    Check([document[@"schemaVersion"] integerValue]==1 && [events isKindOfClass:NSArray.class],@"export is one schema-versioned JSON document");
    Check([events.lastObject[@"details"][@"text"] isEqual:escaped],@"JSON preserves escaped and Unicode details");
    Check([events.lastObject[@"timestamp"] length]>0 && [events.lastObject[@"guestID"] isEqual:@"test.host"],@"events include timestamp and process context");
    Check([[events description] containsString:@"legacy line"] && [[events description] containsString:@"older line"],@"legacy current and rotated history is imported");
    NSUInteger initial=events.count;[logger dataForKind:@"runtime"];
    Check([Read(logger,@"runtime")[@"events"] count]==initial,@"repeated export does not import history twice");
    Check([NSFileManager.defaultManager fileExistsAtPath:legacy],@"legacy originals remain recoverable");
    NSString *longHistory=[@"start\n" stringByPaddingToLength:160000 withString:@"history 中文\n" startingAtIndex:0];
    Write([legacy.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"tweaks.log"],longHistory);
    NSMutableString *imported=[NSMutableString string];
    for(NSDictionary *entry in Read(logger,@"tweaks")[@"events"])
        if([entry[@"event"] isEqual:@"legacy-import"]) [imported appendString:entry[@"details"][@"text"]?:@""];
    Check([imported isEqual:longHistory],@"legacy import preserves complete bounded UTF-8 history");
    [logger clearKind:@"tweaks"];
    [logger clearKind:@"runtime"];
    Check([Read(logger,@"runtime")[@"events"] count]==0,@"clear removes history without reimporting legacy");
    [logger appendEvent:@"after-clear" details:nil kind:@"runtime"];
    Check([Read(logger,@"runtime")[@"events"] count]==1,@"new events start fresh after clear");
    dispatch_apply(32,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t index) {
        [logger appendEvent:@"concurrent" details:@(index) kind:@"runtime"];
    });
    Check([Read(logger,@"runtime")[@"events"] count]==33,@"concurrent threads do not lose records");
    NSMutableArray<NSTask *> *tasks=[NSMutableArray array];
    for(int index=0;index<3;index++) {
        NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@(argv[0])];
        task.arguments=@[Home,@"worker"];[task launchAndReturnError:nil];[tasks addObject:task];
    }
    for(NSTask *task in tasks) [task waitUntilExit];
    Check([Read(logger,@"runtime")[@"events"] count]==123,@"separate processes do not lose records");
    [logger clearKind:@"runtime"];
    NSString *large=[@"x" stringByPaddingToLength:16000 withString:@"x" startingAtIndex:0];
    for(int index=0;index<50;index++) [logger appendEvent:@"large" details:large kind:@"runtime"];
    NSString *file=LogPath(logger,@"runtime"),*old=[file.stringByDeletingPathExtension stringByAppendingString:@".old.json"];
    Check([[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil] fileSize]<=262144,@"current JSON file stays within size limit");
    Check([[NSFileManager.defaultManager attributesOfItemAtPath:old error:nil] fileSize]<=262144 &&
        [NSFileManager.defaultManager fileExistsAtPath:old],@"rotated JSON file stays bounded");
    Check([Read(logger,@"runtime")[@"events"] count]>1,@"rotated export remains valid JSON with history");
    [logger appendEvent:@"oversized" details:[large stringByPaddingToLength:500000 withString:large startingAtIndex:0] kind:@"runtime"];
    Check([[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil] fileSize]<=262144,@"oversized event cannot grow log without bound");
    Write(file,@"{broken");[logger appendEvent:@"recovered" details:nil kind:@"runtime"];
    Check([Read(logger,@"runtime")[@"events"] isKindOfClass:NSArray.class],@"malformed current file recovers to parseable JSON");
    NSDictionary *last=[[Read(logger,@"runtime") objectForKey:@"events"] lastObject];
    Check([last[@"event"] isEqual:@"recovered"],@"recovery retains new event");
    Check(LogPath(logger,@"../escape")==nil,@"invalid log kinds cannot escape storage root");
    [logger appendEvent:@"independent" details:nil kind:@"tweaks"];
    [logger clearKind:@"runtime"];
    Check(![NSFileManager.defaultManager fileExistsAtPath:[file.stringByDeletingPathExtension stringByAppendingString:@".corrupt.json"]],@"clear also removes quarantined JSON history");
    Check([Read(logger,@"tweaks")[@"events"] count]==1,@"clearing runtime leaves tweak log intact");
    NSString *root=[LCOrbitStorage rootPath];
    NSString *outside=[Home stringByAppendingPathComponent:@"unrelated"];
    [NSFileManager.defaultManager createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager moveItemAtPath:root toPath:[root stringByAppendingString:@"-saved"] error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:root withDestinationPath:outside error:nil];
    [logger appendEvent:@"redirected" details:nil kind:@"runtime"];[logger dataForKind:@"runtime"];
    NSString *outsideLogs=[outside stringByAppendingPathComponent:@"logs"];
    Check(![NSFileManager.defaultManager fileExistsAtPath:outsideLogs],@"symlinked LCOrbit root cannot redirect log creation or export");
    NSString *sentinel=[outsideLogs stringByAppendingPathComponent:@"runtime.json"];
    Write(sentinel,@"keep unrelated bytes");[logger clearKind:@"runtime"];
    Check([[NSString stringWithContentsOfFile:sentinel encoding:NSUTF8StringEncoding error:nil] isEqual:@"keep unrelated bytes"],@"clearing logs cannot follow root symlink into unrelated files");
    [NSFileManager.defaultManager removeItemAtPath:Home error:nil];
    fprintf(stdout,"JSON log behavior: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
    return Failures?1:0;
} }
