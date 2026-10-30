#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "../Core/LCOrbitHost.h"
#import "../Core/LCOrbitGitHub.h"

static BOOL IsHost=YES;
static NSData *Saved;
static NSDictionary *LastWrite;
static OSStatus ReadStatus=errSecSuccess,WriteStatus=errSecSuccess,DeleteStatus=errSecSuccess;
static NSUInteger Reads,Checks,Failures,UnsafeQueries;
static NSString *AppIdentifier=@"TEAM.fixture.LC";
static BOOL MissingEntitlements;
static void CaptureQuery(CFDictionaryRef raw) {
    NSDictionary *query=(__bridge NSDictionary *)raw;
    if(![query[(__bridge id)kSecAttrAccessGroup] isEqual:AppIdentifier]) UnsafeQueries++;
}
static CFTypeRef FakeTask(CFAllocatorRef allocator) { return CFBridgingRetain(@"fixture-task"); }
static CFTypeRef FakeEntitlement(CFTypeRef task,CFStringRef key,CFErrorRef *error) {
    return MissingEntitlements?NULL:CFBridgingRetain(AppIdentifier);
}
static void *FakeSymbol(void *handle,const char *name) {
    if(strcmp(name,"SecTaskCreateFromSelf")==0) return FakeTask;
    if(strcmp(name,"SecTaskCopyValueForEntitlement")==0) return FakeEntitlement;
    return NULL;
}
@implementation LCOrbitHost
+ (BOOL)isHostUI { return IsHost; }
@end
static OSStatus FakeCopy(CFDictionaryRef query,CFTypeRef *result) {
    CaptureQuery(query);Reads++;
    if(ReadStatus!=errSecSuccess) return ReadStatus;
    if(!Saved) return errSecItemNotFound;
    if(result) *result=CFBridgingRetain(Saved);
    return errSecSuccess;
}
static OSStatus FakeUpdate(CFDictionaryRef query,CFDictionaryRef attrs) {
    CaptureQuery(query);
    if(WriteStatus!=errSecSuccess) return WriteStatus;
    if(!Saved) return errSecItemNotFound;
    LastWrite=(__bridge NSDictionary *)attrs;
    Saved=LastWrite[(__bridge id)kSecValueData];return errSecSuccess;
}
static OSStatus FakeAdd(CFDictionaryRef attrs,CFTypeRef *result) {
    CaptureQuery(attrs);
    if(WriteStatus!=errSecSuccess) return WriteStatus;
    if(Saved) return errSecDuplicateItem;
    LastWrite=(__bridge NSDictionary *)attrs;
    Saved=LastWrite[(__bridge id)kSecValueData];return errSecSuccess;
}
static OSStatus FakeDelete(CFDictionaryRef query) {
    CaptureQuery(query);
    if(DeleteStatus!=errSecSuccess) return DeleteStatus;
    if(!Saved) return errSecItemNotFound;
    Saved=nil;return errSecSuccess;
}
#define dlsym FakeSymbol
#define SecItemCopyMatching FakeCopy
#define SecItemUpdate FakeUpdate
#define SecItemAdd FakeAdd
#define SecItemDelete FakeDelete
#import "../Core/LCOrbitGitHub.m"

static NSURLSessionConfiguration *CapturedConfiguration;
static NSURLRequest *CapturedRequest;
static NSError *FixtureNetworkError;
static BOOL TaskResumed,SessionInvalidated;
@interface GHFixtureDataTask : NSObject
@property(nonatomic,copy) void (^callback)(NSData *,NSURLResponse *,NSError *);
- (void)resume;
@end
@implementation GHFixtureDataTask
- (void)resume {
    TaskResumed=YES;
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:CapturedRequest.URL
        statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    self.callback([@"{}" dataUsingEncoding:NSUTF8StringEncoding],response,FixtureNetworkError);
}
@end
@interface GHFixtureSession : NSObject
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion;
- (void)finishTasksAndInvalidate;
@end
@implementation GHFixtureSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    CapturedRequest=request;GHFixtureDataTask *task=[GHFixtureDataTask new];task.callback=completion;
    return (NSURLSessionDataTask *)task;
}
- (void)finishTasksAndInvalidate { SessionInvalidated=YES; }
@end
@interface NSURLSession (GitHubBoundaryFixture)
+ (NSURLSession *)fixtureSessionWithConfiguration:(NSURLSessionConfiguration *)configuration
    delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;
@end
@implementation NSURLSession (GitHubBoundaryFixture)
+ (NSURLSession *)fixtureSessionWithConfiguration:(NSURLSessionConfiguration *)configuration
    delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    CapturedConfiguration=configuration;return (NSURLSession *)[GHFixtureSession new];
}
@end

static void Check(BOOL ok,NSString *name) {
    Checks++;if(!ok) {Failures++;fprintf(stderr,"FAIL %s\n",name.UTF8String);}
}
int main(void) { @autoreleasepool {
    NSURL *api=[NSURL URLWithString:@"https://api.github.com/repos/dompling/LC-SS-widget-export/releases/tags/fm-latest"];
    NSError *error=nil;
    NSMutableURLRequest *r=[LCOrbitGitHub requestForURL:api timeout:12 error:&error];
    Check(r && !error && ![r valueForHTTPHeaderField:@"Authorization"],@"anonymous update remains available");
    Check([[r valueForHTTPHeaderField:@"Accept"] isEqual:@"application/vnd.github+json"],@"GitHub Accept header");
    Check([r valueForHTTPHeaderField:@"User-Agent"].length>0 && r.timeoutInterval==12,@"user agent and timeout");
    Check(![LCOrbitGitHub hasTokenWithError:nil],@"empty Keychain has no token");
    Check([LCOrbitGitHub saveAccount:@"octocat" token:@"github_pat_fixtureOnly123" error:&error],@"save credentials");
    Check([[LCOrbitGitHub accountWithError:nil] isEqual:@"octocat"] && [LCOrbitGitHub hasTokenWithError:nil],@"read account and token presence");
    Check([LastWrite[(__bridge id)kSecAttrAccessible] isEqual:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly],@"device-only Keychain accessibility");
    r=[LCOrbitGitHub requestForURL:api timeout:15 error:nil];
    Check([[r valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer github_pat_fixtureOnly123"],@"host API uses saved bearer token");
    Check([LCOrbitGitHub saveAccount:@"another-user" token:@"" error:nil] &&
          [[LCOrbitGitHub accountWithError:nil] isEqual:@"another-user"],@"blank token preserves saved token during account edit");
    Check([[[LCOrbitGitHub requestForURL:api timeout:15 error:nil] valueForHTTPHeaderField:@"Authorization"]
          isEqual:@"Bearer github_pat_fixtureOnly123"],@"retained token still authenticates");
    NSData *before=Saved;
    WriteStatus=errSecMissingEntitlement;error=nil;
    Check(![LCOrbitGitHub saveAccount:@"new-user" token:@"replacement_fixture" error:&error] && error!=nil &&
          [Saved isEqual:before],@"failed save retains prior record atomically");
    Check(![error.localizedDescription containsString:@"replacement_fixture"],@"Keychain error does not expose token");
    WriteStatus=errSecSuccess;
    for(NSString *bad in @[@"bad user",@"bad/user",@"-bad",@"bad-",@"bad--user"]) {
        error=nil;Check(![LCOrbitGitHub saveAccount:bad token:@"fixture" error:&error] && error &&
            [Saved isEqual:before],[@"invalid username " stringByAppendingString:bad]);
    }
    error=nil;Check(![LCOrbitGitHub saveAccount:@"octocat" token:@"fixture\r\nInjected: yes" error:&error] &&
        error && [Saved isEqual:before],@"header injection rejected without replacing old record");
    for(NSString *url in @[@"http://api.github.com/user",@"https://api.github.com.evil.test/user",
        @"https://api.github.com@evil.test/user",@"https://user:pass@api.github.com/user",
        @"https://api.github.com:444/user",@"https://github.com/releases/download/plugin",
        @"https://api.github.com/user#fragment"]) {
        error=nil;Check(![LCOrbitGitHub requestForURL:[NSURL URLWithString:url] timeout:15 error:&error] && error,
            [@"refuse non-API target " stringByAppendingString:url]);
    }
    IsHost=NO;NSUInteger reads=Reads;error=nil;
    r=[LCOrbitGitHub requestForURL:api timeout:15 error:&error];
    Check(r && !error && ![r valueForHTTPHeaderField:@"Authorization"] && reads==Reads,@"Guest remains anonymous and never reads host Keychain");
    Check(![LCOrbitGitHub saveAccount:@"octocat" token:@"fixture" error:nil] &&
        ![LCOrbitGitHub clearCredentialsWithError:nil] && [Saved isEqual:before],@"Guest cannot overwrite or clear host credentials");
    Check(![LCOrbitGitHub accountWithError:nil] && ![LCOrbitGitHub hasTokenWithError:nil] && reads==Reads,@"Guest cannot inspect host credentials");
    IsHost=YES;ReadStatus=errSecInteractionNotAllowed;error=nil;
    Check(![LCOrbitGitHub requestForURL:api timeout:15 error:&error] && error,@"locked Keychain fails explicitly");
    ReadStatus=errSecSuccess;Saved=[@"invalid-record" dataUsingEncoding:NSUTF8StringEncoding];error=nil;
    Check(![LCOrbitGitHub requestForURL:api timeout:15 error:&error] && error,@"corrupt record not silently accepted");
    Saved=before;DeleteStatus=errSecMissingEntitlement;error=nil;
    Check(![LCOrbitGitHub clearCredentialsWithError:&error] && error && [Saved isEqual:before],@"failed delete preserves configuration");
    DeleteStatus=errSecSuccess;
    Check([LCOrbitGitHub clearCredentialsWithError:nil] && !Saved,@"clear removes whole credential record");
    Check([LCOrbitGitHub clearCredentialsWithError:nil],@"clear missing credentials is idempotent");
    error=nil;Check(![LCOrbitGitHub saveAccount:@"octocat" token:@"" error:&error] && error,@"empty first save requires token");
    Check([LCOrbitGitHub saveAccount:@"" token:@"ghp_fixture2" error:nil],@"username is optional with token authentication");
    id<NSURLSessionTaskDelegate> delegate=[NSClassFromString(@"LCOrbitGitHubSessionDelegate") new];
    Check(delegate!=nil,@"API session has redirect boundary");
    NSURLSession *redirectSession=[NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSURLRequest *original=[LCOrbitGitHub requestForURL:api timeout:15 error:nil];
    NSURLSessionDataTask *redirectTask=[redirectSession dataTaskWithRequest:original];
    NSHTTPURLResponse *moved=[[NSHTTPURLResponse alloc] initWithURL:api statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    for(NSString *url in @[@"https://evil.test/steal",@"http://api.github.com/user",@"https://api.github.com/user"]) {
        __block NSURLRequest *redirect=nil;
        NSURLRequest *proposed=[NSURLRequest requestWithURL:[NSURL URLWithString:url]];
        [delegate URLSession:redirectSession task:redirectTask willPerformHTTPRedirection:moved newRequest:proposed completionHandler:^(NSURLRequest *next){redirect=next;}];
        Check(([url isEqual:@"https://api.github.com/user"]?redirect!=nil:redirect==nil),@"redirect stays on HTTPS GitHub API");
        if(redirect) Check([[redirect valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer ghp_fixture2"],
            @"same-origin redirect preserves this task bearer");
    }
    [redirectTask cancel];[redirectSession invalidateAndCancel];
    Check(UnsafeQueries==0,@"all Keychain operations explicitly select host app-id group, never shared default");
    MissingEntitlements=YES;error=nil;reads=Reads;
    Check(![LCOrbitGitHub requestForURL:api timeout:15 error:&error] && error && Reads==reads,
        @"missing private group fails before querying shared Keychain");
    MissingEntitlements=NO;
    Check([[LCOrbitGitHub messageForStatusCode:401] containsString:@"Token"],@"invalid token has actionable error");
    Check([LCOrbitGitHub messageForStatusCode:403].length && [LCOrbitGitHub messageForStatusCode:429].length,@"permission and rate limit messages");
    Method liveFactory=class_getClassMethod(NSURLSession.class,@selector(sessionWithConfiguration:delegate:delegateQueue:));
    Method fixtureFactory=class_getClassMethod(NSURLSession.class,@selector(fixtureSessionWithConfiguration:delegate:delegateQueue:));
    method_exchangeImplementations(liveFactory,fixtureFactory);
    __block BOOL completed=NO;
    r=[LCOrbitGitHub requestForURL:api timeout:15 error:nil];
    [LCOrbitGitHub performRequest:r completion:^(NSData *data,NSHTTPURLResponse *response,NSError *failure) {
        completed=data.length>0 && response.statusCode==200 && !failure;
    }];
    Check(completed && TaskResumed && SessionInvalidated,@"performRequest starts task and releases session");
    Check(!CapturedConfiguration.URLCache && !CapturedConfiguration.HTTPCookieStorage &&
        !CapturedConfiguration.URLCredentialStorage && !CapturedRequest.HTTPShouldHandleCookies,
        @"API session disables persistent cache cookies and credential store");
    Check([[CapturedRequest valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer ghp_fixture2"],@"host task carries configured bearer");
    IsHost=NO;completed=NO;
    [LCOrbitGitHub performRequest:r completion:^(NSData *data,NSHTTPURLResponse *response,NSError *failure){completed=!failure;}];
    Check(completed && ![CapturedRequest valueForHTTPHeaderField:@"Authorization"],@"Guest performRequest strips caller-supplied bearer");
    IsHost=YES;
    FixtureNetworkError=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet
        userInfo:@{NSLocalizedDescriptionKey:@"private-token-fixture",@"request":r}];
    __block NSError *safeError=nil;
    [LCOrbitGitHub performRequest:r completion:^(NSData *data,NSHTTPURLResponse *response,NSError *failure){safeError=failure;}];
    Check(safeError && safeError.userInfo.count==1 && ![safeError.localizedDescription containsString:@"private-token-fixture"],
        @"network error drops request and raw networking userInfo");
    FixtureNetworkError=nil;CapturedRequest=nil;safeError=nil;
    NSMutableURLRequest *invalid=[r mutableCopy];invalid.HTTPMethod=@"POST";
    [LCOrbitGitHub performRequest:invalid completion:^(NSData *data,NSHTTPURLResponse *response,NSError *failure){safeError=failure;}];
    Check(safeError && !CapturedRequest,@"non-GET refused before session creation");
    method_exchangeImplementations(liveFactory,fixtureFactory);
    fprintf(stdout,"GitHub access and credential isolation: %lu assertions, %lu failures\n",(unsigned long)Checks,(unsigned long)Failures);
    return Failures?1:0;
}}
