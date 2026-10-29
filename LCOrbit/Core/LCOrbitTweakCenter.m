#import "LCOrbitTweakCenter.h"
#import "LCOrbitGuestService.h"
#import "LCOrbitHost.h"
#import "LCOrbitTweakAudit.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <stdio.h>

static BOOL TCRegular(NSString *path) {
    struct stat st;
    return path.length && lstat(path.fileSystemRepresentation,&st)==0 && S_ISREG(st.st_mode);
}
static BOOL TCExists(NSString *path) {
    struct stat st;
    return path.length && lstat(path.fileSystemRepresentation,&st)==0;
}
static BOOL TCDirectory(NSString *path) {
    struct stat st;
    return path.length && lstat(path.fileSystemRepresentation,&st)==0 && S_ISDIR(st.st_mode);
}
static BOOL TCName(NSString *name) {
    return [name isKindOfClass:NSString.class] && name.length &&
        [name isEqualToString:name.lastPathComponent] && ![name hasPrefix:@"."] &&
        [name hasSuffix:@".dylib"] && ![name isEqualToString:@"TweakLoader.dylib"];
}
static NSString *TCHome(void) {
    const char *p=getenv("LC_HOME_PATH");
    return (p && p[0])?[NSString stringWithUTF8String:p]:nil;
}
static NSString *TCRoot(BOOL shared) {
    NSString *base=shared?[LCOrbitHost appGroupPath]:TCHome();
    if(!base.length) return nil;
    return [base stringByAppendingPathComponent:shared?@"LiveContainer/Tweaks":@"Documents/Tweaks"];
}
static NSString *TCBackupRoot(BOOL shared) {
    NSString *base=shared?[LCOrbitHost appGroupPath]:TCHome();
    if(!base.length) return nil;
    return [base stringByAppendingPathComponent:shared?
        @"LiveContainer/LCFloatingMenu/PluginBackups":@"Documents/LCFloatingMenu/PluginBackups"];
}
static NSString *TCOldSyncBackupRoot(void) {
    NSString *group=[LCOrbitHost appGroupPath];
    return group.length?[group stringByAppendingPathComponent:
        @"LiveContainer/LCFloatingMenu/TweakBackups"]:nil;
}
static NSString *TCAppBackupRoot(BOOL shared) {
    NSString *base=shared?[LCOrbitHost appGroupPath]:TCHome();
    if(!base.length) return nil;
    return [base stringByAppendingPathComponent:shared?
        @"LiveContainer/LCFloatingMenu/AppAssignments":@"Documents/LCFloatingMenu/AppAssignments"];
}
static NSString *TCFileInRoot(NSString *root, NSString *name) {
    NSString *active=[root stringByAppendingPathComponent:name];
    if(TCRegular(active)) return active;
    NSString *disabled=[active stringByAppendingString:@".disabled"];
    return TCRegular(disabled)?disabled:nil;
}
static BOOL TCScope(NSDictionary *guest) {
    NSString *path=guest[@"folder"];
    NSString *group=[LCOrbitHost appGroupPath];
    return group.length && [path hasPrefix:[group stringByAppendingPathComponent:@"LiveContainer/Applications/"]];
}
static NSString *TCManagedName(NSDictionary *guest) {
    NSString *identity=[NSString stringWithFormat:@"%@|%@",
        TCScope(guest)?@"shared":@"private",guest[@"path"]?:@""];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    NSData *data=[identity dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *result=[NSMutableString stringWithString:@"Orbit-"];
    for(NSUInteger i=0;i<10;i++) [result appendFormat:@"%02x",digest[i]];
    return result;
}
static NSDictionary *TCReadInfo(NSDictionary *guest) {
    NSString *folder=guest[@"folder"];
    if(![folder isKindOfClass:NSString.class] || !folder.length) return nil;
    NSString *file=[folder stringByAppendingPathComponent:@"LCAppInfo.plist"];
    if(!TCRegular(file)) return nil;
    return [NSDictionary dictionaryWithContentsOfFile:file];
}
static BOOL TCWriteInfo(NSDictionary *guest, NSMutableDictionary *info) {
    NSString *file=[guest[@"folder"] stringByAppendingPathComponent:@"LCAppInfo.plist"];
    NSError *error=nil;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:info
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    return data && [data writeToFile:file options:NSDataWritingAtomic error:&error];
}
static BOOL TCEnsure(NSString *dir) {
    return dir.length && [NSFileManager.defaultManager createDirectoryAtPath:dir
        withIntermediateDirectories:YES attributes:nil error:nil];
}
static NSString *TCBackup(NSString *source, NSString *folder, NSString *name) {
    if(!TCRegular(source) || !TCEnsure(folder)) return nil;
    NSString *safe=[name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *backup=[folder stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.%@.bak",safe,NSUUID.UUID.UUIDString]];
    if(![NSFileManager.defaultManager copyItemAtPath:source toPath:backup error:nil] ||
       ![NSFileManager.defaultManager contentsEqualAtPath:source andPath:backup]) {
        [NSFileManager.defaultManager removeItemAtPath:backup error:nil]; return nil;
    }
    return backup;
}
static NSString *TCResult(NSString *action,NSString *message) {
    [LCOrbitTweakAudit appendEvent:[NSString stringWithFormat:@"tweak-center %@ %@",action,message]];
    return message;
}
@implementation LCOrbitTweakCenter
+ (NSArray<NSDictionary *> *)guests {
    if(![LCOrbitHost isHostUI]) return @[];
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *app in [LCOrbitGuestService installedApps]) {
        if([app[@"builtin"] boolValue]) continue;
        NSDictionary *info=TCReadInfo(app);
        if(!info) continue;
        NSString *managed=TCManagedName(app);
        NSString *current=[info[@"LCTweakFolder"] isKindOfClass:NSString.class]?info[@"LCTweakFolder"]:@"";
        BOOL shared=TCScope(app);
        NSString *root=TCRoot(shared);
        BOOL conflict=current.length && ![current isEqualToString:managed];
        NSUInteger assigned=0;
        NSString *folder=[root stringByAppendingPathComponent:managed];
        if(TCDirectory(folder)) for(NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]?:@[])
            if(TCName(entry) && TCRegular([folder stringByAppendingPathComponent:entry])) assigned++;
        NSMutableDictionary *row=[app mutableCopy];
        row[@"shared"]=@(shared); row[@"managedFolder"]=managed;
        row[@"selectedFolder"]=current; row[@"conflict"]=@(conflict); row[@"assigned"]=@(assigned);
        [result addObject:row];
    }
    return result;
}
+ (NSArray<NSDictionary *> *)sourcePluginsForGuest:(NSDictionary *)guest {
    if(![LCOrbitHost isHostUI] || !TCReadInfo(guest)) return @[];
    BOOL shared=TCScope(guest);
    NSString *root=TCRoot(shared),*managed=TCManagedName(guest);
    if(!TCDirectory(root)) return @[];
    NSString *assigned=[root stringByAppendingPathComponent:managed];
    NSMutableSet *names=[NSMutableSet set];
    NSArray *entries=[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]?:@[];
    for(NSString *entry in entries) {
        NSString *name=[entry hasSuffix:@".dylib.disabled"]?
           [entry substringToIndex:entry.length-9]:entry;
        if(TCName(name) && TCRegular([root stringByAppendingPathComponent:entry])) [names addObject:name];
    }
    // Never silently drop an assigned dylib just because the global source was disabled or deleted.
    for(NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:assigned error:nil]?:@[])
        if(TCName(entry) && TCRegular([assigned stringByAppendingPathComponent:entry])) [names addObject:entry];
    NSMutableArray *rows=[NSMutableArray array];
    for(NSString *name in [[names allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        NSString *source=TCFileInRoot(root,name);
        if(!source) source=[assigned stringByAppendingPathComponent:name];
        if(!TCRegular(source)) continue;
        NSString *target=[assigned stringByAppendingPathComponent:name];
        BOOL present=TCRegular(target),globalEnabled=TCRegular([root stringByAppendingPathComponent:name]);
        [rows addObject:@{@"name":name,@"assigned":@(present),
                          @"globalEnabled":@(globalEnabled),
                          @"sourceEnabled":@(globalEnabled),
                          @"source":source}];
    }
    return rows;
}
+ (NSString *)assignPluginNames:(NSArray<NSString *> *)requested toGuest:(NSDictionary *)guest {
    if(![LCOrbitHost isHostUI]) return @"只能从 LC 主界面分配插件。";
    BOOL knownGuest=NO;
    for(NSDictionary *app in [LCOrbitGuestService installedApps])
        if(![app[@"builtin"] boolValue] && [app[@"folder"] isEqualToString:guest[@"folder"]] &&
           [app[@"path"] isEqualToString:guest[@"path"]]) { knownGuest=YES; break; }
    if(!knownGuest) return @"应用不在当前 LC 的可管理清单中，未修改。";
    NSDictionary *info=TCReadInfo(guest);
    if(!info) return @"应用元数据无法读取，未修改。";
    NSString *folder=TCManagedName(guest);
    NSString *selected=[info[@"LCTweakFolder"] isKindOfClass:NSString.class]?info[@"LCTweakFolder"]:@"";
    if(selected.length && ![selected isEqualToString:folder])
        return @"此 App 已使用 LC 原有的专属插件文件夹。请先在 LC 设置中手动取消该选择，避免覆盖已有配置。";
    NSString *root=TCRoot(TCScope(guest)),*backups=TCAppBackupRoot(TCScope(guest));
    if(!root.length || !TCEnsure(root) || !backups.length) return @"插件目录不可访问。";
    NSMutableSet *valid=[NSMutableSet set];
    for(NSDictionary *row in [self sourcePluginsForGuest:guest]) [valid addObject:row[@"name"]];
    NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSet];
    for(id name in requested) {
        if(!TCName(name) || ![valid containsObject:name]) return @"存在无效插件名称，已取消操作。";
        [names addObject:name];
    }
    NSString *destination=[root stringByAppendingPathComponent:folder];
    if(TCExists(destination) && !TCDirectory(destination)) return @"托管目录不安全，已取消操作。";
    NSFileManager *fm=NSFileManager.defaultManager;
    // Stage the entire new folder, then atomically swap it into place.
    NSString *temporary=[root stringByAppendingPathComponent:
        [NSString stringWithFormat:@".%@.%@.tmp",folder,NSUUID.UUID.UUIDString]];
    NSString *oldFolder=nil;
    if(![fm createDirectoryAtPath:temporary withIntermediateDirectories:NO attributes:nil error:nil])
        return @"无法创建临时插件目录。";
    for(NSString *name in names) {
        NSString *source=TCFileInRoot(root,name);
        if(!source) source=[destination stringByAppendingPathComponent:name];
        NSString *target=[temporary stringByAppendingPathComponent:name];
        if(!TCRegular(source) || ![fm copyItemAtPath:source toPath:target error:nil] ||
           ![fm contentsEqualAtPath:source andPath:target]) {
            [fm removeItemAtPath:temporary error:nil];
            return [NSString stringWithFormat:@"%@ 复制校验失败，原配置未改变。",name];
        }
    }
    NSString *infoFile=[guest[@"folder"] stringByAppendingPathComponent:@"LCAppInfo.plist"];
    NSString *infoBackup=TCBackup(infoFile,backups,folder);
    if(!infoBackup) {
        [fm removeItemAtPath:temporary error:nil]; return @"备份应用配置失败，原配置未改变。";
    }
    if(TCDirectory(destination)) {
        oldFolder=[backups stringByAppendingPathComponent:
           [NSString stringWithFormat:@"%@.%@.folder",folder,NSUUID.UUID.UUIDString]];
        if(rename(destination.fileSystemRepresentation,oldFolder.fileSystemRepresentation)!=0) {
            [fm removeItemAtPath:temporary error:nil]; return @"备份原专属插件目录失败。";
        }
    }
    if(names.count) {
        if(rename(temporary.fileSystemRepresentation,destination.fileSystemRepresentation)!=0) {
            if(oldFolder) rename(oldFolder.fileSystemRepresentation,destination.fileSystemRepresentation);
            [fm removeItemAtPath:temporary error:nil]; return @"安装新插件目录失败，已恢复旧目录。";
        }
    } else {
        [fm removeItemAtPath:temporary error:nil];
    }
    NSMutableDictionary *next=[info mutableCopy];
    if(names.count) next[@"LCTweakFolder"]=folder;
    else [next removeObjectForKey:@"LCTweakFolder"];
    if(!TCWriteInfo(guest,next)) {
        [fm removeItemAtPath:destination error:nil];
        if(oldFolder) rename(oldFolder.fileSystemRepresentation,destination.fileSystemRepresentation);
        return @"应用配置写入失败，已尝试恢复旧目录；原配置备份已保留。";
    }
    return TCResult(@"assignment",[NSString stringWithFormat:
        @"%@：已分配 %lu 个插件。配置与旧目录均已备份。请重新启动 Guest；全局已启用插件仍会加载。",
        guest[@"title"],(unsigned long)names.count]);
}
+ (NSDictionary *)pluginInfo:(NSString *)name shared:(BOOL)shared {
    if(![LCOrbitHost isHostUI] || !TCName(name)) return @{};
    NSString *root=TCRoot(shared),*file=TCFileInRoot(root,name);
    if(!file) return @{@"exists":@NO};
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil]?:@{};
    return @{@"exists":@YES, @"enabled":@([file hasSuffix:@".dylib"]),
             @"path":file,@"size":attrs[NSFileSize]?:@0,
             @"date":attrs[NSFileModificationDate]?:NSDate.distantPast};
}
+ (NSArray<NSDictionary *> *)backupsForPlugin:(NSString *)name {
    if(![LCOrbitHost isHostUI] || !TCName(name)) return @[];
    NSMutableArray *result=[NSMutableArray array];
    for(NSNumber *shared in @[@NO,@YES]) {
        NSArray *roots=shared.boolValue?
            @[TCBackupRoot(YES),TCOldSyncBackupRoot()]:@[TCBackupRoot(NO)];
        for(NSString *root in roots) {
            if(!root.length) continue;
            for(NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]?:@[]) {
                if(![file hasPrefix:[name stringByAppendingString:@"."]] || ![file hasSuffix:@".bak"]) continue;
                NSString *path=[root stringByAppendingPathComponent:file];
                if(!TCRegular(path)) continue;
                NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil]?:@{};
                [result addObject:@{@"file":file,@"shared":shared,
                    @"size":attrs[NSFileSize]?:@0,@"date":attrs[NSFileModificationDate]?:NSDate.distantPast}];
            }
        }
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
        return [b[@"date"] compare:a[@"date"]];
    }];
    return result;
}
+ (NSString *)backupPlugin:(NSString *)name shared:(BOOL)shared {
    if(![LCOrbitHost isHostUI] || !TCName(name)) return @"无效插件名称。";
    NSString *source=TCFileInRoot(TCRoot(shared),name);
    if(!source) return @"插件不存在或不是普通文件。";
    NSString *backup=TCBackup(source,TCBackupRoot(shared),name);
    return backup?TCResult(@"backup",[NSString stringWithFormat:@"%@ 已备份：%@",name,backup.lastPathComponent]):
        @"备份失败，源文件未改动。";
}
+ (NSString *)restorePlugin:(NSString *)name backup:(NSString *)filename shared:(BOOL)shared {
    if(![LCOrbitHost isHostUI] || !TCName(name) ||
       ![filename isKindOfClass:NSString.class] ||
       ![filename isEqualToString:filename.lastPathComponent] ||
       ![filename hasPrefix:[name stringByAppendingString:@"."]] ||
       ![filename hasSuffix:@".bak"]) return @"备份名称无效。";
    NSString *root=TCBackupRoot(shared);
    NSString *from=[root stringByAppendingPathComponent:filename];
    if(shared && !TCRegular(from))
        from=[TCOldSyncBackupRoot() stringByAppendingPathComponent:filename];
    NSString *destination=TCFileInRoot(TCRoot(shared),name);
    if(!destination) destination=[TCRoot(shared) stringByAppendingPathComponent:
        [filename hasPrefix:[name stringByAppendingString:@".disabled."]]?
        [name stringByAppendingString:@".disabled"]:name];
    if(!TCRegular(from) || TCExists(destination) && !TCRegular(destination))
        return @"备份不存在或目标文件类型不安全，未恢复。";
    if(TCRegular(destination) && !TCBackup(destination,root,name))
        return @"恢复前的安全备份失败，未修改。";
    NSString *temporary=[destination stringByAppendingFormat:@".%@.tmp",NSUUID.UUID.UUIDString];
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm copyItemAtPath:from toPath:temporary error:nil] ||
       ![fm contentsEqualAtPath:from andPath:temporary] ||
       rename(temporary.fileSystemRepresentation,destination.fileSystemRepresentation)!=0) {
        [fm removeItemAtPath:temporary error:nil];return @"还原校验或写入失败。";
    }
    return TCResult(@"restore",[NSString stringWithFormat:@"%@ 已恢复备份，重新启动 Guest 后生效。",name]);
}
+ (NSString *)deleteBackup:(NSString *)name backup:(NSString *)filename shared:(BOOL)shared {
    if(![LCOrbitHost isHostUI] || !TCName(name) ||
       ![filename isKindOfClass:NSString.class] ||
       ![filename isEqualToString:filename.lastPathComponent] ||
       ![filename hasPrefix:[name stringByAppendingString:@"."]] ||
       ![filename hasSuffix:@".bak"]) return @"无效备份名称，未删除。";
    NSString *folder=TCBackupRoot(shared);
    NSString *target=[folder stringByAppendingPathComponent:filename];
    if(shared && !TCRegular(target)) target=[TCOldSyncBackupRoot() stringByAppendingPathComponent:filename];
    if(!TCRegular(target)) return @"备份不存在或不是普通文件，未删除。";
    NSError *error=nil;
    if(![NSFileManager.defaultManager removeItemAtPath:target error:&error])
        return [NSString stringWithFormat:@"删除失败：%@",error.localizedDescription?:@"未知错误"];
    return TCResult(@"delete-backup",@"指定备份已删除，不影响当前插件。");
}
+ (NSString *)deleteAllBackups:(NSString *)name {
    if(![LCOrbitHost isHostUI] || !TCName(name)) return @"无效插件名称。";
    NSArray *files=[self backupsForPlugin:name];
    NSUInteger success=0,failed=0;
    for(NSDictionary *entry in files) {
        NSString *result=[self deleteBackup:name backup:entry[@"file"] shared:[entry[@"shared"] boolValue]];
        if([result containsString:@"已删除"]) success++; else failed++;
    }
    return [NSString stringWithFormat:@"已删除 %lu 个备份，失败 %lu 个。当前插件未改动。",(unsigned long)success,(unsigned long)failed];
}
+ (NSString *)setPlugin:(NSString *)name enabled:(BOOL)enabled shared:(BOOL)shared {
    if(![LCOrbitHost isHostUI] || !TCName(name)) return @"无效插件名称。";
    if(!shared && !enabled && [name isEqualToString:@"LCFloatingMenu.dylib"])
        return @"为防止微珠管理入口失效，请从 LC 原生 Tweaks 页面手动停用宿主微珠。";
    NSString *root=TCRoot(shared),*active=[root stringByAppendingPathComponent:name];
    NSString *disabled=[active stringByAppendingString:@".disabled"];
    NSString *source=enabled?disabled:active,*target=enabled?active:disabled;
    if(!TCRegular(source) || TCExists(target)) return @"找不到待切换插件，或目标文件已存在。";
    if(!TCBackup(source,TCBackupRoot(shared),name)) return @"启停前备份失败，未修改。";
    if(rename(source.fileSystemRepresentation,target.fileSystemRepresentation)!=0)
        return @"无法切换插件状态。";
    return TCResult(@"toggle",[NSString stringWithFormat:@"%@ 已%@。请重启 Guest；全局目录与专属目录彼此独立。",
        name,enabled?@"启用":@"停用"]);
}
@end
