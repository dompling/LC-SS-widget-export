#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/loader.h>
#import <mach/machine.h>
#import <stdbool.h>
#import <stdlib.h>
#import <string.h>
#import "../Core/LCOrbitPluginUpdater.h"
#import "../Core/LCOrbitHost.h"

static BOOL Host=YES,HasCert=YES,SignerSuccess=YES,VerifySuccess=YES,RestartAccepted=YES;
static BOOL RestartTargetSafe=NO;
static NSUInteger Calls=0,RestartCalls=0,Assertions=0,Failures=0;
static NSString *Destination;

@implementation LCOrbitHost
+ (BOOL)isHostUI { return Host; }
+ (NSUserDefaults *)hostDefaults { return NSUserDefaults.standardUserDefaults; }
@end

@interface LCUtils : NSObject
+ (NSData *)certificateData;
+ (NSProgress *)signFilesWithZSignWithURLs:(NSArray<NSURL *> *)urls
                        completionHandler:(void (^)(BOOL,NSError *))done;
@end
@implementation LCUtils
+ (NSData *)certificateData { return HasCert?[@"fixture-certificate" dataUsingEncoding:NSUTF8StringEncoding]:nil; }
+ (NSProgress *)signFilesWithZSignWithURLs:(NSArray<NSURL *> *)urls
                        completionHandler:(void (^)(BOOL,NSError *))done {
    Calls++;
    if(!SignerSuccess) {
        done(NO,[NSError errorWithDomain:@"FakeSigner" code:1 userInfo:@{NSLocalizedDescriptionKey:@"fixture refused signature"}]);
        return nil;
    }
    NSMutableData *data=[[NSData dataWithContentsOfURL:urls.firstObject] mutableCopy];
    [data appendData:[@"SIGNED" dataUsingEncoding:NSUTF8StringEncoding]];
    BOOL written=[data writeToURL:urls.firstObject atomically:YES];
    done(written,written?nil:[NSError errorWithDomain:@"FakeSigner" code:2 userInfo:nil]);
    return nil;
}
@end

@interface LCSharedUtils : NSObject
+ (NSString *)certificatePassword;
+ (BOOL)launchToGuestAppWithClassicMode:(NSUInteger)classicMode;
@end
@implementation LCSharedUtils
+ (NSString *)certificatePassword { return HasCert?@"fixture-password":nil; }
+ (BOOL)launchToGuestAppWithClassicMode:(NSUInteger)classicMode {
    RestartCalls++;
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    RestartTargetSafe=classicMode==0 &&
        [[defaults stringForKey:@"selected"] isEqualToString:@"ui"] &&
        [defaults objectForKey:@"selectedContainer"]==nil &&
        [defaults objectForKey:@"launchAppUrlScheme"]==nil &&
        ![defaults boolForKey:@"LCOpenSideStore"];
    return RestartAccepted;
}
@end

// Exported by the dedicated fixture executable: equivalent contract to LC's
// main-app checkCodeSignature symbol, not a real signing trust assertion.
bool checkCodeSignature(const char *path) {
    NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];
    NSData *tail=[@"SIGNED" dataUsingEncoding:NSUTF8StringEncoding];
    if(!VerifySuccess || data.length<tail.length) return false;
    return [[data subdataWithRange:NSMakeRange(data.length-tail.length,tail.length)] isEqual:tail];
}

static NSData *MakePlugin(void) {
    const char *name="@rpath/LCFloatingMenu.dylib";
    NSUInteger cmdsize=(sizeof(struct dylib_command)+strlen(name)+1+7)&~(NSUInteger)7;
    NSMutableData *data=[NSMutableData dataWithLength:sizeof(struct mach_header_64)+cmdsize+32];
    char *bytes=data.mutableBytes;
    struct mach_header_64 *header=(void *)bytes;
    header->magic=MH_MAGIC_64;
    header->cputype=CPU_TYPE_ARM64;
    header->cpusubtype=CPU_SUBTYPE_ARM64_ALL;
    header->filetype=MH_DYLIB;
    header->ncmds=1;
    header->sizeofcmds=(uint32_t)cmdsize;
    struct dylib_command *command=(void *)(bytes+sizeof(*header));
    command->cmd=LC_ID_DYLIB;
    command->cmdsize=(uint32_t)cmdsize;
    command->dylib.name.offset=sizeof(*command);
    strcpy((char *)command+sizeof(*command),name);
    return data;
}
static NSString *Digest(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    NSMutableString *text=[NSMutableString stringWithString:@"sha256:"];
    for(NSUInteger i=0;i<sizeof(bytes);i++) [text appendFormat:@"%02x",bytes[i]];
    return text;
}
static void Check(BOOL ok,NSString *name) {
    Assertions++;
    if(!ok) { Failures++;fprintf(stderr,"FAIL %s\n",name.UTF8String); }
}
static void Pump(void) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.08]];
}
static NSError *Install(NSData *plugin) {
    __block NSError *failure=nil;
    __block BOOL complete=NO;
    [LCOrbitPluginUpdater installDownloadedPluginAndSign:plugin expectedSHA256:Digest(plugin)
        completion:^(BOOL ok,NSError *error) {
            failure=error;
            complete=YES;
            if(ok) Check(error==nil,@"success has no error");
            else Check(error!=nil,@"failure has clear error");
        }];
    for(int i=0;i<35 && !complete;i++) Pump();
    Check(complete,@"completion returns");
    return failure;
}
int main(void) {
    @autoreleasepool {
        NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *dir=[root stringByAppendingPathComponent:@"Documents/Tweaks"];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        Destination=[dir stringByAppendingPathComponent:@"LCFloatingMenu.dylib"];
        setenv("LC_HOME_PATH",root.UTF8String,1);
        NSData *original=MakePlugin();
        NSMutableData *candidate=[original mutableCopy];
        [candidate appendData:[@"NEW" dataUsingEncoding:NSUTF8StringEncoding]];
        [original writeToFile:Destination atomically:YES];
        NSError *error=Install(candidate);
        Check(error==nil,@"sign succeeds");
        Check(checkCodeSignature(Destination.UTF8String),@"signature verified");
        Check(Calls==1,@"one file signed");
        NSData *working=[NSData dataWithContentsOfFile:Destination];
        Check(working.length>original.length,@"installed content differs from old");

        [original writeToFile:Destination atomically:YES];
        SignerSuccess=NO;
        error=Install(candidate);
        Check(error!=nil,@"signer reports failure");
        Check([[NSData dataWithContentsOfFile:Destination] isEqual:original],@"failed signer rolls back exact original");
        SignerSuccess=YES;

        [original writeToFile:Destination atomically:YES];
        VerifySuccess=NO;
        error=Install(candidate);
        Check(error!=nil,@"invalid signature refused");
        Check([[NSData dataWithContentsOfFile:Destination] isEqual:original],@"invalid signature rolls back");
        VerifySuccess=YES;

        HasCert=NO;
        NSUInteger calls=Calls;
        error=Install(candidate);
        Check(error!=nil && Calls==calls && [[NSData dataWithContentsOfFile:Destination] isEqual:original],
              @"missing certificate never replaces");
        HasCert=YES;

        Host=NO;
        error=Install(candidate);
        Check(error!=nil && Calls==calls && [[NSData dataWithContentsOfFile:Destination] isEqual:original],
              @"guest never replaces");
        Host=YES;

        NSArray *leftovers=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]
            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name,NSDictionary *bindings) {
                return [name hasSuffix:@".rollback"];
            }]];
        Check(leftovers.count==0,@"no rollback artifacts after completed transactions");
        NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
        NSArray<NSString *> *keys=@[@"selected",@"selectedContainer",@"launchAppUrlScheme",@"LCOpenSideStore"];
        NSMutableDictionary<NSString *,id> *saved=[NSMutableDictionary dictionary];
        for(NSString *key in keys) saved[key]=[defaults objectForKey:key]?:NSNull.null;
        [defaults setObject:@"builtinSideStore" forKey:@"selected"];
        [defaults setObject:@"original-container" forKey:@"selectedContainer"];
        [defaults setObject:@"custom-url" forKey:@"launchAppUrlScheme"];
        [defaults setBool:YES forKey:@"LCOpenSideStore"];
        Host=NO;
        NSError *restartError=nil;
        BOOL restarted=[LCOrbitPluginUpdater restartHostAfterSignedUpdate:&restartError];
        Check(!restarted && restartError!=nil && RestartCalls==0,@"guest never starts a host restart");
        Host=YES;
        RestartAccepted=NO;
        restartError=nil;
        restarted=[LCOrbitPluginUpdater restartHostAfterSignedUpdate:&restartError];
        Check(!restarted && restartError!=nil && RestartCalls==1 && RestartTargetSafe,
              @"failed launcher never claims success and receives only host target");
        Check([[defaults stringForKey:@"selected"] isEqualToString:@"builtinSideStore"] &&
              [[defaults stringForKey:@"selectedContainer"] isEqualToString:@"original-container"] &&
              [[defaults stringForKey:@"launchAppUrlScheme"] isEqualToString:@"custom-url"] &&
              [defaults boolForKey:@"LCOpenSideStore"],
              @"launcher rejection restores all previous LC boot flags");
        RestartAccepted=YES;
        restartError=nil;
        restarted=[LCOrbitPluginUpdater restartHostAfterSignedUpdate:&restartError];
        Check(restarted && restartError==nil && RestartCalls==2 && RestartTargetSafe,
              @"verified install may relaunch host through native LC launcher");
        Check([[defaults stringForKey:@"selected"] isEqualToString:@"ui"] &&
              [defaults objectForKey:@"selectedContainer"]==nil &&
              [defaults objectForKey:@"launchAppUrlScheme"]==nil &&
              ![defaults boolForKey:@"LCOpenSideStore"],
              @"accepted restart prepares safe host UI bootstrap");
        for(NSString *key in keys) {
            id prior=saved[key];
            if(prior==NSNull.null) [defaults removeObjectForKey:key];
            else [defaults setObject:prior forKey:key];
        }
        [defaults synchronize];
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        NSString *result=[NSString stringWithFormat:@"%lu/%lu assertions passed",(unsigned long)(Assertions-Failures),(unsigned long)Assertions];
        NSString *resultPath=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/PluginAutoSignResult.txt"];
        [[NSString stringWithFormat:@"%lu %lu %@",(unsigned long)Assertions,(unsigned long)Failures,result]
            writeToFile:resultPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        printf("Plugin auto-sign transaction: %lu assertions, %lu failures\n",
               (unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
