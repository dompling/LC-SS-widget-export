// Test-only shim: the guest service uses Foundation; its host header names a scene.
// No UIKit behavior is mocked or tested by this target.
#import <Foundation/Foundation.h>
@class UIWindowScene;
