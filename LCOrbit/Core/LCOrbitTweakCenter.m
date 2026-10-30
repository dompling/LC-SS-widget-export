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
    NSString *root=TCRoot(TCScope(guest));
    if(!root.length || !TCEnsure(root)) return @"插件目录不可访问。";
    NSMutableSet *valid=[NSMutableSet set];
    for(NSDictionary *row in [self sourcePluginsForGuest:guest]) [valid addObject:row[@"name"]];
    NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSet];
    for(id name in requested) {
        if(!TCName(name) || ![valid containsObject:name]) return @"存在无效插件名称，已取消操作。";
        [names addObject:name];
    }
    NSString *destination=[root stringByAppendingPathComponent:folder];
    if(TCExists(destination) && !TCDirectory(destination)) return @"托管目录不安全，已取消操作。";
    NSString *infoFile=[guest[@"folder"] stringByAppendingPathComponent:@"LCAppInfo.plist"];
    // Keep the original plist only in memory; never create a permanent backup file.
    NSData *originalInfo=[NSData dataWithContentsOfFile:infoFile options:0 error:nil];
    if(!originalInfo.length) return @"无法读取原应用配置，未修改插件。";
    NSFileManager *fm=NSFileManager.defaultManager;
    // Stage the new directory next to its destination to allow atomic rename.
    NSString *temporary=[root stringByAppendingPathComponent:
        [NSString stringWithFormat:@".%@.%@.tmp",folder,NSUUID.UUID.UUIDString]];
    NSString *rollbackFolder=nil;
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
    if(TCDirectory(destination)) {
        rollbackFolder=[root stringByAppendingPathComponent:
            [NSString stringWithFormat:@".%@.%@.rollback.tmp",folder,NSUUID.UUID.UUIDString]];
        if(rename(destination.fileSystemRepresentation,rollbackFolder.fileSystemRepresentation)!=0) {
            [fm removeItemAtPath:temporary error:nil];
            return @"暂存原插件目录失败，原配置未改变。";
        }
    }
    if(names.count) {
        if(rename(temporary.fileSystemRepresentation,destination.fileSystemRepresentation)!=0) {
            BOOL restored=!rollbackFolder ||
                rename(rollbackFolder.fileSystemRepresentation,destination.fileSystemRepresentation)==0;
            [fm removeItemAtPath:temporary error:nil];
            return restored?@"安装新插件目录失败，原目录已恢复。":
                @"安装新插件目录失败，恢复旧目录也失败；旧目录仍保留在临时回滚路径。";
        }
    } else {
        [fm removeItemAtPath:temporary error:nil];
    }
    NSMutableDictionary *next=[info mutableCopy];
    if(names.count) next[@"LCTweakFolder"]=folder;
    else [next removeObjectForKey:@"LCTweakFolder"];
    if(!TCWriteInfo(guest,next)) {
        BOOL folderRestored=YES;
        if(names.count && TCExists(destination))
            folderRestored=[fm removeItemAtPath:destination error:nil];
        if(rollbackFolder)
            folderRestored=(rename(rollbackFolder.fileSystemRepresentation,
                                   destination.fileSystemRepresentation)==0) && folderRestored;
        NSData *currentInfo=[NSData dataWithContentsOfFile:infoFile options:0 error:nil];
        BOOL infoRestored=[originalInfo isEqualToData:currentInfo] ||
            [originalInfo writeToFile:infoFile options:NSDataWritingAtomic error:nil];
        return (folderRestored && infoRestored)?
            @"应用配置写入失败，已恢复原插件目录和配置。":
            @"应用配置写入失败，自动恢复未完全成功；请检查临时回滚目录和应用配置。";
    }
    // The old directory is needed only until the plist commit succeeds.
    if(rollbackFolder && ![fm removeItemAtPath:rollbackFolder error:nil])
        return TCResult(@"assignment", [NSString stringWithFormat:
            @"%@：插件分配已完成，但旧目录的临时回滚文件清理失败。请检查插件目录。",guest[@"title"]]);
    return TCResult(@"assignment",[NSString stringWithFormat:
        @"%@：已分配 %lu 个插件。旧托管目录已清理。请重新启动 Guest；全局已启用插件仍会加载。",
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
+ (NSString *)setPlugin:(NSString *)name enabled:(BOOL)enabled shared:(BOOL)shared {
    if(![LCOrbitHost isHostUI] || !TCName(name)) return @"无效插件名称。";
    if(!shared && !enabled && [name isEqualToString:@"LCFloatingMenu.dylib"])
        return @"为防止微珠管理入口失效，请从 LC 原生 Tweaks 页面手动停用宿主微珠。";
    NSString *root=TCRoot(shared),*active=[root stringByAppendingPathComponent:name];
    NSString *disabled=[active stringByAppendingString:@".disabled"];
    NSString *source=enabled?disabled:active,*target=enabled?active:disabled;
    if(!TCRegular(source) || TCExists(target)) return @"找不到待切换插件，或目标文件已存在。";
    if(rename(source.fileSystemRepresentation,target.fileSystemRepresentation)!=0)
        return @"无法切换插件状态。";
    return TCResult(@"toggle",[NSString stringWithFormat:@"%@ 已%@。请重启 Guest；全局目录与专属目录彼此独立。",
        name,enabled?@"启用":@"停用"]);
}
@end
