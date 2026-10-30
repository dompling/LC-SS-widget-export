#import "LCOrbitGitHub.h"
#import "LCOrbitHost.h"
#import <Security/Security.h>
#import <dlfcn.h>

static NSError *GHError(NSInteger code,NSString *message) {
    return [NSError errorWithDomain:@"LCOrbit.GitHub" code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL GHFail(NSError **error,NSInteger code,NSString *message) {
    if(error) *error=GHError(code,message);
    return NO;
}
static BOOL GHHost(NSError **error) {
    return [LCOrbitHost isHostUI] || GHFail(error,1,@"请返回 LC 主界面配置 GitHub 访问。");
}
static NSMutableDictionary *GHQuery(NSError **error) {
    // LC's first/default keychain group is shared with Guest processes.
    // Use the signed application's own identifier for every operation.
    CFTypeRef (*createTask)(CFAllocatorRef)=dlsym(RTLD_DEFAULT,"SecTaskCreateFromSelf");
    CFTypeRef (*copyEntitlement)(CFTypeRef,CFStringRef,CFErrorRef *)=
        dlsym(RTLD_DEFAULT,"SecTaskCopyValueForEntitlement");
    CFTypeRef task=createTask?createTask(NULL):NULL;
    id group=task && copyEntitlement?CFBridgingRelease(copyEntitlement(task,CFSTR("application-identifier"),NULL)):nil;
    if(task) CFRelease(task);
    if(![group isKindOfClass:NSString.class] || ![group length] ||
       [group rangeOfString:@"*"].location!=NSNotFound) {
        GHFail(error,7,@"无法确定 LC 的私有钥匙串访问组，未读取或保存 GitHub 凭据。");return nil;
    }
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:@"com.lcorbit.github",
              (__bridge id)kSecAttrAccount:@"credentials",
              (__bridge id)kSecAttrAccessGroup:group,
              (__bridge id)kSecAttrSynchronizable:@NO} mutableCopy];
}
static BOOL GHValidToken(id token) {
    if(![token isKindOfClass:NSString.class] || ![token length] || [token length]>4096) return NO;
    for(NSUInteger i=0;i<[token length];i++) {
        unichar c=[token characterAtIndex:i];
        if(c<33 || c>126) return NO;
    }
    return YES;
}
static BOOL GHValidAccount(id account) {
    if(![account isKindOfClass:NSString.class]) return NO;
    if(![account length]) return YES;
    NSString *pattern=@"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$";
    return [account rangeOfString:pattern options:NSRegularExpressionSearch].location!=NSNotFound &&
        [account rangeOfString:@"--"].location==NSNotFound;
}
static NSDictionary *GHRead(NSError **error) {
    if(!GHHost(error)) return nil;
    NSMutableDictionary *query=GHQuery(error);
    if(!query) return nil;
    query[(__bridge id)kSecReturnData]=@YES;
    query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    CFTypeRef result=NULL;
    OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);
    id data=CFBridgingRelease(result);
    if(status==errSecItemNotFound) return @{};
    if(status!=errSecSuccess) {
        GHFail(error,status,@"无法读取 GitHub 钥匙串配置，请解锁设备并确认 LC 的签名权限。");return nil;
    }
    id record=[data isKindOfClass:NSData.class]?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![record isKindOfClass:NSDictionary.class] || !GHValidAccount(record[@"account"]) ||
       !GHValidToken(record[@"token"])) {
        GHFail(error,2,@"GitHub 钥匙串配置已损坏，请清除后重新设置。");return nil;
    }
    return record;
}
static BOOL GHAPIURL(NSURL *url) {
    return [url.scheme.lowercaseString isEqualToString:@"https"] &&
        [url.host.lowercaseString isEqualToString:@"api.github.com"] &&
        (!url.port || url.port.integerValue==443) && !url.user && !url.password && !url.fragment;
}

@interface LCOrbitGitHubSessionDelegate : NSObject <NSURLSessionTaskDelegate>
@end
@implementation LCOrbitGitHubSessionDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if(!GHAPIURL(request.URL)) {completionHandler(nil);return;}
    NSMutableURLRequest *next=[request mutableCopy];
    // Preserve only this request's token across same-origin API redirects.
    // Never follow to a CDN, web login, different port, or plaintext HTTP.
    [next setValue:[LCOrbitHost isHostUI]?[task.currentRequest valueForHTTPHeaderField:@"Authorization"]:nil
        forHTTPHeaderField:@"Authorization"];
    next.HTTPShouldHandleCookies=NO;
    completionHandler(next);
}
@end

@implementation LCOrbitGitHub
+ (NSString *)accountWithError:(NSError **)error {
    return GHRead(error)[@"account"];
}
+ (BOOL)hasTokenWithError:(NSError **)error {
    return [GHRead(error)[@"token"] length]>0;
}
+ (BOOL)saveAccount:(NSString *)account token:(NSString *)token error:(NSError **)error {
    if(!GHHost(error)) return NO;
    if(![account isKindOfClass:NSString.class] || ![token isKindOfClass:NSString.class])
        return GHFail(error,3,@"请输入有效的 GitHub 账号和 Token。");
    account=[account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    token=[token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!GHValidAccount(account)) return GHFail(error,4,@"请输入 GitHub 用户名，不要填写邮箱或网址。账号也可以留空。");
    @synchronized(self) {
        if(!token.length) {
            NSDictionary *previous=GHRead(error);
            if(!previous) return NO;
            token=previous[@"token"];
        }
        if(!GHValidToken(token)) return GHFail(error,5,@"请输入有效的 Token 原文，不要添加 Bearer 前缀或空白字符。");
        NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"account":account,@"token":token} options:0 error:nil];
        NSDictionary *attributes=@{(__bridge id)kSecValueData:data,
            (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
        NSMutableDictionary *query=GHQuery(error);
        if(!query) return NO;
        OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)attributes);
        if(status==errSecItemNotFound) {
            NSMutableDictionary *addition=[query mutableCopy];[addition addEntriesFromDictionary:attributes];
            status=SecItemAdd((__bridge CFDictionaryRef)addition,NULL);
            if(status==errSecDuplicateItem)
                status=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)attributes);
        }
        if(status!=errSecSuccess) return GHFail(error,status,@"保存 GitHub 配置失败，原配置仍保留。请检查 LC 的钥匙串签名权限。");
        return YES;
    }
}
+ (BOOL)clearCredentialsWithError:(NSError **)error {
    if(!GHHost(error)) return NO;
    @synchronized(self) {
        NSDictionary *query=GHQuery(error);
        if(!query) return NO;
        OSStatus status=SecItemDelete((__bridge CFDictionaryRef)query);
        return status==errSecSuccess || status==errSecItemNotFound ||
            GHFail(error,status,@"清除 GitHub 配置失败，原配置仍保留。请检查 LC 的钥匙串签名权限。");
    }
}
+ (NSMutableURLRequest *)requestForURL:(NSURL *)url timeout:(NSTimeInterval)timeout error:(NSError **)error {
    if(!GHAPIURL(url)) {
        GHFail(error,6,@"GitHub 请求仅允许通过 HTTPS 访问 api.github.com。");return nil;
    }
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout];
    request.HTTPShouldHandleCookies=NO;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"LCFloatingMenu" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    if([LCOrbitHost isHostUI]) {
        NSDictionary *record=GHRead(error);
        if(!record) return nil;
        NSString *token=record[@"token"];
        if(token.length) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    }
    return request;
}
+ (void)performRequest:(NSURLRequest *)request
           completion:(void (^)(NSData *,NSHTTPURLResponse *,NSError *))completion {
    if(!GHAPIURL(request.URL) || ![request.HTTPMethod isEqualToString:@"GET"]) {
        completion(nil,nil,GHError(6,@"GitHub 请求仅允许通过 HTTPS 读取 api.github.com。"));return;
    }
    NSMutableURLRequest *safe=[request mutableCopy];
    safe.HTTPShouldHandleCookies=NO;
    if(![LCOrbitHost isHostUI]) [safe setValue:nil forHTTPHeaderField:@"Authorization"];
    NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.HTTPCookieStorage=nil;
    configuration.URLCredentialStorage=nil;
    configuration.URLCache=nil;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration
        delegate:[LCOrbitGitHubSessionDelegate new] delegateQueue:nil];
    [[session dataTaskWithRequest:safe completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        [session finishTasksAndInvalidate];
        // Do not forward networking userInfo (which can contain the request).
        NSError *failure=error?GHError(error.code,@"GitHub 请求失败，请检查网络连接后重试。"):nil;
        completion(data,[response isKindOfClass:NSHTTPURLResponse.class]?(NSHTTPURLResponse *)response:nil,failure);
    }] resume];
}
+ (NSString *)messageForStatusCode:(NSInteger)status {
    if(status==401) return @"GitHub Token 无效或已过期，请在 GitHub 访问中重新设置。";
    if(status==403) return @"GitHub 拒绝访问，请检查 Token 权限、组织授权或请求额度。";
    if(status==429) return @"GitHub 请求过于频繁，请稍后重试。";
    return [NSString stringWithFormat:@"GitHub 请求未成功（HTTP %ld），请稍后重试。",(long)status];
}
@end
