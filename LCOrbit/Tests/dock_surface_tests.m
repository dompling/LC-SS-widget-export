#import <Foundation/Foundation.h>
#include "dock-surface.inc"
static int passed,failed;
static void Expect(BOOL condition,const char *message) {
    if(condition) passed++;
    else { failed++;fprintf(stderr,"FAIL: %s\n",message); }
}
int main(void) { @autoreleasepool {
    NSString *dock=@"SwiftUI._UIHostingView<SwiftUI.AnyView>";
    Expect(OrbitDockShouldSuppress(YES,dock,NO),"microbead hides actual SwiftUI AnyView dock");
    Expect(OrbitDockShouldSuppress(YES,@"_UIHostingView<AnyView>",NO),"short Swift runtime name accepted");
    Expect(!OrbitDockShouldSuppress(NO,dock,NO),"system multitask always restores native dock");
    Expect(!OrbitDockShouldSuppress(YES,dock,YES),"never hide root view controller");
    Expect(!OrbitDockShouldSuppress(YES,@"SwiftUI._UIHostingView<RootScreen>",NO),"non-dock SwiftUI view stays");
    Expect(!OrbitDockShouldSuppress(YES,@"UIView",NO),"ordinary UIKit view stays");
    Expect(!OrbitDockShouldSuppress(YES,@"UIHostingView<AnyView>",YES),"host root protected");
    Expect(!OrbitDockShouldSuppress(YES,nil,NO),"unknown view not suppressed");
    printf("Native Dock surface policy: %d assertions, %d failures\n",passed+failed,failed);
    return failed?1:0;
}}
