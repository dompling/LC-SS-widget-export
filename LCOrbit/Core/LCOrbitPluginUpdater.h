#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface LCOrbitPluginUpdater : NSObject
// Host-only install to the known LC global Tweaks folder. A Guest may never
// silently replace another LC process's binary.
+ (BOOL)installDownloadedPlugin:(NSData *)binary
                expectedSHA256:(NSString *)digest
                          error:(NSError * _Nullable * _Nullable)error;
// Separate, testable atomic replacement. The old dylib remains intact if
// validation or staging fails; no persistent backup files are created.
+ (BOOL)replacePluginData:(NSData *)binary
          expectedSHA256:(NSString *)digest
             destination:(NSString *)destination
                   error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
