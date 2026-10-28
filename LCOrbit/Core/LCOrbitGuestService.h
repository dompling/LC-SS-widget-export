#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const LCOrbitGuestErrorDomain;
typedef NS_ENUM(NSInteger, LCOrbitGuestError) {
    LCOrbitGuestErrorInvalidTarget=1, LCOrbitGuestErrorIneligible,
    LCOrbitGuestErrorMissingAPI, LCOrbitGuestErrorMissingScheme,
    LCOrbitGuestErrorInvalidURL, LCOrbitGuestErrorRejected,
    LCOrbitGuestErrorSideStoreMissing
};
@interface LCOrbitGuestService : NSObject
// Complete installed inventory, including current, JIT, hidden and locked apps.
// Use this for listing, favorites and plugin assignments, not launch permission.
// Each item carries a scope-aware identity, launchable flag and concise status.
+ (NSArray<NSDictionary*> *)installedApps;
// Only for callers that specifically require a validated quick-launch target.
+ (NSArray<NSDictionary*> *)launchableApps;
+ (NSArray<NSString*> *)inventoryDiagnostics;
+ (BOOL)isCurrentGuest:(NSDictionary *)app;
+ (BOOL)isBuiltInSideStoreAvailable;
+ (BOOL)isEligibleGuestPath:(NSString *)path uuid:(nullable NSString *)uuid;
// Prefer the identity-aware entrypoint for UI selections. It re-reads disk state.
+ (BOOL)launchGuest:(NSDictionary *)app error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)launchGuestPath:(NSString *)path uuid:(nullable NSString *)uuid error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)launchBuiltInSideStoreWithError:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
