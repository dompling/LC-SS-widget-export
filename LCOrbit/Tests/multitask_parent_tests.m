#import <Foundation/Foundation.h>
#import <objc/message.h>

@interface OrbitResponder : NSObject
@property(nonatomic,strong) OrbitResponder *nextResponder;
@end
@implementation OrbitResponder @end
@compatibility_alias UIResponder OrbitResponder;
@interface OrbitView : OrbitResponder @end
@implementation OrbitView @end
@compatibility_alias UIView OrbitView;
@interface OrbitController : OrbitResponder @end
@implementation OrbitController @end
@compatibility_alias UIViewController OrbitController;
@interface OrbitDock : NSObject
@property(nonatomic,strong) UIView *windowHostingView;
@end
@implementation OrbitDock @end
static OrbitDock *HostDock;
static UIViewController *ExpectedParent,*ReceivedParent;
static NSUInteger Registrations,Failures,Assertions;
@interface LCOrbitMultitask : NSObject @end
@implementation LCOrbitMultitask
+ (BOOL)isEnabled { return NO; }
+ (void)didActivateWindow:(id)window { }
+ (void)recordWindow:(id)window bundle:(NSString *)bundle container:(NSString *)container { Registrations++; }
@end
static id Dock(void) { return HostDock; }
static BOOL Fullscreen(void) { return NO; }
static void Activate(UIViewController *window,SEL selector) {}
static void InstallFinalSceneHook(void) {}
typedef id (*OrbitInitializer)(id __attribute__((ns_consumed)),SEL,id,id,id,id) __attribute__((ns_returns_retained));
static IMP OriginalInit;

// Native UIKit enforces this same containment rule after the view has been
// added to LC's existing hosting view. The real production hook is under test.
static id NativeInit(id __attribute__((ns_consumed)) object,SEL selector,id title,id bundle,id container,id parent) __attribute__((ns_returns_retained));
static id NativeInit(id __attribute__((ns_consumed)) object,SEL selector,id title,id bundle,id container,id parent) {
    ReceivedParent=parent;
    if(ExpectedParent && parent!=ExpectedParent)
        @throw [NSException exceptionWithName:@"ContainmentMismatch" reason:@"child view controller should have the owning host parent" userInfo:nil];
    return object;
}
#include "parent.inc"

static void Expect(BOOL result,NSString *message) {
    Assertions++;if(!result) {Failures++;fprintf(stderr,"FAIL: %s\n",message.UTF8String);}
}
static void Launch(UIViewController *requested) {
    @try {
        id window=InitWindow([UIViewController alloc],NSSelectorFromString(@"initWindowName:bundleId:dataUUID:rootVC:"),@"App",@"A.app",@"a",requested);
        Expect(window!=nil,@"native window initialization succeeds");
    } @catch(NSException *exception) {Expect(NO,@"transient plugin key window cannot cause a parent containment exception");}
}
int main(void) {
    @autoreleasepool {
        HostDock=[OrbitDock new];HostDock.windowHostingView=[UIView new];OriginalInit=(IMP)NativeInit;
        UIViewController *host=[UIViewController new], *overlay=[UIViewController new];
        UIView *nested=[UIView new];nested.nextResponder=host;HostDock.windowHostingView.nextResponder=nested;
        ExpectedParent=host;Launch(overlay);
        Expect(ReceivedParent==host,@"initializer uses the existing hosting view's owner instead of the plugin root");
        Launch(host);
        Expect(ReceivedParent==host,@"LC's normal correct parent is preserved");
        HostDock.windowHostingView.nextResponder=nil;ExpectedParent=nil;Launch(host);
        Expect(ReceivedParent==host,@"unattached hosting view preserves LC's requested parent");
        Expect(Registrations==3,@"all successful windows are registered once");
        fprintf(stdout,"Multitask parent containment: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
