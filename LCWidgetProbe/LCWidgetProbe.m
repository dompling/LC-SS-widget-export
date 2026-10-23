// LCWidgetProbe v2: minimal path-visibility test for the official LC+SS Nightly.
// Runs only as an enabled LiveContainer Guest App tweak.
// Does not read SideStore files, sign-in data, certificates, or file contents.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

static NSDictionary *ProbeDirectory(NSString *base, NSString *relative, NSString *label) {
    NSString *path = [base stringByAppendingPathComponent:relative];
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDirectory];

    NSMutableDictionary *result = [@{
        @"base": label,
        @"relativePath": relative,
        @"exists": @(exists),
        @"isDirectory": @(isDirectory)
    } mutableCopy];

    if (exists && isDirectory) {
        NSError *error = nil;
        // Check directory readability only. No names or file contents are exported.
        NSArray *entries = [fm contentsOfDirectoryAtPath:path error:&error];
        result[@"readable"] = @(entries != nil);
        if (error) result[@"readErrorCode"] = @(error.code);
    }
    return result;
}

__attribute__((constructor)) static void LCWidgetProbeInit(void) {
    NSLog(@"[LCWidgetProbe] v2 loaded");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSString *guestHome = NSHomeDirectory();
            const char *rawLCHome = getenv("LC_HOME_PATH");
            NSString *lcHome = (rawLCHome && rawLCHome[0])
                ? [NSString stringWithUTF8String:rawLCHome] : nil;

            NSMutableArray *checks = [NSMutableArray array];
            [checks addObject:ProbeDirectory(guestHome, @"Documents", @"guestHome")];
            [checks addObject:ProbeDirectory(guestHome, @"Documents/SideStore", @"guestHome")];
            if (lcHome.length) {
                // SideStoreSupport/SideStore.swift in upstream LC uses
                // LC_HOME_PATH + "/Documents/SideStore" for the built-in SideStore.
                [checks addObject:ProbeDirectory(lcHome, @"Documents", @"lcHome")];
                [checks addObject:ProbeDirectory(lcHome, @"Documents/SideStore", @"lcHome")];
                [checks addObject:ProbeDirectory(lcHome, @"Documents/SideStore/Library", @"lcHome")];
            }

            NSDictionary *report = @{
                @"version": @2,
                @"status": @"probe-only",
                @"timestamp": @([[NSDate date] timeIntervalSince1970]),
                @"hostBundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
                @"lcHomePathAvailable": @(lcHome.length > 0),
                @"lcHomeIsDifferentFromGuestHome": @(lcHome.length > 0 && ![lcHome isEqualToString:guestHome]),
                @"candidateDirectories": checks,
                @"warning": @"Directory visibility only; no SideStore data or signing expiration dates are read."
            };

            NSString *outDir = [guestHome stringByAppendingPathComponent:@"Documents/LCWidgetProbe"];
            NSError *error = nil;
            BOOL created = [NSFileManager.defaultManager createDirectoryAtPath:outDir
                                      withIntermediateDirectories:YES attributes:nil error:&error];
            NSData *data = [NSJSONSerialization dataWithJSONObject:report
                                                            options:NSJSONWritingPrettyPrinted error:&error];
            BOOL saved = created && data &&
                [data writeToFile:[outDir stringByAppendingPathComponent:@"probe.json"]
                          options:NSDataWritingAtomic error:&error];
            NSLog(@"[LCWidgetProbe] v2 report %@; LC_HOME_PATH present=%@",
                  saved ? @"saved" : @"failed", lcHome.length ? @"YES" : @"NO");
            if (!saved && error) NSLog(@"[LCWidgetProbe] v2 error code=%ld", (long)error.code);
        }
    });
}
