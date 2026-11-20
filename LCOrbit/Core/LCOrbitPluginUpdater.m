#import "LCOrbitPluginUpdater.h"
#import "LCOrbitHost.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/loader.h>
#import <mach/machine.h>
#import <sys/stat.h>
#import <errno.h>
#import <stdio.h>
#import <objc/message.h>
#import <dlfcn.h>

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
// Accessed only on the main queue; signing has one completion owner.
static BOOL UAutomaticSigningInProgress=NO;
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
+ (void)installDownloadedPluginAndSign:(NSData *)binary
                      expectedSHA256:(NSString *)digest
                           completion:(void (^)(BOOL,NSError *))completion {
    // Installation, signing, and rollback are one transaction. The existing
    // synchronous installer is retained for its separately tested atomic file
    // replacement, but the updater UI only uses this signed transaction.
    dispatch_async(dispatch_get_main_queue(), ^{
        if(UAutomaticSigningInProgress) {
            if(completion) completion(NO,UErr(10,@"已有插件更新正在签名，请勿重复安装。"));
            return;
        }
        if(![LCOrbitHost isHostUI]) {
            if(completion) completion(NO,UErr(7,@"仅 LC 主界面允许自动签名。"));
            return;
        }
        // Never replace first and discover afterward that the signer is absent.
        Class utils=NSClassFromString(@"LCUtils");
        Class shared=NSClassFromString(@"LCSharedUtils");
        SEL sign=NSSelectorFromString(@"signFilesWithZSignWithURLs:completionHandler:");
        SEL certificate=NSSelectorFromString(@"certificateData");
        SEL password=NSSelectorFromString(@"certificatePassword");
        BOOL (*verifySignature)(const char *)=(BOOL (*)(const char *))dlsym(RTLD_DEFAULT,"checkCodeSignature");
        if(!utils || !shared || ![utils respondsToSelector:sign] ||
           ![utils respondsToSelector:certificate] || ![shared respondsToSelector:password] ||
           !verifySignature) {
            if(completion) completion(NO,UErr(11,@"当前 LC 未提供可验证的原生 ZSign 签名接口，请使用 LC Tweaks 页面签名。"));
            return;
        }
        NSData *cert=((id(*)(id,SEL))objc_msgSend)(utils,certificate);
        NSString *pass=((id(*)(id,SEL))objc_msgSend)(shared,password);
        if(![cert isKindOfClass:NSData.class] || !cert.length ||
           ![pass isKindOfClass:NSString.class] || !pass.length) {
            if(completion) completion(NO,UErr(12,@"LC 未配置有效的签名证书或密码。旧插件未被替换。"));
            return;
        }
        const char *root=getenv("LC_HOME_PATH");
        if(!root || !root[0]) {
            if(completion) completion(NO,UErr(8,@"无法找到 LC 私有插件目录。"));
            return;
        }
        NSString *destination=[[[NSString stringWithUTF8String:root]
            stringByAppendingPathComponent:@"Documents/Tweaks"]
            stringByAppendingPathComponent:@"LCFloatingMenu.dylib"];
        if(!URegular(destination) || !UBinaryIsPlugin(binary) ||
           !UHasMatchingDigest(binary,digest)) {
            if(completion) completion(NO,UErr(13,@"插件路径、二进制或 SHA-256 校验无效，旧插件未被修改。"));
            return;
        }
        // Keep a temporary original in the same directory until ZSign and the
        // kernel signature verifier both succeed. The .rollback extension is
        // deliberately not .dylib, so LC's loader cannot pick it up.
        NSString *backup=[destination stringByAppendingFormat:@".%@.rollback",NSUUID.UUID.UUIDString];
        NSError *copyError=nil;
        if(![NSFileManager.defaultManager copyItemAtPath:destination toPath:backup error:&copyError] ||
           !URegular(backup)) {
            if(completion) completion(NO,copyError?:UErr(14,@"无法保留原插件，已取消更新。"));
            return;
        }
        UAutomaticSigningInProgress=YES;
        NSError *installError=nil;
        if(![self installDownloadedPlugin:binary expectedSHA256:digest error:&installError]) {
            [NSFileManager.defaultManager removeItemAtPath:backup error:nil];
            UAutomaticSigningInProgress=NO;
            if(completion) completion(NO,installError?:UErr(15,@"替换失败。"));
            return;
        }
        __block BOOL completed=NO;
        void (^signedResult)(BOOL,NSError *)=^(BOOL success,NSError *signError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(completed) return;
                completed=YES;
                BOOL valid=success && URegular(destination) &&
                    UBinaryIsPlugin([NSData dataWithContentsOfFile:destination]) &&
                    verifySignature(destination.fileSystemRepresentation);
                if(valid) {
                    [NSFileManager.defaultManager removeItemAtPath:backup error:nil];
                    UAutomaticSigningInProgress=NO;
                    if(completion) completion(YES,nil);
                    return;
                }
                BOOL restored=rename(backup.fileSystemRepresentation,
                                     destination.fileSystemRepresentation)==0;
                UAutomaticSigningInProgress=NO;
                if(completion) completion(NO,restored?
                    UErr(16,[NSString stringWithFormat:@"自动签名失败，已恢复旧插件。%@",
                        signError.localizedDescription?:@"请检查证书与 LC 签名权限。"]):
                    UErr(17,[NSString stringWithFormat:@"自动签名和回滚均失败！原插件保留在：%@",backup]));
            });
        };
        @try {
            ((id(*)(id,SEL,NSArray *,id))objc_msgSend)(utils,sign,
                @[[NSURL fileURLWithPath:destination]],signedResult);
        } @catch(NSException *exception) {
            signedResult(NO,UErr(18,@"LC 签名接口执行异常。"));
        }
    });
}
@end
