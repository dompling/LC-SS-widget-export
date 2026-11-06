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
+ (void)appendEvent:(NSString *)event details:(NSDictionary *)details kind:(NSString *)kind {}
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
        [LCOrbitMultitask setUsesAppTopInset:YES forBundle:@"A.app"];
        EXPECT([Preferences[@"LCFloatingMenu.guestOwnTopInset.A.app"] boolValue],"uses v6 install-path storage key");
        EXPECT([LCOrbitMultitask usesAppTopInsetForBundle:@"A.app"],"can enable before any window exists");
        EXPECT(![LCOrbitMultitask usesAppTopInsetForBundle:@"B.app"],"does not affect another App");
        EXPECT(Refreshes==1,"requests presentation update after save");
        [LCOrbitMultitask setUsesAppTopInset:NO forBundle:@"A.app"];
        EXPECT(![LCOrbitMultitask usesAppTopInsetForBundle:@"A.app"],"turning off restores default");
        Preferences[@"LCFloatingMenu.guestOwnTopInset.A.app"]=@"YES";
        EXPECT(![LCOrbitMultitask usesAppTopInsetForBundle:@"A.app"],"invalid value defaults off");
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
