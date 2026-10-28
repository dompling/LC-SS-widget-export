#import <Foundation/Foundation.h>
#import <objc/runtime.h>
static BOOL Enabled,SystemMenu;
static NSUInteger Requests,NativeCalls,Assertions,Failures,DockSyncs;
static void SyncNativeDockSurface(void) { DockSyncs++; }
static IMP OriginalShowDock,OriginalShowHidden,OriginalToggleDock;
static IMP OriginalBringToFront;
static IMP OriginalMinimize;
@interface OrbitView : NSObject
@property BOOL hidden;
@end
@implementation OrbitView @end
@compatibility_alias UIView OrbitView;
@interface OrbitController : NSObject
@property(nonatomic,strong) UIView *view;
@end
@implementation OrbitController @end
@compatibility_alias UIViewController OrbitController;
static NSArray *ManagedWindows;
static id Active;
static NSUInteger GeometryUpdates,FrontCalls;
static void SetVisible(UIViewController *window,SEL selector,BOOL visible) { window.view.hidden=!visible; }
static void UpdateScene(UIViewController *window,id settings) { GeometryUpdates++; }
static void NativeFront(id object,SEL selector,id view) { FrontCalls++; }
static void NativeMinimize(UIViewController *window,SEL selector) { window.view.hidden=YES; }
static BOOL Fullscreen(void) { return Enabled && !SystemMenu; }
static void Native(id object,SEL selector) { NativeCalls++; }
@interface LCOrbitMultitask : NSObject @end
@implementation LCOrbitMultitask
+ (BOOL)isEnabled { return Enabled; }
+ (void)requestMenu { Requests++; }
+ (BOOL)usesSystemMenu { return SystemMenu; }
+ (NSArray *)windows { return ManagedWindows; }
+ (void)didActivateWindow:(id)window { Active=window; }
+ (void)didHideWindow:(id)window { if(Active==window) Active=nil; }
@end
#include "menu.inc"
static void Expect(BOOL result,NSString *message) {
    Assertions++;if(!result) {Failures++;fprintf(stderr,"FAIL: %s\n",message.UTF8String);}
}
int main(void) {
    @autoreleasepool {
        OriginalShowDock=OriginalShowHidden=OriginalToggleDock=(IMP)Native;
        Enabled=YES;
        ShowDock(nil,NSSelectorFromString(@"showDock"));
        Expect(Requests==0 && NativeCalls==0 && DockSyncs==1,
            @"LC task startup must suppress native Dock without popping open the bead menu");
        ShowHidden(nil,NSSelectorFromString(@"showDockFromHidden"));
        Expect(Requests==1 && NativeCalls==0,@"LC edge reveal opens the bead menu");
        ToggleDock(nil,NSSelectorFromString(@"toggleDockVisibility"));
        Expect(Requests==2 && NativeCalls==0,@"LC visibility command routes to the bead menu");
        SystemMenu=YES;
        ShowDock(nil,NSSelectorFromString(@"showDock"));
        ShowHidden(nil,NSSelectorFromString(@"showDockFromHidden"));
        ToggleDock(nil,NSSelectorFromString(@"toggleDockVisibility"));
        Expect(Requests==2 && NativeCalls==3 && !Fullscreen(),@"system LC menu preserves native entry points without fullscreen enforcement");
        Enabled=NO;SystemMenu=NO;
        ShowDock(nil,NSSelectorFromString(@"showDock"));
        Expect(Requests==2 && NativeCalls==4,@"disabled multitask passes through to LC's own Dock");
        UIViewController *a=[UIViewController new],*b=[UIViewController new];
        a.view=[UIView new];b.view=[UIView new];b.view.hidden=YES;
        ManagedWindows=@[a,b];OriginalBringToFront=(IMP)NativeFront;
        Enabled=YES;SystemMenu=YES;
        HostingBringToFront(nil,NSSelectorFromString(@"bringSubviewToFront:"),b.view);
        Expect(Active==b && b.view.hidden && !a.view.hidden && GeometryUpdates==0 && FrontCalls==1,
            @"system Dock tracks identity without imposing plugin visibility or fullscreen geometry");
        OriginalMinimize=(IMP)NativeMinimize;
        Minimize(b,NSSelectorFromString(@"minimizeWindow"));
        Expect(Active==nil && b.view.hidden,@"system minimize clears active identity for settings recovery");
        SystemMenu=NO;
        HostingBringToFront(nil,NSSelectorFromString(@"bringSubviewToFront:"),b.view);
        Expect(Active==b && !b.view.hidden && a.view.hidden && GeometryUpdates==1 && FrontCalls==2,
            @"bead mode still reconciles active task and fullscreen geometry");
        OriginalMinimize=(IMP)NativeMinimize;
        Minimize(b,NSSelectorFromString(@"minimizeWindow"));
        Expect(Active==nil && b.view.hidden,@"LC native minimize clears foreground identity");
        Active=b;
        HostingBringToFront(nil,NSSelectorFromString(@"bringSubviewToFront:"),[UIView new]);
        Expect(Active==b && GeometryUpdates==1 && FrontCalls==3,@"unmanaged views are reordered without task side effects");
        Enabled=NO;
        HostingBringToFront(nil,NSSelectorFromString(@"bringSubviewToFront:"),a.view);
        Expect(Active==b && GeometryUpdates==1 && FrontCalls==4,@"disabled engine preserves native view behavior");
        fprintf(stdout,"Multitask menu routing: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
