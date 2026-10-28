#import "LCOrbitStorage.h"
#import "LCOrbitHost.h"
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>

static NSError *StorageError;
static NSMutableDictionary<NSString *,NSDictionary *> *LastGood;
static const NSUInteger MaximumConfigSize=1048576;
static BOOL PluginKey(id key) {
    return [key isKindOfClass:NSString.class] &&
        ![key isEqualToString:@"LCFloatingMenu.previousMultitaskMode"] &&
        ([key hasPrefix:@"LCFloatingMenu."] || [key hasPrefix:@"LCOrbit.module."]);
}
static BOOL JSONValue(id value) {
    if([value isKindOfClass:NSString.class]) return YES;
    if([value isKindOfClass:NSNumber.class]) return isfinite([value doubleValue]);
    if([value isKindOfClass:NSArray.class]) {
        for(id item in value) if(!JSONValue(item)) return NO;
        return YES;
    }
    if([value isKindOfClass:NSDictionary.class]) {
        for(id key in value) if(![key isKindOfClass:NSString.class] || !JSONValue(value[key])) return NO;
        return YES;
    }
    return NO;
}
static BOOL PreferenceValue(NSString *key,id value) {
    if(!JSONValue(value)) return NO;
    NSString *name=[key hasPrefix:@"LCFloatingMenu."]?[key substringFromIndex:15]:key;
    if([@[@"favoritePaths",@"menuOrder"] containsObject:name]) {
        if(![value isKindOfClass:NSArray.class]) return NO;
        for(id item in value) if(![item isKindOfClass:NSString.class]) return NO;
    } else if([@[@"accentLight",@"accentDark"] containsObject:name]) {
        return [value isKindOfClass:NSString.class];
    } else if([key hasPrefix:@"LCOrbit.module."] ||
              [@[@"fullscreenMultitask",@"systemMultitaskMenu",@"autoSyncSharedTweaks",@"idleAlpha",@"orbScale",@"orbWidth",@"orbY",@"onLeft",@"roundOrb",@"autoFade",@"haptic",@"confirm",@"showRestart",@"compactRestart",@"compactMode",@"panelScale",@"glassTint",@"clearGlass",@"appearanceMode",@"preferDarkIcons"] containsObject:name] ||
              [name hasPrefix:@"appAlpha."] || [name hasPrefix:@"override."] ||
              [name hasPrefix:@"doubleTap."] || [name hasPrefix:@"stealth."] || [name hasPrefix:@"appEnabled."]) {
        return [value isKindOfClass:NSNumber.class];
    }
    return YES;
}
static NSError *Error(NSString *description) {
    return [NSError errorWithDomain:@"LCOrbitStorage" code:1 userInfo:@{NSLocalizedDescriptionKey:description}];
}
static NSDictionary *LegacyValues(void) {
    NSDictionary *legacy=[[LCOrbitHost hostDefaults] dictionaryRepresentation];
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    for(NSString *key in legacy) if(PluginKey(key) && PreferenceValue(key,legacy[key])) values[key]=legacy[key];
    return values;
}
static NSString *ConfigPath(NSString *root) { return [root stringByAppendingPathComponent:@"config.json"]; }
static NSString *BackupPath(NSString *root) { return [root stringByAppendingPathComponent:@"config.last-good.json"]; }
static NSDictionary *ReadDocument(NSString *file,NSError **error) {
    struct stat info;
    if(lstat(file.fileSystemRepresentation,&info)!=0 || !S_ISREG(info.st_mode) || info.st_size<0 || (unsigned long long)info.st_size>MaximumConfigSize) {
        if(error) *error=Error(@"配置文件不可读取、不是普通文件或超过 1 MiB。");
        return nil;
    }
    NSData *data=[NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:error];
    id document=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:error]:nil;
    if(![document isKindOfClass:NSDictionary.class] ||
       ![document[@"schemaVersion"] isKindOfClass:NSNumber.class] ||
       [document[@"schemaVersion"] doubleValue]!=1 ||
       ![document[@"preferences"] isKindOfClass:NSDictionary.class]) {
        if(error && !*error) *error=Error(@"配置 JSON 格式或版本不受支持。");
        return nil;
    }
    NSDictionary *values=document[@"preferences"];
    for(id key in values) if(!PluginKey(key) || !PreferenceValue(key,values[key])) {
        if(error) *error=Error(@"配置包含不允许的键或不正确的值类型。");
        return nil;
    }
    return values;
}
static NSData *DocumentData(NSDictionary *values,NSError **error) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"schemaVersion":@1,@"preferences":values}
        options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:error];
    if(data.length>MaximumConfigSize) {
        if(error) *error=Error(@"配置超过 1 MiB，未写入。");
        return nil;
    }
    return data;
}
static BOOL WriteDocument(NSString *path,NSDictionary *values,NSError **error) {
    struct stat info;
    if(lstat(path.fileSystemRepresentation,&info)==0 && !S_ISREG(info.st_mode)) {
        if(error) *error=Error(@"配置目标不是普通文件，未写入。");
        return NO;
    }
    NSData *data=DocumentData(values,error);
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error];
}
static int LockRoot(NSString *root,NSError **error) {
    if(!root.length || ![NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error]) return -1;
    struct stat info;
    if(lstat(root.fileSystemRepresentation,&info)!=0 || !S_ISDIR(info.st_mode)) {
        if(error) *error=Error(@"LCOrbit 配置目录不安全。");
        return -1;
    }
    NSString *path=[root stringByAppendingPathComponent:@".config.lock"];
    int lock=open(path.fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(lock<0 || flock(lock,LOCK_EX)!=0) {
        if(lock>=0) close(lock);
        if(error) *error=Error(@"无法锁定 LCOrbit 配置文件。");
        return -1;
    }
    return lock;
}
static void Unlock(int lock) { flock(lock,LOCK_UN);close(lock); }
// Called with process and file locks. Invalid existing documents stay untouched.
static NSDictionary *Load(NSString *root,BOOL *valid,NSError **error) {
    if(!LastGood) LastGood=[NSMutableDictionary dictionary];
    NSString *path=ConfigPath(root);struct stat info;NSDictionary *values=nil;
    if(lstat(path.fileSystemRepresentation,&info)!=0) {
        values=ReadDocument(BackupPath(root),nil) ?: LastGood[root] ?: LegacyValues();
        *valid=WriteDocument(path,values,error);
    } else {
        values=ReadDocument(path,error);*valid=values!=nil;
    }
    if(*valid) {
        LastGood[root]=[values copy];
        NSDictionary *backup=ReadDocument(BackupPath(root),nil);
        if(![backup isEqual:values]) WriteDocument(BackupPath(root),values,nil);
        return values;
    }
    NSDictionary *recovered=ReadDocument(BackupPath(root),nil) ?: LastGood[root] ?: LegacyValues();
    LastGood[root]=[recovered copy];
    return recovered;
}
static NSDictionary *ReadValues(void) {
    @synchronized(LCOrbitStorage.class) {
        NSError *error=nil;NSString *root=[LCOrbitStorage rootPath];int lock=LockRoot(root,&error);
        if(lock<0) {
            StorageError=error?:Error(@"无法访问 LC 宿主配置目录。");
            return (root?LastGood[root]:nil) ?: LegacyValues();
        }
        BOOL valid=NO;NSDictionary *values=Load(root,&valid,&error);
        Unlock(lock);StorageError=error;return values;
    }
}
@implementation LCOrbitPreferences
- (id)objectForKey:(NSString *)key {
    if(!PluginKey(key)) return [[LCOrbitHost hostDefaults] objectForKey:key];
    return ReadValues()[key];
}
- (void)setObject:(id)value forKey:(NSString *)key {
    if(!PluginKey(key)) {
        if(value) [[LCOrbitHost hostDefaults] setObject:value forKey:key];
        else [[LCOrbitHost hostDefaults] removeObjectForKey:key];
        return;
    }
    @synchronized(LCOrbitStorage.class) {
        if(value && !PreferenceValue(key,value)) { StorageError=Error(@"配置值类型不正确，未保存。");return; }
        NSError *error=nil;NSString *root=[LCOrbitStorage rootPath];int lock=LockRoot(root,&error);
        if(lock<0) {
            // A warm JSON configuration must not split into a second, stale
            // preference backend when its directory temporarily disappears.
            if(!root || !LastGood[root]) {
                if(value) [[LCOrbitHost hostDefaults] setObject:value forKey:key];
                else [[LCOrbitHost hostDefaults] removeObjectForKey:key];
            }
            StorageError=error?:Error(@"无法访问 LC 宿主配置目录，JSON 配置未保存。");return;
        }
        BOOL valid=NO;NSDictionary *current=Load(root,&valid,&error);
        if(valid) {
            NSMutableDictionary *next=[current mutableCopy];
            if(value) next[key]=value;else [next removeObjectForKey:key];
            if(WriteDocument(ConfigPath(root),next,&error)) {
                LastGood[root]=[next copy];WriteDocument(BackupPath(root),next,nil);
            }
        }
        Unlock(lock);StorageError=error;
    }
}
- (void)removeObjectForKey:(NSString *)key { [self setObject:nil forKey:key]; }
- (BOOL)boolForKey:(NSString *)key { id value=[self objectForKey:key];return [value respondsToSelector:@selector(boolValue)]?[value boolValue]:NO; }
- (NSInteger)integerForKey:(NSString *)key { id value=[self objectForKey:key];return [value respondsToSelector:@selector(integerValue)]?[value integerValue]:0; }
- (double)doubleForKey:(NSString *)key { id value=[self objectForKey:key];return [value respondsToSelector:@selector(doubleValue)]?[value doubleValue]:0; }
- (NSString *)stringForKey:(NSString *)key { id value=[self objectForKey:key];return [value isKindOfClass:NSString.class]?value:nil; }
- (NSArray *)arrayForKey:(NSString *)key { id value=[self objectForKey:key];return [value isKindOfClass:NSArray.class]?value:nil; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (NSDictionary *)dictionaryRepresentation { return ReadValues(); }
- (BOOL)synchronize { return [LCOrbitStorage reloadWithError:nil]; }
@end
@implementation LCOrbitStorage
+ (NSString *)key:(NSString *)key forModule:(NSString *)identifier { return [NSString stringWithFormat:@"%@.%@",identifier,key]; }
+ (id)objectForKey:(NSString *)key module:(NSString *)identifier { return [[self preferences] objectForKey:[self key:key forModule:identifier]]; }
+ (void)setObject:(id)object forKey:(NSString *)key module:(NSString *)identifier { [[self preferences] setObject:object forKey:[self key:key forModule:identifier]]; }
+ (NSString *)rootPath {
    const char *raw=getenv("LC_HOME_PATH");if(!raw || !raw[0]) return nil;
    return [[NSString stringWithUTF8String:raw] stringByAppendingPathComponent:@"Documents/LCOrbit"];
}
+ (LCOrbitPreferences *)preferences {
    static LCOrbitPreferences *preferences;static dispatch_once_t once;
    dispatch_once(&once,^{preferences=[LCOrbitPreferences new];});return preferences;
}
+ (BOOL)reloadWithError:(NSError **)error {
    @synchronized(self) { ReadValues();if(error) *error=StorageError;return StorageError==nil; }
}
+ (NSError *)lastError { @synchronized(self) { return StorageError; } }
@end
