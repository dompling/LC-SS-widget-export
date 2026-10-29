#import <Foundation/Foundation.h>

// Diagnostics-only. Installed strictly inside LC's LiveProcess Guest.
// Never forces an orientation, modifies the UIKit reply, or runs in LC host.
@interface LCOrbitGuestFullscreenProbe : NSObject
+ (void)installIfLiveProcess;
@end
