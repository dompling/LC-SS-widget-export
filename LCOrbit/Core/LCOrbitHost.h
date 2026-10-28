#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface LCOrbitHost : NSObject
+ (NSUserDefaults *)hostDefaults;
+ (nullable NSString *)appGroupPath;
+ (nullable NSDictionary *)guestInfo;
+ (NSString *)guestIdentifier;
+ (nullable UIWindowScene *)activeScene;
+ (BOOL)isHostUI;
+ (BOOL)isSupportedGuest;
@end
NS_ASSUME_NONNULL_END
