#import "LCOrbitTweakSync.h"
#import "LCOrbitHost.h"
#import "LCOrbitStorage.h"
#import "LCOrbitTweakAudit.h"
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <stdio.h>
#import <stdlib.h>
#import <errno.h>

static NSString *HostTweaksPath(void) {
    const char *home=getenv("LC_HOME_PATH");
    if(!home || !home[0]) return nil;
    return [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"Documents/Tweaks"];
}
static BOOL RegularFile(NSString *path) {
    struct stat st;
    return path.length && lstat(path.fileSystemRepresentation,&st)==0 && S_ISREG(st.st_mode);
}
static BOOL ExistsWithoutFollowingLinks(NSString *path) {
    struct stat st;
    return path.length && lstat(path.fileSystemRepresentation,&st)==0;
}
static NSString *Canonical(NSString *path) {
    return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}
static BOOL ManageableName(NSString *name) {
    if(![name isKindOfClass:NSString.class] || !name.length ||
       ![name isEqualToString:name.lastPathComponent] || [name hasPrefix:@"."]) return NO;
    return [name hasSuffix:@".dylib"] && ![name isEqualToString:@"TweakLoader.dylib"];
}
static NSSet<NSString *> *LoadedImages(void) {
    NSMutableSet<NSString *> *images=[NSMutableSet set];
    uint32_t count=_dyld_image_count();
    for(uint32_t i=0;i<count;i++) {
        const char *path=_dyld_get_image_name(i);
        if(path && path[0]) [images addObject:Canonical([NSString stringWithUTF8String:path])];
    }
    return images;
}
static NSString *SharedTweakRoot(void) {
    NSString *group=[LCOrbitHost appGroupPath];
    return group.length?[group stringByAppendingPathComponent:@"LiveContainer/Tweaks"]:nil;
}
static NSString *const AutomaticPluginNamesKey=@"LCFloatingMenu.autoSyncSharedPluginNames";
static NSArray<NSString *> *AutomaticPluginNames(void) {
    NSMutableOrderedSet<NSString *> *names=[NSMutableOrderedSet orderedSet];
    for(id name in [[LCOrbitStorage preferences] arrayForKey:AutomaticPluginNamesKey])
        if(ManageableName(name)) [names addObject:name];
    return names.array;
}
static BOOL SyncError(NSError **error,NSString *message) {
    if(error) *error=[NSError errorWithDomain:@"LCOrbitTweakSync" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}

@implementation LCOrbitTweakSync
+ (BOOL)automaticSyncEnabled { return AutomaticPluginNames().count>0; }
+ (BOOL)automaticSyncEnabledForPlugin:(NSString *)name {
    return ManageableName(name) && [AutomaticPluginNames() containsObject:name];
}
+ (BOOL)setAutomaticSyncEnabled:(BOOL)enabled forPlugin:(NSString *)name error:(NSError **)error {
    @synchronized(self) {
        if(![LCOrbitHost isHostUI]) return SyncError(error,@"请从 LC 主界面调整自动共享。");
        if(!ManageableName(name)) return SyncError(error,@"插件名称无效，未修改自动共享配置。");
        if(enabled) {
            NSString *source=[HostTweaksPath() stringByAppendingPathComponent:name];
            NSString *disabled=[source stringByAppendingString:@".disabled"];
            BOOL active=RegularFile(source),inactive=RegularFile(disabled);
            if((!active && !inactive) || (active && inactive) ||
               (ExistsWithoutFollowingLinks(source) && !active) ||
               (ExistsWithoutFollowingLinks(disabled) && !inactive))
                return SyncError(error,@"只有安全的本地插件可开启自动共享。");
        }
        NSMutableOrderedSet<NSString *> *names=[NSMutableOrderedSet orderedSetWithArray:AutomaticPluginNames()];
        if([names containsObject:name]==enabled) return YES;
        if(enabled) [names addObject:name];else [names removeObject:name];
        [[LCOrbitStorage preferences] setObject:names.array forKey:AutomaticPluginNamesKey];
        NSError *writeError=[LCOrbitStorage lastError];
        if(writeError) { if(error) *error=writeError;return NO; }
        [LCOrbitTweakAudit appendEvent:[NSString stringWithFormat:@"automatic-sync plugin=%@ %@",name,enabled?@"enabled":@"disabled"]];
        return YES;
    }
}
+ (void)setAutomaticSyncEnabled:(BOOL)enabled { [self setAutomaticSyncEnabled:enabled error:nil]; }
+ (BOOL)setAutomaticSyncEnabled:(BOOL)enabled error:(NSError **)error {
    // Legacy callers cannot opt every plugin in. Only explicit names authorize
    // automatic sharing; an old global=true preference is deliberately ignored.
    @synchronized(self) {
        if(![LCOrbitHost isHostUI]) return SyncError(error,@"请从 LC 主界面调整自动共享。");
        if(enabled) return [self automaticSyncEnabled] || SyncError(error,@"请在插件详情中逐个开启自动共享。");
        if(![self automaticSyncEnabled]) return YES;
        [[LCOrbitStorage preferences] setObject:@[] forKey:AutomaticPluginNamesKey];
        NSError *writeError=[LCOrbitStorage lastError];
        if(writeError) { if(error) *error=writeError;return NO; }
        [LCOrbitTweakAudit appendEvent:@"automatic-sync all-explicit-selections disabled"];
        return YES;
    }
}
+ (NSString *)syncAutomaticallyIfNeeded {
    @synchronized(self) {
        if(![LCOrbitHost isHostUI]) return @"";
        NSSet<NSString *> *selected=[NSSet setWithArray:AutomaticPluginNames()];
        if(!selected.count) return @"";
        NSMutableArray<NSString *> *names=[NSMutableArray array];
        for(NSString *name in [self eligibleNames]) if([selected containsObject:name]) [names addObject:name];
        if(!names.count) return @"";
        NSString *report=[self applyShare:YES names:names];
        [LCOrbitTweakAudit appendEvent:[@"automatic-sync " stringByAppendingString:report]];
        return report;
    }
}
+ (NSArray<NSDictionary *> *)pluginInventory {
    if(![LCOrbitHost isHostUI]) return @[];
    NSString *privateRoot=HostTweaksPath(), *sharedRoot=SharedTweakRoot();
    if(!privateRoot.length || !sharedRoot.length) return @[];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSArray<NSString *> *privateEntries=[fm contentsOfDirectoryAtPath:privateRoot error:nil]?:@[];
    NSArray<NSString *> *sharedEntries=[fm contentsOfDirectoryAtPath:sharedRoot error:nil]?:@[];
    NSMutableSet<NSString *> *names=[NSMutableSet set];
    for(NSString *entry in privateEntries) {
        NSString *name=[entry hasSuffix:@".dylib.disabled"]?
            [entry substringToIndex:entry.length-9]:entry;
        if(ManageableName(name)) [names addObject:name];
    }
    for(NSString *entry in sharedEntries) {
        NSString *name=[entry hasSuffix:@".dylib.disabled"]?
            [entry substringToIndex:entry.length-9]:entry;
        if(ManageableName(name)) [names addObject:name];
    }
    NSSet<NSString *> *images=LoadedImages();
    NSMutableArray<NSDictionary *> *items=[NSMutableArray array];
    NSArray<NSString *> *sorted=[[names allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for(NSString *name in sorted) {
        if(items.count>=200) break;
        NSString *privatePath=[privateRoot stringByAppendingPathComponent:name];
        NSString *sharedPath=[sharedRoot stringByAppendingPathComponent:name];
        NSString *privateOff=[privatePath stringByAppendingString:@".disabled"];
        NSString *sharedOff=[sharedPath stringByAppendingString:@".disabled"];
        BOOL sourceOn=RegularFile(privatePath),sourceOff=RegularFile(privateOff);
        BOOL sharedOn=RegularFile(sharedPath),sharedDisabled=RegularFile(sharedOff);
        BOOL blocked=(ExistsWithoutFollowingLinks(privatePath) && !sourceOn) ||
                     (ExistsWithoutFollowingLinks(privateOff) && !sourceOff) ||
                     (ExistsWithoutFollowingLinks(sharedPath) && !sharedOn) ||
                     (ExistsWithoutFollowingLinks(sharedOff) && !sharedDisabled) ||
                     (sourceOn && sourceOff) || (sharedOn && sharedDisabled);
        BOOL loaded=sourceOn && [images containsObject:Canonical(privatePath)];
        BOOL matches=sourceOn && sharedOn && [fm contentsEqualAtPath:privatePath andPath:sharedPath];
        [items addObject:@{
            @"name":name,
            @"private":@(sourceOn || sourceOff), @"shared":@(sharedOn || sharedDisabled),
            @"privateDisabled":@(sourceOff),@"sharedDisabled":@(sharedDisabled),
            @"loaded":@(loaded), @"matches":@(matches),
            @"blocked":@(blocked),
            @"canShare":@(sourceOn && loaded && !blocked && !matches && !sharedDisabled),
            @"canUnshare":@((sharedOn || sharedDisabled) && !blocked)
        }];
    }
    return items;
}
+ (NSArray<NSString *> *)eligibleNames {
    NSMutableArray<NSString *> *names=[NSMutableArray array];
    for(NSDictionary *item in [self pluginInventory])
        if([item[@"canShare"] boolValue])
            [names addObject:item[@"name"]];
    return names;
}
+ (NSString *)copyLoadedTweaksToShared {
    return [self applyShare:YES names:[self eligibleNames]];
}
+ (NSString *)applyShare:(BOOL)share names:(NSArray<NSString *> *)requested {
    @synchronized(self) {
    if(![LCOrbitHost isHostUI]) return @"只能从 LiveContainer 主界面管理共享插件。";
    NSString *privateRoot=HostTweaksPath(), *sharedRoot=SharedTweakRoot();
    if(!privateRoot.length || !sharedRoot.length)
        return @"无法访问私有插件目录或共享目录。";
    if(![requested isKindOfClass:NSArray.class] || requested.count==0)
        return @"尚未选择插件。";
    NSFileManager *fm=NSFileManager.defaultManager;
    NSMutableDictionary<NSString *,NSDictionary *> *inventory=[NSMutableDictionary dictionary];
    for(NSDictionary *item in [self pluginInventory]) inventory[item[@"name"]]=item;
    NSMutableOrderedSet<NSString *> *names=[NSMutableOrderedSet orderedSet];
    for(id name in requested) {
        if([name isKindOfClass:NSString.class] && ManageableName(name))
            [names addObject:name];
    }
    if(!names.count) return @"没有可操作的插件。";
    NSUInteger done=0,skipped=0,failed=0;
    NSMutableArray<NSString *> *results=[NSMutableArray array];
    for(NSString *name in names) {
        NSDictionary *item=inventory[name];
        NSString *from=[privateRoot stringByAppendingPathComponent:name];
        NSString *to=[sharedRoot stringByAppendingPathComponent:name];
        if(!item || [item[@"blocked"] boolValue]) {
            failed++;
            [results addObject:[NSString stringWithFormat:@"%@：文件类型不安全，未操作",name]];
            continue;
        }
        if(share) {
            if(![item[@"canShare"] boolValue]) {
                skipped++;
                [results addObject:[NSString stringWithFormat:@"%@：没有已加载的可共享版本，或已是最新版",name]];
                continue;
            }
            if(!RegularFile(from) || (ExistsWithoutFollowingLinks(to) && !RegularFile(to))) {
                failed++;
                [results addObject:[NSString stringWithFormat:@"%@：文件状态发生变化，未操作",name]];
                continue;
            }
            if(![fm createDirectoryAtPath:sharedRoot withIntermediateDirectories:YES attributes:nil error:nil]) {
                failed++;
                [results addObject:[NSString stringWithFormat:@"%@：共享目录不可写",name]];
                continue;
            }
            NSString *temporary=[sharedRoot stringByAppendingPathComponent:
                [NSString stringWithFormat:@".%@.%@.tmp",name,NSUUID.UUID.UUIDString]];
            if(![fm copyItemAtPath:from toPath:temporary error:nil] ||
               ![fm contentsEqualAtPath:from andPath:temporary]) {
                failed++;
                [fm removeItemAtPath:temporary error:nil];
                [results addObject:[NSString stringWithFormat:@"%@：复制校验失败",name]];
                continue;
            }
            if(rename(temporary.fileSystemRepresentation,to.fileSystemRepresentation)!=0) {
                failed++;
                [fm removeItemAtPath:temporary error:nil];
                [results addObject:[NSString stringWithFormat:@"%@：更新共享副本失败",name]];
                continue;
            }
            done++;
            [results addObject:[NSString stringWithFormat:@"%@：已共享",name]];
        } else {
            NSString *actual=[item[@"sharedDisabled"] boolValue]?[to stringByAppendingString:@".disabled"]:to;
            if(![item[@"canUnshare"] boolValue] || !RegularFile(actual)) {
                skipped++;
                [results addObject:[NSString stringWithFormat:@"%@：没有可取消的共享副本",name]];
                continue;
            }
            // Removing a regular shared copy is atomic; unlink failure leaves
            // it in place. Private originals and historical backups stay intact.
            if(unlink(actual.fileSystemRepresentation)!=0) {
                failed++;
                [results addObject:[NSString stringWithFormat:@"%@：无法移除共享副本",name]];
                continue;
            }
            done++;
            [results addObject:[NSString stringWithFormat:@"%@：已取消共享",name]];
        }
    }
    NSString *report=[NSString stringWithFormat:
        @"%@：成功 %lu，跳过 %lu，失败 %lu\n%@\n\n仅管理共享全局目录中的副本；私有插件和应用专属插件不会改动。已运行的 Guest 需要重新启动才能反映更改。",
        share?@"批量共享":@"取消共享",
        (unsigned long)done,(unsigned long)skipped,(unsigned long)failed,
        [results componentsJoinedByString:@"\n"]];
    [LCOrbitTweakAudit appendEvent:[NSString stringWithFormat:@"manual-sync action=%@ %@",
                                   share?@"share":@"revoke",report]];
    [LCOrbitTweakAudit captureSnapshot];
    return report;
    }
}
@end
