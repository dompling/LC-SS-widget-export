//
//  SideBackupAppLauncher.h
//  SideBackup
//
//  Created by Magesh K on 9/8/26.
//  Solution credits: Thanks to @HugeBlack
//  Copyright © 2026 SideStore. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SideBackupAppLauncher : NSObject

+ (void)openApplicationWithBundleIdentifier:(NSString *)bundleID
                                         url:(NSURL *)url
                           completionHandler:(void (^ _Nullable)(BOOL success, NSError * _Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END
