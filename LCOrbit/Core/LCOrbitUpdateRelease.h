#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Public release metadata only; never contains GitHub credentials.
@interface LCOrbitUpdateRelease : NSObject
/// Normalizes GitHub JSON into version, commit, downloadURL, sha256, notes.
+ (nullable NSDictionary<NSString *,NSString *> *)releaseFromJSON:(nullable id)json error:(NSError * _Nullable * _Nullable)error;
+ (NSString *)notesFromBody:(nullable id)body;
/// Treat persisted metadata as untrusted; validate before offering/installing.
+ (nullable NSDictionary<NSString *,NSString *> *)validatedRelease:(nullable id)release error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)isNewerRelease:(NSDictionary *)release thanVersion:(NSString *)installed;
+ (BOOL)shouldOfferRelease:(NSDictionary *)release installedVersion:(NSString *)installed
           skippedVersion:(nullable NSString *)skipped;
@end
NS_ASSUME_NONNULL_END
