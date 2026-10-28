#import <Foundation/Foundation.h>
@class UIWindowScene;
@protocol LCOrbitModule <NSObject>
- (NSString *)moduleIdentifier;
- (void)orbitDidStartWithContext:(id)context;
- (void)orbitWillStop;
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event;
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event scene:(UIWindowScene *)scene;
@end
static BOOL Enabled=YES, RejectWrites;
@interface LCOrbitStorage : NSObject @end
@implementation LCOrbitStorage
+ (id)objectForKey:(NSString *)key module:(NSString *)module { return @(Enabled); }
+ (void)setObject:(id)value forKey:(NSString *)key module:(NSString *)module { if(!RejectWrites) Enabled=[value boolValue]; }
@end
@interface LCOrbitHost : NSObject @end
@implementation LCOrbitHost
+ (id)guestInfo { return nil; }
+ (id)guestIdentifier { return @"fixture"; }
@end
@interface FixtureContext : NSObject
- (id)events;
- (void)publish:(id)event payload:(id)payload;
@end
@implementation FixtureContext
- (id)events { return self; }
- (void)publish:(id)event payload:(id)payload {}
@end
@interface LCOrbitCore : NSObject { NSMutableDictionary *_modules;NSMutableArray *_moduleOrder;NSMutableSet *_runningModules;BOOL _started; }
@property(nonatomic,strong) FixtureContext *context;
- (BOOL)isModuleEnabled:(NSString *)identifier;
- (void)notifyModules:(NSString *)event scene:(UIWindowScene *)scene;
@end
@implementation LCOrbitCore
- (id)init { if((self=[super init])) { _modules=[NSMutableDictionary dictionary];_moduleOrder=[NSMutableArray array];_runningModules=[NSMutableSet set];_started=YES;self.context=[FixtureContext new]; } return self; }
#include "core.inc"

@end
@interface Module : NSObject<LCOrbitModule>
@property NSUInteger starts, stops, receives;
@end
@implementation Module
- (NSString *)moduleIdentifier { return @"FloatingMenu"; }
- (void)orbitDidStartWithContext:(id)context { self.starts++; }
- (void)orbitWillStop { self.stops++; }
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event { self.receives++; }
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event scene:(UIWindowScene *)scene { self.receives++; }
@end
static NSUInteger Assertions,Failures;
static void Expect(BOOL value,NSString *message) {
 Assertions++;if(!value) { Failures++;fprintf(stderr,"FAIL: %s\n",message.UTF8String); }
}
int main(void) { @autoreleasepool {
 LCOrbitCore *core=[LCOrbitCore new];Module *module=[Module new];[core registerModule:module];
 Expect(module.starts==1,@"enabled registration starts module once");
 Enabled=NO;[core notifyModules:@"active" scene:nil];
 Expect(module.stops==1 && module.receives==0,@"external disable invokes stop before lifecycle dispatch");
 [core notifyModules:@"active" scene:nil];
 Expect(module.stops==1,@"repeated lifecycle never repeats stop");
 LCOrbitCore *disabledCore=[LCOrbitCore new];Module *disabled=[Module new];[disabledCore registerModule:disabled];
 Expect(disabled.starts==0,@"disabled startup never starts module");
 Enabled=YES;[disabledCore notifyModules:@"active" scene:nil];
 Expect(disabled.starts==1 && disabled.receives==1,@"external enable starts module before receiving events");
 [disabledCore notifyModules:@"active" scene:nil];
 Expect(disabled.starts==1 && disabled.receives==2,@"foreground events do not duplicate startup observers");
 RejectWrites=YES;[disabledCore setModule:@"FloatingMenu" enabled:NO];
 Expect(disabled.stops==0 && Enabled,@"failed preference write does not stop a still-enabled module");
 RejectWrites=NO;[disabledCore setModule:@"FloatingMenu" enabled:NO];
 Expect(disabled.stops==1 && !Enabled,@"successful disable stops module exactly once");
 printf("Core external configuration lifecycle: %lu assertions, %lu failures\n",Assertions,Failures);
 return Failures?1:0;
} }
