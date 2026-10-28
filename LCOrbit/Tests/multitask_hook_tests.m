#import <Foundation/Foundation.h>
#import <objc/runtime.h>

extern BOOL OrbitMethodMatches(Class cls, NSString *name, const char *result, NSArray<NSString *> *arguments);

@interface OrbitHookFixture : NSObject
- (void)update:(id)value count:(uint32_t)count;
- (BOOL)visible;
@end
@implementation OrbitHookFixture
- (void)update:(id)value count:(uint32_t)count {}
- (BOOL)visible { return YES; }
@end

int main(void) {
    @autoreleasepool {
        unsigned failures=0, assertions=0;
#define EXPECT(condition) do { assertions++; if(!(condition)) { failures++; fprintf(stderr,"FAIL line %d\n",__LINE__); } } while(0)
        // Installing a hook with the wrong argument ABI can corrupt the host.
        EXPECT(OrbitMethodMatches(OrbitHookFixture.class,@"update:count:",@encode(void),@[@"@",@(@encode(uint32_t))]));
        EXPECT(!OrbitMethodMatches(OrbitHookFixture.class,@"update:count:",@encode(void),@[@"@",@"@"]));
        EXPECT(!OrbitMethodMatches(OrbitHookFixture.class,@"update:count:",@encode(void),@[@"@"]));
        EXPECT(!OrbitMethodMatches(OrbitHookFixture.class,@"visible",@encode(void),@[]));
        EXPECT(OrbitMethodMatches(OrbitHookFixture.class,@"visible",@encode(BOOL),@[]));
        EXPECT(!OrbitMethodMatches(Nil,@"visible",@encode(BOOL),@[]));
        EXPECT(!OrbitMethodMatches(OrbitHookFixture.class,@"missing",@encode(void),@[]));
        fprintf(stdout,"Multitask hook ABI tests: %u assertions, %u failures\n",assertions,failures);
        return failures?1:0;
    }
}
