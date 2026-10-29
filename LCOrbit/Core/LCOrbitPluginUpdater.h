#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface LCOrbitPluginUpdater : NSObject
// Host-only install to the known LC global Tweaks folder. A Guest may never
// silently replace another LC process's binary.
+ (BOOL)installDownloadedPlugin:(NSData *)binary
                expectedSHA256:(NSString *)digest
                          error:(NSError * _Nullable * _Nullable)error;
// Separate, testable file transaction. Both paths are determined by the host
// in production; callers cannot supply a destination over the network.
+ (BOOL)replacePluginData:(NSData *)binary
          expectedSHA256:(NSString *)digest
             destination:(NSString *)destination
             backupFolder:(NSString *)backupFolder
                   error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
