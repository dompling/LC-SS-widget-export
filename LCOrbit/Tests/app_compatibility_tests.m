#import <Foundation/Foundation.h>
#import <objc/runtime.h>
@interface UIViewController : NSObject
@property(nonatomic,copy) NSString *bundleId;
@end
@implementation UIViewController @end
static UIViewController *SceneController(UIViewController *window) { return window; }
static char GeometryLogKey;
static NSMutableDictionary *Preferences;
static NSUInteger Refreshes;
static NSDictionary *LastEvent;
@interface LCOrbitStorage : NSObject
+ (id)objectForKey:(NSString *)key module:(NSString *)module;
+ (void)setObject:(id)value forKey:(NSString *)key module:(NSString *)module;
@end
@implementation LCOrbitStorage
+ (id)objectForKey:(NSString *)key module:(NSString *)module { return Preferences[[module stringByAppendingFormat:@".%@",key]]; }
+ (void)setObject:(id)value forKey:(NSString *)key module:(NSString *)module { Preferences[[module stringByAppendingFormat:@".%@",key]]=value; }
@end
@interface LCOrbitLog : NSObject
+ (void)appendEvent:(NSString *)event details:(NSDictionary *)details kind:(NSString *)kind;
@end
@implementation LCOrbitLog
+ (void)appendEvent:(NSString *)event details:(NSDictionary *)details kind:(NSString *)kind { LastEvent=details; }
@end
static NSArray *Windows;
@interface LCOrbitMultitask : NSObject
+ (NSArray *)windows;
+ (void)refreshPresentation;
@end
@interface LCOrbitMultitask (Compatibility)
+ (BOOL)usesAppTopInsetForBundle:(NSString *)bundle;
+ (void)setUsesAppTopInset:(BOOL)enabled forBundle:(NSString *)bundle;
@end
@implementation LCOrbitMultitask
+ (NSArray *)windows { return Windows; }
+ (void)refreshPresentation { Refreshes++; }
@end
#include "compatibility.inc"
int main(void) {
    @autoreleasepool {
        Preferences=[NSMutableDictionary dictionary];Windows=@[];
        unsigned assertions=0,failures=0;
#define EXPECT(c,m) do { assertions++;if(!(c)){failures++;fprintf(stderr,"FAIL: %s\n",m);} } while(0)
        EXPECT(![LCOrbitMultitask usesAppTopInsetForBundle:@"A.app"],"default remains off");
        EXPECT(GuestOwnsTopInset(@"A.app"),"off by default delegates top safe area to Guest");
        [LCOrbitMultitask setUsesAppTopInset:YES forBundle:@"A.app"];
        EXPECT([Preferences[@"LCFloatingMenu.guestOwnTopInset.A.app"] boolValue],"uses v6 install-path storage key");
        EXPECT([LCOrbitMultitask usesAppTopInsetForBundle:@"A.app"],"can enable before any window exists");
        EXPECT(!GuestOwnsTopInset(@"A.app"),"switch on selects physical avoidance");
        EXPECT([LastEvent[@"physicalTopAvoidanceEnabled"] boolValue] && ![LastEvent[@"appOwnsTopInset"] boolValue],"on logs physical avoidance and actual Guest ownership");
        EXPECT(GuestOwnsTopInset(@"B.app"),"another App remains in compatibility mode");
        EXPECT(![LCOrbitMultitask usesAppTopInsetForBundle:@"B.app"],"does not affect another App");
        EXPECT(Refreshes==1,"requests presentation update after save");
        [LCOrbitMultitask setUsesAppTopInset:NO forBundle:@"A.app"];
        EXPECT(![LCOrbitMultitask usesAppTopInsetForBundle:@"A.app"],"turning off selects compatibility mode");
        EXPECT(GuestOwnsTopInset(@"A.app"),"switch off restores Guest-owned safe area");
        EXPECT(![LastEvent[@"physicalTopAvoidanceEnabled"] boolValue] && [LastEvent[@"appOwnsTopInset"] boolValue],"off logs compatibility and actual Guest ownership");
        Preferences[@"LCFloatingMenu.guestOwnTopInset.A.app"]=@"YES";
        EXPECT(![LCOrbitMultitask usesAppTopInsetForBundle:@"A.app"],"invalid value defaults off");
        EXPECT(GuestOwnsTopInset(@"A.app"),"invalid preference uses off compatibility policy");
        EXPECT(GuestOwnsTopInset(@""),"empty identifier uses off compatibility policy");
        NSUInteger count=Preferences.count;
        [LCOrbitMultitask setUsesAppTopInset:YES forBundle:@""];
        EXPECT(Preferences.count==count,"empty identifier writes nothing");
        UIViewController *a=[UIViewController new],*b=[UIViewController new];a.bundleId=@"A.app";b.bundleId=@"B.app";
        objc_setAssociatedObject(a,&GeometryLogKey,@5,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(b,&GeometryLogKey,@5,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Windows=@[a,b];[LCOrbitMultitask setUsesAppTopInset:YES forBundle:@"A.app"];
        EXPECT(!objc_getAssociatedObject(a,&GeometryLogKey),"enabled App refreshes geometry diagnostics");
        EXPECT(objc_getAssociatedObject(b,&GeometryLogKey)!=nil,"other App diagnostics are preserved");
        printf("App compatibility: %u assertions, %u failures\n",assertions,failures);
        return failures?1:0;
    }
}
