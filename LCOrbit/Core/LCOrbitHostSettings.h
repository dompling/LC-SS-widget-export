#import <Foundation/Foundation.h>
@class UIWindowScene;

NS_ASSUME_NONNULL_BEGIN
// Installed independently of FloatingMenu enablement so a hidden menu can be restored.
@interface LCOrbitHostSettings : NSObject
+ (void)installWithOpenSettings:(void (^)(UIWindowScene *scene))openSettings;
@end
NS_ASSUME_NONNULL_END
