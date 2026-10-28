#import <UIKit/UIKit.h>
#import "../SDK/LCOrbitModule.h"
@class LCOrbitOverlayManager, LCOrbitEventBus;

NS_ASSUME_NONNULL_BEGIN
@interface LCOrbitContext : NSObject
@property (nonatomic, strong, readonly) LCOrbitOverlayManager *overlays;
@property (nonatomic, strong, readonly) LCOrbitEventBus *events;
@end

@interface LCOrbitCore : NSObject
+ (instancetype)sharedCore;
@property (nonatomic, strong, readonly) LCOrbitContext *context;
- (BOOL)registerModule:(id<LCOrbitModule>)module;
- (BOOL)isModuleEnabled:(NSString *)identifier;
- (void)setModule:(NSString *)identifier enabled:(BOOL)enabled;
- (NSArray<NSString *> *)registeredModuleIdentifiers;
- (void)start;
@end
NS_ASSUME_NONNULL_END
