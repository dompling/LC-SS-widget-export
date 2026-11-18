#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Diagnostic-only observer for LC LiveProcess guests. Never changes UIKit
// geometry, scene settings, constraints, or the guest view hierarchy.
// User must opt in from LC host settings and restart the guest process.
@interface LCOrbitGuestUIKitDiagnostics : NSObject
+ (BOOL)isEnabled;
// Host-only mirror for the sandboxed LiveProcess, containing no personal data.
+ (void)synchronizeUIKitModesToGuests;
+ (void)setEnabled:(BOOL)enabled;
+ (void)startInLiveProcess;
+ (NSArray<NSDictionary *> *)events;
@end

NS_ASSUME_NONNULL_END
