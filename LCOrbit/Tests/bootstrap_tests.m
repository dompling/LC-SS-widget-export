#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "LCOrbitHost.h"
#import "LCOrbitGuestFullscreenProbe.h"

static NSUserDefaults *Defaults;
static BOOL LiveProcess;
static NSUInteger Dispatches, Instances, Registrations, Starts, ProbeCalls;
@implementation LCOrbitGuestFullscreenProbe
+ (void)installIfLiveProcess { ProbeCalls++; }
@end
@implementation LCOrbitHost
+ (NSUserDefaults *)hostDefaults { return Defaults; }
+ (NSString *)appGroupPath { return nil; }
+ (NSDictionary *)guestInfo { return nil; }
+ (NSString *)guestIdentifier { return @"fixture"; }
+ (UIWindowScene *)activeScene { return nil; }
+ (BOOL)isHostUI { return !LiveProcess; }
+ (BOOL)isSupportedGuest { return NO; }
@end
@implementation NSUserDefaults (OrbitProcessFixture)
+ (BOOL)isLiveProcess { return LiveProcess; }
@end
@interface LCOrbitCore : NSObject
+ (instancetype)sharedCore;
- (void)start;
@end
@implementation LCOrbitCore
+ (instancetype)sharedCore { Instances++;return [self new]; }
- (void)start { Starts++; }
@end
void LCFloatingMenuRegisterWithOrbit(LCOrbitCore *core) { Registrations++; }
static void OrbitDispatch(void (^block)(void)) { Dispatches++;block(); }
#define dispatch_async(queue,block) OrbitDispatch(block)
#include "entry.inc"
#undef dispatch_async

int main(void) {
    @autoreleasepool {
        NSString *suite=[@"orbit.bootstrap.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        Defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        unsigned failures=0, assertions=0;
#define EXPECT(value,message) do {assertions++;if(!(value)){failures++;fprintf(stderr,"FAIL: %s\n",message);}}while(0)
        LiveProcess=YES;
        [Defaults setBool:YES forKey:@"LCFloatingMenu.fullscreenMultitask"];
        LCOrbitEntry();
        EXPECT(Dispatches==0,"host-managed child does not schedule bootstrap work");
        EXPECT(Instances==0 && Registrations==0 && Starts==0,"host-managed child does not create core, modules or lifecycle observers");
        EXPECT(ProbeCalls==1,"LiveProcess takes the diagnostics-only path without installing the menu");
        LiveProcess=NO;
        LCOrbitEntry();
        EXPECT(Starts==1 && Registrations==1,"LC host still starts its own menu runtime");
        LiveProcess=YES;
        [Defaults setBool:NO forKey:@"LCFloatingMenu.fullscreenMultitask"];
        LCOrbitEntry();
        EXPECT(Starts==1 && Registrations==1,"LiveProcess skips bootstrap even when host preference is absent from child defaults");
        LiveProcess=NO;
        LCOrbitEntry();
        EXPECT(Starts==2 && Registrations==2,"classic single-task plugin behavior remains available without host takeover");
        EXPECT(ProbeCalls==2,"host and classic Guest never install the LiveProcess-only probe");
        [Defaults removePersistentDomainForName:suite];
        fprintf(stdout,"Bootstrap behavior tests: %u assertions, %u failures\n",assertions,failures);
        return failures?1:0;
    }
}
