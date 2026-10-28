#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// In-process events only; other Guests must use persistent storage or an explicit host bridge.
@interface LCOrbitEventBus : NSObject
- (nullable id)subscribe:(NSString *)event handler:(void (^)(NSDictionary *payload))handler;
- (void)unsubscribe:(id)token;
- (void)publish:(NSString *)event payload:(nullable NSDictionary *)payload;
@end
NS_ASSUME_NONNULL_END
