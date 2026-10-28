#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Host-only supplementary screens for the existing shared tweak inventory.
@interface LCOrbitTweakCenterViews : NSObject
+ (UIViewController *)appAssignmentsWithBackground:(UIColor *)background surface:(UIColor *)surface
    text:(UIColor *)text secondary:(UIColor *)secondary accent:(UIColor *)accent;
+ (UIViewController *)pluginDetailsForName:(NSString *)name background:(UIColor *)background
    surface:(UIColor *)surface text:(UIColor *)text secondary:(UIColor *)secondary accent:(UIColor *)accent;
@end
NS_ASSUME_NONNULL_END
