#import <Foundation/Foundation.h>
#import <objc/message.h>
typedef NSObject UIViewController;
static BOOL Overview, PiP, PiPStartedAfterRestore;
static NSUInteger PiPStartCalls;
@interface LCOrbitTaskSwitcher : NSObject
+ (BOOL)isPresentingWindow:(UIViewController *)window;
+ (void)dismiss;
@end
@implementation LCOrbitTaskSwitcher
+ (BOOL)isPresentingWindow:(UIViewController *)window { return Overview && window!=nil; }
+ (void)dismiss { Overview=NO; }
@end
@interface TaskSurface : NSObject
- (BOOL)shouldIgnoreSceneUpdates;
@end
@implementation TaskSurface
- (BOOL)shouldIgnoreSceneUpdates { return PiP; }
@end
static id SceneController(id window) { return window; }
static void NativePiPStarting(id manager,SEL selector,id controller) { PiPStartCalls++;PiPStartedAfterRestore=!Overview; }
static IMP OriginalPiPStarting=(IMP)NativePiPStarting;
#include "ownership.inc"
int main(void) {
    @autoreleasepool {
        TaskSurface *surface=[TaskSurface new];
        if(OrbitPiPProtectedWindow((id)surface)) return 1;
        PiP=YES;
        if(!OrbitPiPProtectedWindow((id)surface)) return 2;
        PiP=NO;Overview=YES;
        if(!OrbitPiPProtectedWindow((id)surface)) {fprintf(stderr,"FAIL: overview-owned surface must be protected from LC geometry/visibility hooks\n");return 3;}
        Overview=NO;
        if(OrbitPiPProtectedWindow((id)surface) || OrbitPiPProtectedWindow(nil)) return 4;
        Overview=YES;PiPStarting(nil,NULL,nil);
        if(!PiPStartedAfterRestore || PiPStartCalls!=1) {fprintf(stderr,"FAIL: automatic PiP must restore task hierarchy before moving content\n");return 5;}
        puts("Task surface ownership: 6 assertions, 0 failures");
    }
    return 0;
}
