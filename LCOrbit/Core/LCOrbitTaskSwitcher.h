#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef UIView * _Nullable (^LCOrbitTaskDockIconProvider)(NSDictionary *app,CGFloat size,BOOL current);
// Phone overview keeps live task views in their original hierarchy. A
// transparent window above the host captures whole-card task gestures.
@interface LCOrbitTaskSwitcher : NSObject
+ (BOOL)presentInScene:(UIWindowScene *)scene error:(NSError * _Nullable * _Nullable)error;
// The drawer supplies its cached, ordered inventory. Dock selection restores
// task visibility/input before the drawer's normal validated launch path.
+ (BOOL)presentInScene:(UIWindowScene *)scene
                  apps:(NSArray<NSDictionary *> * _Nullable)apps
         launchHandler:(void (^ _Nullable)(NSDictionary *app))handler
                 error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)presentInScene:(UIWindowScene *)scene
                  apps:(NSArray<NSDictionary *> * _Nullable)apps
          dockIconSize:(CGFloat)size
          iconProvider:(nullable LCOrbitTaskDockIconProvider)provider
         launchHandler:(void (^ _Nullable)(NSDictionary *app))handler
                 error:(NSError * _Nullable * _Nullable)error;
+ (void)dismiss;
+ (void)dismissAnimated;
+ (void)dismissAnimatedWithHome;
+ (nullable NSUUID *)dockLaunchTokenForApp:(NSDictionary *)app;
+ (void)beginDockLaunch:(nullable NSUUID *)token;
+ (void)cancelDockLaunch:(nullable NSUUID *)token;
// Remains YES until saved visibility/input has been restored. Runtime hooks
// must leave these controllers alone while their live previews are presented.
+ (BOOL)isPresentingWindow:(UIViewController *)window;
@end
NS_ASSUME_NONNULL_END
