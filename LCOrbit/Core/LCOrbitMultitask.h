#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const LCOrbitMultitaskLaunchFailedNotification;
FOUNDATION_EXPORT NSString *const LCOrbitMultitaskMenuRequestedNotification;
FOUNDATION_EXPORT NSString *const LCOrbitMultitaskConfigurationChangedNotification;

// Runs in the injected LC host. Guest processes keep the classic launch path.
@interface LCOrbitMultitask : NSObject
+ (BOOL)isEnabled;
// System mode never participates in window geometry/visibility enforcement.
+ (BOOL)isManagingWindows;
+ (BOOL)setEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)usesSystemMenu;
+ (BOOL)setUseSystemMenu:(BOOL)system error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)shouldShowFloatingMenu;
+ (BOOL)launchGuest:(NSDictionary *)guest error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)isCurrentGuest:(NSDictionary *)guest;
+ (BOOL)togglePiPForActiveWindow:(NSError * _Nullable * _Nullable)error;
// Close the actual AVKit PiP session, not the running Guest process.
+ (BOOL)isPiPActive;
+ (BOOL)stopPiPIfActive:(NSError * _Nullable * _Nullable)error;
+ (BOOL)automaticPiPEnabledForGuest:(NSDictionary *)guest;
+ (BOOL)setAutomaticPiPEnabled:(BOOL)enabled forGuest:(NSDictionary *)guest error:(NSError * _Nullable * _Nullable)error;
+ (nullable NSDictionary *)activeGuestForAutomaticPiP;
+ (void)showHome;
+ (BOOL)closeCurrentGuest;
// Exact target close: no fallback to the foreground task or a namesake app.
+ (BOOL)isRunningGuest:(NSDictionary *)guest;
+ (BOOL)closeGuest:(NSDictionary *)guest error:(NSError * _Nullable * _Nullable)error;
+ (NSArray *)windows;
+ (nullable id)activeWindow;
+ (void)recordWindow:(id)window bundle:(NSString *)bundle container:(NSString *)container;
+ (void)forgetWindow:(nullable id)window;
+ (void)didActivateWindow:(id)window;
+ (void)didHideWindow:(id)window;
+ (void)requestMenu;
@end

// UIKit adapter installs guarded runtime hooks without linking LC classes.
@interface LCOrbitMultitask (Presentation)
+ (BOOL)installHooksWithError:(NSError * _Nullable * _Nullable)error;
+ (void)refreshPresentation;
@end
NS_ASSUME_NONNULL_END
