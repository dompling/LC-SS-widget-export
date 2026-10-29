#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>

typedef NS_ENUM(NSInteger, UIApplicationState) {
    UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground
};
FOUNDATION_EXPORT NSString *const UIApplicationDidBecomeActiveNotification;
FOUNDATION_EXPORT NSString *const UIApplicationDidEnterBackgroundNotification;
FOUNDATION_EXPORT NSString *const UISceneDidActivateNotification;
FOUNDATION_EXPORT NSString *const UIWindowDidBecomeVisibleNotification;

@interface OrbitPiPFixtureLayer : NSObject
@property(nonatomic) CGPoint anchorPoint,position;
@end
@interface UIView : NSObject
@property(nonatomic) CGRect bounds,frame;
@property(nonatomic) BOOL hidden;
@property(nonatomic,strong) id window;
@property(nonatomic,strong) OrbitPiPFixtureLayer *layer;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) NSMutableArray<UIView *> *subviews;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
@end
@interface UIViewController : NSObject
@property(nonatomic,strong) UIView *view;
@property(nonatomic) CGSize preferredContentSize;
@end
@interface UIApplication : NSObject
@property(nonatomic) UIApplicationState applicationState;
+ (instancetype)sharedApplication;
@end
