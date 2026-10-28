#import "LCOrbitTweakAudit.h"
#import "LCOrbitLog.h"
#import "LCOrbitHost.h"
#import "LCOrbitGuestService.h"
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <stdlib.h>

static NSString *AuditPath(NSString *path) {
    return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}
static NSString *AuditTweakRoot(NSString **context, NSDictionary **guestInfo) {
    NSDictionary *guest=[LCOrbitHost guestInfo];
    if(guestInfo) *guestInfo=guest;
    BOOL isHost=[LCOrbitHost isHostUI];
    SEL sharedSelector=NSSelectorFromString(@"isSharedApp");
    BOOL isShared=!isHost && [NSUserDefaults respondsToSelector:sharedSelector] &&
        ((BOOL (*)(id,SEL))objc_msgSend)(NSUserDefaults.class,sharedSelector);
    if(context) *context=isHost?@"lc-host":isShared?@"shared-guest":@"private-guest";
    if(isShared) {
        NSString *group=[LCOrbitHost appGroupPath];
        return group.length?
            [group stringByAppendingPathComponent:@"LiveContainer/Tweaks"]:nil;
    }
    const char *home=getenv("LC_HOME_PATH");
    return home && home[0]?
        [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"Documents/Tweaks"]:nil;
}
static NSSet<NSString *> *AuditLoadedImages(void) {
    NSMutableSet<NSString *> *images=[NSMutableSet set];
    uint32_t count=_dyld_image_count();
    for(uint32_t i=0;i<count;i++) {
        const char *path=_dyld_get_image_name(i);
        if(path && path[0]) [images addObject:AuditPath([NSString stringWithUTF8String:path])];
    }
    return images;
}
static NSString *AuditImageStatus(NSString *binary, NSSet<NSString *> *images) {
    if([images containsObject:AuditPath(binary)]) return @"loaded";
    NSString *name=binary.lastPathComponent;
    for(NSString *image in images)
        if([image.lastPathComponent isEqualToString:name]) return @"basename-match-only";
    return @"not-observed";
}
// Host-side disk inspection: does not execute shared tweaks or claim that
// another LC/Guest process loaded them. Comparing bytes catches a stale
// per-app copy when the host uses a newer FloatingMenu build.
static NSString *AuditBinaryComparison(NSString *candidate, NSString *running) {
    if(!candidate.length || !running.length) return @"unknown";
    NSFileManager *fm=NSFileManager.defaultManager;
    BOOL directory=NO;
    if(![fm fileExistsAtPath:candidate isDirectory:&directory] || directory)
        return @"missing";
    if(![fm fileExistsAtPath:running]) return @"unknown";
    return [fm contentsEqualAtPath:candidate andPath:running] ?
        @"same-as-running-host" : @"different-from-running-host";
}
static NSString *AuditRunningFloatingMenu(NSSet<NSString *> *images) {
    for(NSString *image in images)
        if([image.lastPathComponent isEqualToString:@"LCFloatingMenu.dylib"]) return image;
    return nil;
}
static void AuditSharedStorage(NSSet<NSString *> *images, NSMutableArray<NSString *> *lines) {
    NSString *group=[LCOrbitHost appGroupPath];
    if(!group.length) {
        [lines addObject:@"shared-disk error=app-group-unavailable"];
        return;
    }
    NSString *root=[group stringByAppendingPathComponent:@"LiveContainer"];
    NSString *tweakRoot=[root stringByAppendingPathComponent:@"Tweaks"];
    NSString *appsRoot=[root stringByAppendingPathComponent:@"Applications"];
    NSString *running=AuditRunningFloatingMenu(images);
    [lines addObject:[NSString stringWithFormat:@"shared-disk root=%@",tweakRoot]];
    [lines addObject:@"shared-disk scope=files-only; status is NOT a shared Guest load result"];
    NSError *error=nil;
    NSArray<NSString *> *entries=[NSFileManager.defaultManager
        contentsOfDirectoryAtPath:tweakRoot error:&error];
    if(error) [lines addObject:[NSString stringWithFormat:
        @"shared-global read-error code=%ld",(long)error.code]];
    BOOL found=NO;
    NSUInteger checked=0;
    for(NSString *name in entries) {
        if(checked>=100) { [lines addObject:@"shared-global truncated=100"]; break; }
        if(![name hasSuffix:@".dylib"] && ![name hasSuffix:@".framework"] &&
           ![name hasSuffix:@".disabled"]) continue;
        NSString *path=[tweakRoot stringByAppendingPathComponent:name];
        NSString *comparison=[name isEqualToString:@"LCFloatingMenu.dylib"] ?
            AuditBinaryComparison(path,running) : @"disk-present";
        [lines addObject:[NSString stringWithFormat:@"shared-global %@ %@",name,comparison]];
        found=YES;
        checked++;
    }
    if(!found && !error) [lines addObject:@"shared-global no-root-tweaks-found"];
    NSError *appError=nil;
    NSArray<NSString *> *apps=[NSFileManager.defaultManager contentsOfDirectoryAtPath:appsRoot error:&appError];
    if(appError) [lines addObject:[NSString stringWithFormat:
        @"shared-apps read-error code=%ld",(long)appError.code]];
    NSUInteger appCount=0;
    for(NSString *name in apps) {
        if(appCount>=60) { [lines addObject:@"shared-apps truncated=60"]; break; }
        if(![name hasSuffix:@".app"]) continue;
        NSString *bundle=[appsRoot stringByAppendingPathComponent:name];
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:
            [bundle stringByAppendingPathComponent:@"LCAppInfo.plist"]];
        NSString *selected=info[@"LCTweakFolder"];
        if(![selected isKindOfClass:NSString.class] || !selected.length) continue;
        if([selected containsString:@"/"] || [selected isEqualToString:@".."]) continue;
        NSString *dylib=[[tweakRoot stringByAppendingPathComponent:selected]
                          stringByAppendingPathComponent:@"LCFloatingMenu.dylib"];
        NSString *comparison=AuditBinaryComparison(dylib,running);
        [lines addObject:[NSString stringWithFormat:
            @"shared-app %@ selected=%@ FloatingMenu=%@",name,selected,comparison]];
        appCount++;
    }
    [lines addObject:@"shared-disk reminder=install-new-FloatingMenu-in-shared-root-or-selected-folder-for-Guest-side-logs"];
}
static void AuditItem(NSURL *url, BOOL recursive, NSString *scope,
                      NSSet<NSString *> *images, NSMutableArray<NSString *> *lines,
                      NSUInteger *count) {
    if(*count>=150) return;
    NSString *name=url.lastPathComponent;
    if([name hasSuffix:@".disabled"]) {
        [lines addObject:[NSString stringWithFormat:@"%@ disabled %@",scope,name]];
        ++*count;
        return;
    }
    NSNumber *isDir=nil;
    [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
    BOOL framework=[name hasSuffix:@".framework"];
    if(isDir.boolValue && !framework) {
        if(!recursive) return; // LC does not recursively scan the global root.
        NSError *error=nil;
        NSArray<NSURL *> *items=[NSFileManager.defaultManager
            contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[NSURLIsDirectoryKey]
            options:0 error:&error];
        if(error) [lines addObject:[NSString stringWithFormat:@"%@ folder-error %@ code=%ld",
                                  scope,name,(long)error.code]];
        for(NSURL *item in items)
            AuditItem(item,YES,[scope stringByAppendingFormat:@"/%@",name],images,lines,count);
        return;
    }
    if(![name hasSuffix:@".dylib"] && !framework) return;
    NSString *binary=url.path;
    if(framework) {
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfURL:
                            [url URLByAppendingPathComponent:@"Info.plist"]];
        NSString *exec=info[@"CFBundleExecutable"];
        if(![exec isKindOfClass:NSString.class] || !exec.length) {
            [lines addObject:[NSString stringWithFormat:@"%@ invalid-framework %@",scope,name]];
            ++*count;
            return;
        }
        binary=[binary stringByAppendingPathComponent:exec];
    }
    NSString *status=AuditImageStatus(binary,images);
    if([name isEqualToString:@"TweakLoader.dylib"])
        status=[NSString stringWithFormat:@"loader-%@",status];
    [lines addObject:[NSString stringWithFormat:@"%@ %@ %@",scope,status,name]];
    ++*count;
}
@implementation LCOrbitTweakAudit
+ (void)appendEvent:(NSString *)event {
    [LCOrbitLog appendEvent:@"sync-event" details:event kind:@"tweaks"];
}
+ (NSString *)logPath { return [LCOrbitLog pathForKind:@"tweaks"]; }
+ (NSString *)captureSnapshot {
    NSString *context=nil;
    NSDictionary *guest=nil;
    NSString *root=AuditTweakRoot(&context,&guest);
    NSMutableArray<NSString *> *lines=[NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"context=%@ guest=%@",
        context?:@"unknown",[LCOrbitHost guestIdentifier]]];
    [lines addObject:[NSString stringWithFormat:@"root=%@",root?:@"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"flags dontInject=%d dontLoad=%d selected=%@",
        [guest[@"dontInjectTweakLoader"] boolValue],
        [guest[@"dontLoadTweakLoader"] boolValue],
        guest[@"LCTweakFolder"]?:@"none"]];
    NSSet<NSString *> *images=AuditLoadedImages();
    NSUInteger count=0;
    if(!root.length) {
        [lines addObject:@"error=global-tweak-root-unavailable"];
    } else {
        NSError *error=nil;
        NSArray<NSURL *> *items=[NSFileManager.defaultManager
            contentsOfDirectoryAtURL:[NSURL fileURLWithPath:root]
            includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:&error];
        if(error) [lines addObject:[NSString stringWithFormat:@"global-dir-error code=%ld",
                                     (long)error.code]];
        for(NSURL *item in items)
            AuditItem(item,NO,@"global",images,lines,&count);
        NSString *selected=guest[@"LCTweakFolder"];
        if([selected isKindOfClass:NSString.class] && selected.length &&
           ![selected containsString:@"/"] && ![selected isEqualToString:@".."]) {
            NSURL *folder=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:selected]];
            NSError *folderError=nil;
            NSArray<NSURL *> *children=[NSFileManager.defaultManager
                contentsOfDirectoryAtURL:folder includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                options:0 error:&folderError];
            if(folderError) [lines addObject:[NSString stringWithFormat:@"selected-dir-error code=%ld",
                                                (long)folderError.code]];
            for(NSURL *item in children)
                AuditItem(item,YES,[@"selected/" stringByAppendingString:selected],images,lines,&count);
        }
    }
    // In LC's home UI, inspect the shared storage even if its Guest has no
    // working tweak. The check is explicitly labeled disk-only.
    if([context isEqualToString:@"lc-host"])
        AuditSharedStorage(images,lines);
    if(count>=150) [lines addObject:@"truncated=150-items"];
    [lines addObjectsFromArray:[LCOrbitGuestService inventoryDiagnostics]];
    [lines addObject:@"note=post-load-dyld-snapshot-not-original-TweakLoader-NSLog"];
    NSString *report=[lines componentsJoinedByString:@"\n"];
    [LCOrbitLog appendEvent:@"snapshot" details:@{@"context":context?:@"unknown",@"lines":lines} kind:@"tweaks"];
    return report;
}
+ (void)clearLogs { [LCOrbitLog clearKind:@"tweaks"]; }

@end
