#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Opt-in LiveProcess UIKit diagnostics and targeted Guest layout recovery.
// The host never modifies a remote Guest hierarchy. Guest-side corrections
// only run for the explicitly selected per-App UIKit mode.
@interface LCOrbitGuestUIKitDiagnostics : NSObject
+ (BOOL)isEnabled;
// Host-only mirror for the sandboxed LiveProcess, containing no personal data.
+ (void)synchronizeUIKitModesToGuests;
+ (void)setEnabled:(BOOL)enabled;
+ (void)startInLiveProcess;
// Host-only: signal a particular running Guest after its view is reactivated.
+ (void)notifyGuestActivatedBundle:(NSString *)bundle container:(NSString *)container;
+ (NSArray<NSDictionary *> *)events;
@end

NS_ASSUME_NONNULL_END
