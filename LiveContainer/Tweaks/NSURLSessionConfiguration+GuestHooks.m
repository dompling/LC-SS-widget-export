//
//  NSURLSessionConfiguration+GuestHooks.m
//  LiveContainer
//
//  Created by Duy Tran on 27/6/26.
//
#import "utils.h"
#import "LCSharedUtils.h"

@implementation NSURLSessionConfiguration(LiveContainerHook)
- (void)hook_encodeWithCoder:(NSCoder *)coder {
    // Fix background download failing in LiveProcess. We always overwrite sharedContainerIdentifier with ours.
    self.sharedContainerIdentifier = LCSharedUtils.appGroupID;
    [self hook_encodeWithCoder:coder];
}
@end

void NSURLSCGuestHooksInit(void) {
    swizzle(NSURLSessionConfiguration.class, @selector(encodeWithCoder:), @selector(hook_encodeWithCoder:));
}
