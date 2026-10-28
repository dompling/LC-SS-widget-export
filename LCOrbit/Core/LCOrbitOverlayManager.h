#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Single pass-through overlay window shared by every floating module in a Guest.
@interface LCOrbitOverlayManager : NSObject
@property (nonatomic, strong, readonly, nullable) UIWindow *window;
- (nullable UIView *)mountModule:(NSString *)identifier inScene:(UIWindowScene *)scene;
- (void)unmountModule:(NSString *)identifier;
- (void)setModule:(NSString *)identifier visible:(BOOL)visible;
- (void)updateFrame;
@end
NS_ASSUME_NONNULL_END
