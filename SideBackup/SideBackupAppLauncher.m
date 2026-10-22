//
//  SideBackupAppLauncher.m
//  SideBackup
//
//  Created by Magesh K on 9/8/26.
//  Solution credits: Thanks to @HugeBlack
//  Copyright © 2026 SideStore. All rights reserved.
//

#import "SideBackupAppLauncher.h"

@interface NSObject (LSApplicationWorkspace)
+ (id)defaultWorkspace;
- (void)openApplicationWithBundleIdentifier:(NSString *)bundleID usingConfiguration:(id)config completionHandler:(void(^ _Nullable)(BOOL success, NSError * _Nullable error))completionHandler;
@end

@interface NSObject (_LSOpenConfiguration)
@property (nonatomic, copy) NSDictionary *frontBoardOptions;
@end

@implementation SideBackupAppLauncher

+ (void)openApplicationWithBundleIdentifier:(NSString *)bundleID
                                         url:(NSURL *)url
                           completionHandler:(void (^ _Nullable)(BOOL success, NSError * _Nullable error))completionHandler {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    Class configClass = NSClassFromString(@"_LSOpenConfiguration");
    
    if (!workspaceClass || !configClass) {
        if (completionHandler) completionHandler(NO, nil);
        return;
    }
    
    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    id config = [[configClass alloc] init];
    
    if ([config respondsToSelector:@selector(setFrontBoardOptions:)]) {
        [config performSelector:@selector(setFrontBoardOptions:) withObject:@{
            @"__PayloadURL": url
        }];
    }
    
    if (workspace && [workspace respondsToSelector:@selector(openApplicationWithBundleIdentifier:usingConfiguration:completionHandler:)]) {
        [workspace openApplicationWithBundleIdentifier:bundleID usingConfiguration:config completionHandler:completionHandler];
    } else {
        if (completionHandler) completionHandler(NO, nil);
    }
}

@end
