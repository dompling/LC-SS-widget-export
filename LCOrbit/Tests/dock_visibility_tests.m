#import <Foundation/Foundation.h>
#import <objc/runtime.h>
@interface OrbitSurface : NSObject
@property BOOL hidden,userInteractionEnabled;
@end
@implementation OrbitSurface @end
@compatibility_alias UIView OrbitSurface;
static char DockVisibilityKey;
#include "visibility.inc"
static NSUInteger Failures,Assertions;
static void Expect(BOOL value,NSString *message) {
    Assertions++;if(!value) {Failures++;fprintf(stderr,"FAIL: %s\n",message.UTF8String);}
}
int main(void) { @autoreleasepool {
    UIView *view=[UIView new];view.hidden=YES;view.userInteractionEnabled=NO;
    ApplyDockSurfaceVisibility(view,NO);
    Expect(view.hidden && !view.userInteractionEnabled,@"system mode preserves native visibility and touch settings");
    view.hidden=NO;view.userInteractionEnabled=YES;
    ApplyDockSurfaceVisibility(view,YES);
    Expect(view.hidden && !view.userInteractionEnabled,@"bead mode hides native surface and touch interception");
    ApplyDockSurfaceVisibility(view,YES);ApplyDockSurfaceVisibility(view,NO);
    Expect(!view.hidden && view.userInteractionEnabled,@"repeated suppression restores original native state");
    view.hidden=YES;view.userInteractionEnabled=NO;
    ApplyDockSurfaceVisibility(view,YES);ApplyDockSurfaceVisibility(view,NO);
    Expect(view.hidden && !view.userInteractionEnabled,@"switch back preserves previously hidden disabled native surface");
    view.hidden=NO;ApplyDockSurfaceVisibility(view,NO);
    Expect(!view.hidden && !view.userInteractionEnabled,@"native changes after restoration remain authoritative");
    printf("Dock visibility ownership: %lu assertions, %lu failures\n",Assertions,Failures);
    return Failures?1:0;
} }
