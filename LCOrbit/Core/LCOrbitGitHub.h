#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Credentials are host-only Keychain items, never ordinary preferences/logs.
@interface LCOrbitGitHub : NSObject
+ (nullable NSString *)accountWithError:(NSError * _Nullable * _Nullable)error;
+ (BOOL)hasTokenWithError:(NSError * _Nullable * _Nullable)error;
/// An empty token keeps the saved token. Clear explicitly with clearCredentials.
+ (BOOL)saveAccount:(NSString *)account token:(NSString *)token error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)clearCredentialsWithError:(NSError * _Nullable * _Nullable)error;
+ (nullable NSMutableURLRequest *)requestForURL:(NSURL *)url timeout:(NSTimeInterval)timeout
                                        error:(NSError * _Nullable * _Nullable)error;
+ (void)performRequest:(NSURLRequest *)request
           completion:(void (^)(NSData * _Nullable, NSHTTPURLResponse * _Nullable, NSError * _Nullable))completion;
/// Always returns local, bounded messages, never GitHub bodies or credentials.
+ (NSString *)messageForStatusCode:(NSInteger)status;
@end
NS_ASSUME_NONNULL_END
