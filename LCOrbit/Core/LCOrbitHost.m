#import "LCOrbitHost.h"
#import <objc/message.h>

@implementation LCOrbitHost
+ (id)callHostSelector:(NSString *)name {
    SEL sel=NSSelectorFromString(name);
    if(![NSUserDefaults respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,sel);
}
+ (NSUserDefaults *)hostDefaults {
    id defaults=[self callHostSelector:@"lcUserDefaults"];
    return [defaults isKindOfClass:NSUserDefaults.class]?defaults:NSUserDefaults.standardUserDefaults;
}
+ (NSString *)appGroupPath { return [self callHostSelector:@"lcAppGroupPath"]; }
+ (NSDictionary *)guestInfo { return [self callHostSelector:@"guestAppInfo"]; }
+ (NSString *)guestIdentifier {
    return [self callHostSelector:@"lcGuestAppId"] ?: NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
}
+ (UIWindowScene *)activeScene {
    if(@available(iOS 13.0,*)) {
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if([scene isKindOfClass:UIWindowScene.class] &&
               scene.activationState==UISceneActivationStateForegroundActive)
                return (UIWindowScene *)scene;
    }
    return nil;
}
+ (BOOL)isHostUI {
    // Only opt-in LC's own UI is allowed. A Guest has guestAppInfo even
    // when its bundle lives in the shared App Group.
    if([self guestInfo] || ![[self hostDefaults] boolForKey:@"LCLoadTweaksToSelf"]) return NO;
    NSBundle *hostBundle=[self callHostSelector:@"lcMainBundle"];
    if(![hostBundle isKindOfClass:NSBundle.class] ||
       ![hostBundle.bundlePath isEqualToString:NSBundle.mainBundle.bundlePath]) return NO;
    SEL side=NSSelectorFromString(@"isSideStore");
    SEL process=NSSelectorFromString(@"isLiveProcess");
    if(![NSUserDefaults respondsToSelector:side] ||
       ![NSUserDefaults respondsToSelector:process]) return NO;
    return !((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,side) &&
           !((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,process);
}
+ (BOOL)isSupportedGuest {
    if(![self activeScene] || ![self guestInfo]) return NO;
    SEL side=NSSelectorFromString(@"isSideStore");
    SEL process=NSSelectorFromString(@"isLiveProcess");
    if(![NSUserDefaults respondsToSelector:side] ||
       ![NSUserDefaults respondsToSelector:process]) return NO;
    return !((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,side) &&
           !((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,process);
}
@end
