#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <signal.h>

static NSMutableArray<void (^)(void)> *MainBlocks, *DelayedBlocks;
static NSMutableArray<NSString *> *Registered;
static NSUInteger Checks, Failures;
static void Expect(BOOL okay,NSString *message) {
    Checks++;
    if(!okay) { Failures++;fprintf(stderr,"FAIL %s\n",message.UTF8String); }
}
static void Drain(void) {
    while(MainBlocks.count) {
        void (^block)(void)=MainBlocks.firstObject;
        [MainBlocks removeObjectAtIndex:0];block();
    }
}
static void FixtureEnqueueMain(void (^block)(void)) { [MainBlocks addObject:[block copy]]; }
static void FixtureEnqueueDelayed(void (^block)(void)) { [DelayedBlocks addObject:[block copy]]; }
#define dispatch_async(queue,block) FixtureEnqueueMain(block)
#define dispatch_after(time,queue,block) FixtureEnqueueDelayed(block)

@interface MultitaskManager : NSObject @end
@implementation MultitaskManager
+ (void)registerMultitaskContainerWithContainer:(NSString *)container { [Registered addObject:container]; }
+ (void)unregisterMultitaskContainerWithContainer:(NSString *)container { [Registered removeObject:container]; }
@end

@interface FixtureExtension : NSObject
@property(copy) void (^completion)(NSUUID *);
@property(strong) NSMutableArray<NSUUID *> *cancelled;
@property BOOL alive;
@property NSUInteger kills;
@end
@implementation FixtureExtension
- (instancetype)init { if((self=[super init])) { _cancelled=[NSMutableArray array];_alive=YES; }return self; }
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))completion { self.completion=completion; }
- (int)pidForRequestIdentifier:(NSUUID *)identifier { return identifier?41:0; }
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)identifier { [self.cancelled addObject:identifier];self.alive=NO; }
- (void)_kill:(int)signal { self.kills++;self.alive=NO; }
@end

@interface FixtureHosting : NSObject
@property(nonatomic) id sceneViewController;
- (void)invalidate;
@end
@implementation FixtureHosting
- (void)invalidate {}
@end
@interface FixturePresenter : NSObject
- (void)deactivate;
- (void)invalidate;
@end
@implementation FixturePresenter
- (void)deactivate {}
- (void)invalidate {}
@end
@interface NSObject (FixtureChild)
- (void)removeFromParentViewController;
@end
@interface FBSceneManager : NSObject
+ (instancetype)sharedInstance;
- (void)destroyScene:(NSString *)scene withTransitionContext:(id)context;
@end
@implementation FBSceneManager
+ (instancetype)sharedInstance { return [self new]; }
- (void)destroyScene:(NSString *)scene withTransitionContext:(id)context {}
@end
#define PrivClass(name) name

@class AppSceneViewController;
@interface FixtureDelegate : NSObject
@property NSUInteger successes, errors, exits;
@property BOOL terminateOnInitialize;
- (void)appSceneVC:(AppSceneViewController *)vc didInitializeWithError:(NSError *)error;
- (void)appSceneVCAppDidExit:(AppSceneViewController *)vc;
@end

@interface AppSceneViewController : NSObject
@property(nonatomic) NSString *dataUUID;
@property(nonatomic) FixtureExtension *extension;
@property(nonatomic) FixtureDelegate *delegate;
@property(nonatomic) NSUUID *identifier;
@property(nonatomic) NSString *sceneID;
@property(nonatomic) int pid;
@property(nonatomic) BOOL terminationRequested, registeredMultitaskContainer, extensionRequestCompleted;
@property(nonatomic) BOOL isAppTerminationCleanUpCalled;
@property(nonatomic) FixtureHosting *hostingController;
@property(nonatomic) FixturePresenter *presenter;
@property(nonatomic) NSUInteger presentations;
- (BOOL)isAppRunning;
- (BOOL)usesHostingControllerAPI;
- (void)startRequest;
- (void)terminate;
- (void)appTerminationCleanUp;
- (void)extensionRequestDidComplete:(NSUUID *)identifier;
- (void)cancelExtensionRequest:(NSUUID *)identifier;
@end
@implementation AppSceneViewController
- (BOOL)isAppRunning { return self.pid>0 && self.extension.alive; }
- (BOOL)usesHostingControllerAPI { return NO; }
- (void)setUpAppPresenter { self.presentations++; }
- (void)startRequest {
    id delegate=self.delegate;
    id item=[NSObject new];
    (void)delegate;
#include "begin-request.inc"
}
#include "startup-methods.inc"
@end
@implementation FixtureDelegate
- (void)appSceneVC:(AppSceneViewController *)vc didInitializeWithError:(NSError *)error {
    if(error) self.errors++;else self.successes++;
    if(self.terminateOnInitialize) [vc terminate];
}
- (void)appSceneVCAppDidExit:(AppSceneViewController *)vc { self.exits++; }
@end

static AppSceneViewController *Task(NSString *container) {
    AppSceneViewController *task=[AppSceneViewController new];task.dataUUID=container;
    task.extension=[FixtureExtension new];task.delegate=[FixtureDelegate new];
    return task;
}
int main(void) { @autoreleasepool {
    MainBlocks=[NSMutableArray array];DelayedBlocks=[NSMutableArray array];Registered=[NSMutableArray array];
    NSUUID *cancelledID=NSUUID.UUID;
    AppSceneViewController *cancelled=Task(@"cancelled");
    [cancelled startRequest];[cancelled terminate];cancelled.extension.completion(cancelledID);Drain();
    Expect([cancelled.extension.cancelled isEqual:@[cancelledID]],@"cancel-before-PID cancels the exact late extension request");
    Expect(![Registered containsObject:@"cancelled"],@"cancel-before-PID never registers a container");
    Expect(cancelled.presentations==0,@"cancel-before-PID never mounts a Guest presenter");
    Expect(cancelled.delegate.successes==0,@"cancelled launch cannot report successful initialization");

    AppSceneViewController *normal=Task(@"normal");
    [normal startRequest];normal.extension.completion(NSUUID.UUID);Drain();
    Expect(normal.pid==41 && normal.presentations==1 && normal.delegate.successes==1,@"normal launch still reports its PID and creates one presenter");
    Expect([Registered containsObject:@"normal"],@"normal launch registers its exact container");

    AppSceneViewController *reentrant=Task(@"reentrant");reentrant.delegate.terminateOnInitialize=YES;
    NSUUID *reentrantID=NSUUID.UUID;
    [reentrant startRequest];reentrant.extension.completion(reentrantID);Drain();
    Expect(reentrant.presentations==0,@"terminate during initialization suppresses queued presenter setup");
    Expect([reentrant.extension.cancelled isEqual:@[reentrantID]],@"termination cancels its own known extension request");

    // The replacement owns this container; a late cancellation from an old
    // request which never registered it must not unregister the new task.
    AppSceneViewController *old=Task(@"reused");[old startRequest];[old terminate];
    [MultitaskManager registerMultitaskContainerWithContainer:@"reused"];
    old.extension.completion(NSUUID.UUID);Drain();
    [old appTerminationCleanUp];Drain();
    Expect([Registered containsObject:@"reused"],@"cancelled pending request cannot clear replacement container registration");

    AppSceneViewController *failed=Task(@"failed");[failed startRequest];failed.extension.completion(nil);Drain();
    Expect(failed.delegate.errors==1 && failed.delegate.successes==0,@"nil extension request reports one startup error");
    Expect(failed.presentations==0 && ![Registered containsObject:@"failed"],@"failed launch cannot register or mount content");
    printf("Native startup cancellation: %lu/%lu passed\n",(unsigned long)(Checks-Failures),(unsigned long)Checks);
    return Failures?1:0;
} }
