#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface LCOrbitPluginUpdater : NSObject
// Host-only install to the known LC global Tweaks folder. A Guest may never
// silently replace another LC process's binary.
+ (BOOL)installDownloadedPlugin:(NSData *)binary
                expectedSHA256:(NSString *)digest
                          error:(NSError * _Nullable * _Nullable)error;
// Host-only automatic signing after replacement. Uses the LC app's existing
// ZSign entry, verifies the resulting signature and rolls back on failure.
// Completion is delivered on the main queue only after signing finishes.
+ (void)installDownloadedPluginAndSign:(NSData *)binary
                      expectedSHA256:(NSString *)digest
                           completion:(void (^)(BOOL success,NSError * _Nullable error))completion;
// Request a real LC host process relaunch using LCSharedUtils' existing
// launcher. Host-only; never uses exit(0) or touches Guest processes.
// Returns NO with an actionable error if the launcher cannot start.
+ (BOOL)restartHostAfterSignedUpdate:(NSError * _Nullable * _Nullable)error;
// Separate, testable atomic replacement. The old dylib remains intact if
// validation or staging fails; no persistent backup files are created.
+ (BOOL)replacePluginData:(NSData *)binary
          expectedSHA256:(NSString *)digest
             destination:(NSString *)destination
                   error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
