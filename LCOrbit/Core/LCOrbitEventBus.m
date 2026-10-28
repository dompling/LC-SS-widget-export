#import "LCOrbitEventBus.h"

@implementation LCOrbitEventBus {
    NSNotificationCenter *_center;
}
- (instancetype)init {
    if((self=[super init])) _center=[NSNotificationCenter new];
    return self;
}
- (nullable id)subscribe:(NSString *)event handler:(void (^)(NSDictionary *))handler {
    if(!event.length || !handler) return nil;
    return [_center addObserverForName:event object:nil queue:NSOperationQueue.mainQueue
                          usingBlock:^(NSNotification *note) { handler(note.userInfo ?: @{}); }];
}
- (void)unsubscribe:(id)token { if(token) [_center removeObserver:token]; }
- (void)publish:(NSString *)event payload:(NSDictionary *)payload {
    if(!event.length) return;
    void (^deliver)(void)=^{ [_center postNotificationName:event object:self userInfo:payload ?: @{}]; };
    if(NSThread.isMainThread) deliver();
    else dispatch_async(dispatch_get_main_queue(),deliver);
}
@end
