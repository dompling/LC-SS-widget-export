#import "LCOrbitLog.h"
#import "LCOrbitStorage.h"
#import "LCOrbitHost.h"
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

@interface LCOrbitStorage (LogDirectory)
+ (nullable NSString *)rootPath;
@end

static const NSUInteger LogLimit=262144;
static BOOL Kind(NSString *kind) { return [kind isEqual:@"runtime"] || [kind isEqual:@"tweaks"]; }
static BOOL Regular(NSString *path) {
    struct stat info;
    return lstat(path.fileSystemRepresentation,&info)==0 && S_ISREG(info.st_mode);
}
static NSData *Encode(NSArray *events) {
    return [NSJSONSerialization dataWithJSONObject:@{@"schemaVersion":@1,@"events":events}
        options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
}
static NSArray *ReadEvents(NSString *path) {
    if(!Regular(path) || [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileSize]>LogLimit) return nil;
    NSData *bytes=[NSData dataWithContentsOfFile:path];
    NSDictionary *document=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;
    if(![document isKindOfClass:NSDictionary.class] || ![document[@"schemaVersion"] isEqual:@1] ||
       ![document[@"events"] isKindOfClass:NSArray.class]) return nil;
    for(id event in document[@"events"])
        if(![event isKindOfClass:NSDictionary.class] || ![event[@"event"] isKindOfClass:NSString.class]) return nil;
    return document[@"events"];
}
static NSString *OldPath(NSString *path) {
    return [path.stringByDeletingPathExtension stringByAppendingString:@".old.json"];
}
static NSDictionary *Event(NSString *event,id details) {
    NSISO8601DateFormatter *format=[NSISO8601DateFormatter new];
    NSString *guest=[LCOrbitHost guestIdentifier]?:@"unknown";
    NSMutableDictionary *record=[@{@"timestamp":[format stringFromDate:NSDate.date],
        @"guestID":guest,@"context":[LCOrbitHost isHostUI]?@"lc-host":@"guest",
        @"pid":@(getpid()),@"event":[event isKindOfClass:NSString.class]?event:@"unknown"} mutableCopy];
    if(details) record[@"details"]=details;
    if(![NSJSONSerialization isValidJSONObject:record]) record[@"details"]=[details description]?:@"";
    NSData *encoded=Encode(@[record]);
    if(encoded.length>LogLimit/2) {
        NSString *text=[details description]?:@"";
        record[@"details"]=[text substringToIndex:MIN(text.length,8192)];
        record[@"truncated"]=@YES;
        record[@"event"]=[record[@"event"] substringToIndex:MIN([record[@"event"] length],256)];
        record[@"guestID"]=[guest substringToIndex:MIN(guest.length,512)];
    }
    return record;
}
static BOOL EnsureDirectory(NSString *directory) {
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    struct stat info;
    return lstat(directory.fileSystemRepresentation,&info)==0 && S_ISDIR(info.st_mode);
}
static int Lock(NSString *path) {
    // Validate the parent root before creating logs beneath it. Checking only
    // the final logs directory would follow a replaced/symlinked LCOrbit root.
    NSString *root=[LCOrbitStorage rootPath];
    if(!root.length || !EnsureDirectory(root)) return -1;
    if(!EnsureDirectory(path.stringByDeletingLastPathComponent)) return -1;
    NSString *lock=[path stringByAppendingString:@".lock"];
    int descriptor=open(lock.fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(descriptor<0) return -1;
    if(flock(descriptor,LOCK_EX)!=0) {close(descriptor);return -1;}
    return descriptor;
}
static void Unlock(int descriptor) { flock(descriptor,LOCK_UN);close(descriptor); }
static NSString *LegacyRoot(void) {
    NSString *group=[LCOrbitHost appGroupPath];
    if(group.length) return [group stringByAppendingPathComponent:@"LiveContainer/LCFloatingMenu"];
    const char *home=getenv("LC_HOME_PATH");
    return home && home[0]?[[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"Documents/LCFloatingMenu"]:nil;
}
static BOOL WriteImportedEvents(NSArray *events,NSString *path) {
    NSMutableArray *current=[NSMutableArray array];
    NSData *previous=nil;
    for(NSDictionary *event in events) {
        [current addObject:event];
        NSData *bytes=Encode(current);
        if(bytes.length>LogLimit) {
            [current removeLastObject];previous=Encode(current);
            [current removeAllObjects];[current addObject:event];
        }
    }
    if(previous && ![previous writeToFile:OldPath(path) atomically:YES]) return NO;
    return [Encode(current) writeToFile:path atomically:YES];
}
// A separate marker survives rotation and clear, so old plaintext history is
// never resurrected after the user clears the JSON log.
static void ImportLegacy(NSString *path,NSString *kind) {
    NSString *marker=[path stringByAppendingString:@".migrated"];
    NSFileManager *fm=NSFileManager.defaultManager;
    if([fm fileExistsAtPath:marker]) return;
    if(Regular(path)) {
        [NSData.data writeToFile:marker atomically:YES];
        return;
    }
    NSString *legacy=[LegacyRoot() stringByAppendingPathComponent:[kind isEqual:@"runtime"]?@"diagnostics.log":@"tweaks.log"];
    NSMutableArray *events=[NSMutableArray array];
    if(legacy) for(NSString *file in @[[legacy stringByAppendingString:@".old"],legacy]) {
        if(!Regular(file)) continue;
        // Read a bounded tail from old logs without loading unbounded user files.
        NSFileHandle *handle=[NSFileHandle fileHandleForReadingAtPath:file];
        unsigned long long length=[handle seekToEndOfFile];
        [handle seekToFileOffset:length>LogLimit?length-LogLimit:0];
        NSData *tail=[handle readDataOfLength:LogLimit];[handle closeFile];
        NSString *text=nil;
        for(NSUInteger skip=0;!text && skip<MIN((NSUInteger)4,tail.length);skip++)
            text=[[NSString alloc] initWithData:[tail subdataWithRange:NSMakeRange(skip,tail.length-skip)] encoding:NSUTF8StringEncoding];
        for(NSUInteger offset=0;offset<text.length;) {
            NSRange range=[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(offset,MIN((NSUInteger)16384,text.length-offset))];
            [events addObject:Event(@"legacy-import",@{@"source":file.lastPathComponent,@"text":[text substringWithRange:range]})];
            offset=NSMaxRange(range);
        }
    }
    if(WriteImportedEvents(events,path)) [NSData.data writeToFile:marker atomically:YES];
}
static NSMutableArray *CurrentEvents(NSString *path) {
    NSArray *events=ReadEvents(path);
    if(events) return [events mutableCopy];
    if(Regular(path)) {
        NSString *corrupt=[path.stringByDeletingPathExtension stringByAppendingString:@".corrupt.json"];
        [NSFileManager.defaultManager removeItemAtPath:corrupt error:nil];
        [NSFileManager.defaultManager moveItemAtPath:path toPath:corrupt error:nil];
        return [NSMutableArray arrayWithObject:Event(@"log-recovered",@"Invalid JSON log preserved as .corrupt.json")];
    }
    return [NSMutableArray array];
}

@implementation LCOrbitLog
+ (NSString *)pathForKind:(NSString *)kind {
    if(!Kind(kind)) return nil;
    NSString *root=[LCOrbitStorage rootPath];
    return root.length?[[root stringByAppendingPathComponent:@"logs"] stringByAppendingPathComponent:[kind stringByAppendingString:@".json"]]:nil;
}
+ (void)appendEvent:(NSString *)event details:(id)details kind:(NSString *)kind {
    @try { @synchronized(self) {
        NSString *path=[self pathForKind:kind];if(!path) return;
        int descriptor=Lock(path);if(descriptor<0) return;
        @try {
            ImportLegacy(path,kind);
            NSMutableArray *events=CurrentEvents(path);
            [events addObject:Event(event,details)];
            NSData *bytes=Encode(events);
            if(bytes.length>LogLimit) {
                NSArray *previous=[events subarrayWithRange:NSMakeRange(0,events.count-1)];
                NSData *old=Encode(previous);
                if(old.length<=LogLimit && ![old writeToFile:OldPath(path) atomically:YES]) return;
                bytes=Encode(@[events.lastObject]);
            }
            if(bytes.length<=LogLimit) [bytes writeToFile:path atomically:YES];
        } @finally { Unlock(descriptor); }
    } } @catch(NSException *exception) { /* Logging must never break the guest. */ }
}
+ (NSData *)dataForKind:(NSString *)kind {
    @try { @synchronized(self) {
        NSString *path=[self pathForKind:kind];if(!path) return Encode(@[]);
        int descriptor=Lock(path);if(descriptor<0) return Encode(@[]);
        @try {
            ImportLegacy(path,kind);
            NSMutableArray *events=[NSMutableArray arrayWithArray:ReadEvents(OldPath(path))?:@[]];
            [events addObjectsFromArray:ReadEvents(path)?:@[]];
            return Encode(events)?:Encode(@[]);
        } @finally { Unlock(descriptor); }
    } } @catch(NSException *exception) { return Encode(@[]); }
}
+ (void)clearKind:(NSString *)kind {
    @try { @synchronized(self) {
        NSString *path=[self pathForKind:kind];if(!path) return;
        int descriptor=Lock(path);if(descriptor<0) return;
        @try {
            if([Encode(@[]) writeToFile:path atomically:YES]) {
                [NSData.data writeToFile:[path stringByAppendingString:@".migrated"] atomically:YES];
                [NSFileManager.defaultManager removeItemAtPath:OldPath(path) error:nil];
                [NSFileManager.defaultManager removeItemAtPath:[path.stringByDeletingPathExtension stringByAppendingString:@".corrupt.json"] error:nil];
            }
        } @finally { Unlock(descriptor); }
    } } @catch(NSException *exception) { }
}
@end
