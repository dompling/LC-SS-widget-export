#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@class LCOrbitContext;

/// Modules run inside the current LiveContainer Guest process. No sandbox isolation is implied.
@protocol LCOrbitModule <NSObject>
@property (nonatomic, copy, readonly) NSString *moduleIdentifier;
- (void)orbitDidStartWithContext:(LCOrbitContext *)context;
@optional
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event;
/// Optional scene-aware callback. Modules may implement it instead of the event-only callback.
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event scene:(nullable UIWindowScene *)scene;
- (void)orbitWillStop;
@end
NS_ASSUME_NONNULL_END
