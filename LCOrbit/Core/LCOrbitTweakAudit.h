#import <Foundation/Foundation.h>

// A post-load view of LC's tweak directories and dyld images.
// This cannot recover earlier NSLog lines or the original dlopen error text.
@interface LCOrbitTweakAudit : NSObject
+ (nullable NSString *)logPath;
+ (nonnull NSString *)captureSnapshot;
+ (void)appendEvent:(nonnull NSString *)event;
+ (void)clearLogs;
@end
