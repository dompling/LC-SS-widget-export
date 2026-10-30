#import "LCOrbitPluginUpdater.h"
#import "LCOrbitHost.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/loader.h>
#import <mach/machine.h>
#import <sys/stat.h>
#import <errno.h>
#import <stdio.h>

static BOOL URegular(NSString *p) {
    struct stat s;
    return p.length && lstat(p.fileSystemRepresentation,&s)==0 && S_ISREG(s.st_mode);
}
static NSError *UErr(NSInteger code,NSString *message) {
    return [NSError errorWithDomain:@"LCOrbit.PluginUpdate" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL UFail(NSError **error,NSInteger code,NSString *message) {
    if(error) *error=UErr(code,message);
    return NO;
}
static BOOL UBinaryIsPlugin(NSData *binary) {
    if(binary.length<sizeof(struct mach_header_64) || binary.length>16*1024*1024) return NO;
    const uint8_t *bytes=binary.bytes;
    const struct mach_header_64 *header=(const void *)bytes;
    if(header->magic!=MH_MAGIC_64 || header->cputype!=CPU_TYPE_ARM64 || header->filetype!=MH_DYLIB)
        return NO;
    NSUInteger offset=sizeof(*header);
    if(header->sizeofcmds>binary.length-offset || header->ncmds>10000) return NO;
    NSUInteger commandsEnd=offset+header->sizeofcmds;
    BOOL expectedInstallName=NO;
    for(uint32_t i=0;i<header->ncmds;i++) {
        if(offset+sizeof(struct load_command)>commandsEnd) return NO;
        const struct load_command *command=(const void *)(bytes+offset);
        if(command->cmdsize<sizeof(*command) || command->cmdsize>commandsEnd-offset) return NO;
        if(command->cmd==LC_ID_DYLIB) {
            if(command->cmdsize<sizeof(struct dylib_command)) return NO;
            const struct dylib_command *dylib=(const void *)command;
            NSUInteger pos=dylib->dylib.name.offset;
            if(pos>=command->cmdsize) return NO;
            const char *name=(const char *)command+pos;
            const char *end=memchr(name,0,command->cmdsize-pos);
            if(!end) return NO;
            expectedInstallName=strcmp(name,"@rpath/LCFloatingMenu.dylib")==0;
        }
        offset+=command->cmdsize;
    }
    return expectedInstallName;
}
static BOOL UHasMatchingDigest(NSData *binary,NSString *digest) {
    if(![digest isKindOfClass:NSString.class] || digest.length!=71 ||
       ![digest hasPrefix:@"sha256:"]) return NO;
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(binary.bytes,(CC_LONG)binary.length,hash);
    NSMutableString *hex=[NSMutableString stringWithCapacity:64];
    for(NSUInteger i=0;i<sizeof(hash);i++) [hex appendFormat:@"%02x",hash[i]];
    return [digest.lowercaseString isEqualToString:[@"sha256:" stringByAppendingString:hex]];
}
@implementation LCOrbitPluginUpdater
+ (BOOL)replacePluginData:(NSData *)binary expectedSHA256:(NSString *)digest
             destination:(NSString *)destination
                   error:(NSError **)error {
    if(!UBinaryIsPlugin(binary)) return UFail(error,1,@"下载的文件不是有效的 arm64 LCFloatingMenu.dylib。");
    if(!UHasMatchingDigest(binary,digest)) return UFail(error,2,@"SHA-256 校验失败，已拒绝安装。");
    if(![destination.lastPathComponent isEqualToString:@"LCFloatingMenu.dylib"] ||
       !URegular(destination)) return UFail(error,3,@"原插件不是预期的普通文件，未进行替换。");
    struct stat old;
    if(lstat(destination.fileSystemRepresentation,&old)!=0) return UFail(error,4,@"无法读取原插件信息。");
    NSFileManager *fm=NSFileManager.defaultManager;
    // Verify a staged file, then atomically replace the destination. Until
    // rename succeeds, the old dylib remains intact; no .bak is created.
    NSString *temporary=[destination stringByAppendingFormat:@".%@.tmp",NSUUID.UUID.UUIDString];
    if(![binary writeToFile:temporary options:NSDataWritingAtomic error:error]) {
        [fm removeItemAtPath:temporary error:nil];
        return NO;
    }
    BOOL prepared=chmod(temporary.fileSystemRepresentation,old.st_mode&0777)==0 &&
        URegular(temporary) && [fm attributesOfItemAtPath:temporary error:nil]!=nil &&
        UHasMatchingDigest([NSData dataWithContentsOfFile:temporary],digest);
    if(!prepared || rename(temporary.fileSystemRepresentation,destination.fileSystemRepresentation)!=0) {
        [fm removeItemAtPath:temporary error:nil];
        return UFail(error,6,@"替换插件失败，旧插件未被覆盖；备份已保留。");
    }
    return YES;
}
+ (BOOL)installDownloadedPlugin:(NSData *)binary expectedSHA256:(NSString *)digest error:(NSError **)error {
    if(![LCOrbitHost isHostUI]) return UFail(error,7,@"请在 LC 主界面的微珠设置中心更新插件。");
    const char *root=getenv("LC_HOME_PATH");
    if(!root || !root[0]) return UFail(error,8,@"无法找到 LC 私有插件目录，未进行替换。");
    NSString *home=[NSString stringWithUTF8String:root];
    NSString *directory=[home stringByAppendingPathComponent:@"Documents/Tweaks"];
    NSString *destination=[directory stringByAppendingPathComponent:@"LCFloatingMenu.dylib"];
    // Only replace a plugin actually loaded from LC's own private Tweaks root.
    // Never tamper with a bundle, an assigned guest folder, or shared LC root.
    if(!URegular(destination)) return UFail(error,9,@"未在 LC 私有插件目录找到微珠，请通过原生 Tweaks 页面安装一次。");
    return [self replacePluginData:binary expectedSHA256:digest
                      destination:destination error:error];
}
@end
