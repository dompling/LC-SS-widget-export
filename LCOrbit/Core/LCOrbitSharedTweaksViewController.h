#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// A host-only management screen. The supplied palette comes from FloatingMenu's theme.
@interface LCOrbitSharedTweaksViewController : UIViewController
- (instancetype)initWithBackground:(UIColor *)background
                           surface:(UIColor *)surface
                              text:(UIColor *)text
                         secondary:(UIColor *)secondary
                            accent:(UIColor *)accent;
- (void)updateBackground:(UIColor *)background
                 surface:(UIColor *)surface
                    text:(UIColor *)text
               secondary:(UIColor *)secondary
                  accent:(UIColor *)accent;
@end
NS_ASSUME_NONNULL_END
