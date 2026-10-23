// LCWidgetProbe v4 - copy the official SideStore widget snapshot unchanged.
// Optional Guest App tweak; compatible with the stock LiveContainer+SideStore Nightly.
// Never accesses Apple ID sessions, account databases, private keys, or certificate files.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#import <stdlib.h>

static BOOL LCWidgetIsKnownSnapshot(NSDictionary *snapshot) {
    NSSet *allowedRoot = [NSSet setWithArray:@[@"activeApps", @"allApps", @"lastUpdated"]];
    NSSet *allowedApp = [NSSet setWithArray:@[
        @"name", @"bundleIdentifier", @"expirationDate", @"refreshedDate", @"tintColorHex"
    ]];
    for (id key in snapshot) {
        if (![key isKindOfClass:NSString.class] || ![allowedRoot containsObject:key]) return NO;
    }
    if (![snapshot[@"activeApps"] isKindOfClass:NSArray.class] ||
        ![snapshot[@"allApps"] isKindOfClass:NSArray.class] ||
        !([snapshot[@"lastUpdated"] isKindOfClass:NSNumber.class] ||
          [snapshot[@"lastUpdated"] isKindOfClass:NSString.class])) return NO;

    for (NSArray *apps in @[snapshot[@"activeApps"], snapshot[@"allApps"]]) {
        for (id entry in apps) {
            if (![entry isKindOfClass:NSDictionary.class]) return NO;
            NSDictionary *app = entry;
            for (id key in app) {
                if (![key isKindOfClass:NSString.class] || ![allowedApp containsObject:key]) return NO;
                id value = app[key];
                if ([key isEqualToString:@"name"] || [key isEqualToString:@"bundleIdentifier"]) {
                    if (![value isKindOfClass:NSString.class]) return NO;
                } else if ([key isEqualToString:@"expirationDate"] || [key isEqualToString:@"refreshedDate"]) {
                    if (![value isKindOfClass:NSNumber.class] && ![value isKindOfClass:NSString.class]) return NO;
                } else if (![value isKindOfClass:NSString.class] && value != NSNull.null) {
                    return NO;
                }
            }
        }
    }
    return YES;
}

__attribute__((constructor)) static void LCWidgetProbeInit(void) {
    NSLog(@"[LCWidgetProbe] v4 started");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            const char *rawHome = getenv("LC_HOME_PATH");
            NSString *lcHome = (rawHome && rawHome[0]) ? [NSString stringWithUTF8String:rawHome] : nil;
            if (!lcHome.length) {
                NSLog(@"[LCWidgetProbe] v4 unavailable: LC_HOME_PATH not set; no export");
                return;
            }

            // Stable destination: independent of which Guest App launched the tweak.
            NSString *outDir = [lcHome stringByAppendingPathComponent:@"Documents/LCWidgetExport"];
            NSString *outPath = [outDir stringByAppendingPathComponent:@"widget_data.json"];
            NSError *error = nil;
            BOOL directoryReady = [fm createDirectoryAtPath:outDir
                                  withIntermediateDirectories:YES attributes:nil error:&error];

            Class utils = NSClassFromString(@"LCSharedUtils");
            NSURL *group = nil;
            if (utils && [utils respondsToSelector:@selector(appGroupPath)]) {
                group = ((NSURL *(*)(id, SEL))objc_msgSend)(utils, @selector(appGroupPath));
            }
            NSURL *source = [group URLByAppendingPathComponent:@"widget_data.json"];
            BOOL sourceExists = source && [fm fileExistsAtPath:source.path];
            NSString *status = @"source-not-found";
            BOOL copied = NO;
            BOOL identical = NO;
            NSUInteger activeCount = 0;
            NSUInteger allCount = 0;

            if (!directoryReady) {
                status = @"destination-unavailable";
            } else if (sourceExists) {
                NSData *raw = [NSData dataWithContentsOfURL:source options:0 error:&error];
                if (!raw) {
                    status = @"source-unreadable";
                } else if (raw.length > 2 * 1024 * 1024) {
                    status = @"source-too-large";
                } else {
                    id parsed = [NSJSONSerialization JSONObjectWithData:raw options:0 error:&error];
                    if (![parsed isKindOfClass:NSDictionary.class] || !LCWidgetIsKnownSnapshot(parsed)) {
                        // If upstream adds fields, do not blindly export unknown potentially sensitive data.
                        status = @"unexpected-widget-schema";
                    } else {
                        NSDictionary *snapshot = parsed;
                        activeCount = [snapshot[@"activeApps"] count];
                        allCount = [snapshot[@"allApps"] count];
                        NSData *existing = [NSData dataWithContentsOfFile:outPath];
                        if ([existing isEqualToData:raw]) {
                            copied = YES;
                            identical = YES;
                            status = @"unchanged";
                        } else {
                            copied = [raw writeToFile:outPath options:NSDataWritingAtomic error:&error];
                            identical = copied && [[NSData dataWithContentsOfFile:outPath] isEqualToData:raw];
                            status = copied && identical ? @"ok" : @"write-failed";
                        }
                    }
                }
            }

            // Diagnostics are kept separate; never modify the copied official JSON.
            NSDictionary *report = @{
                @"version": @4,
                @"status": status,
                @"timestamp": @([[NSDate date] timeIntervalSince1970]),
                @"hostBundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
                @"officialWidgetDataExists": @(sourceExists),
                @"widgetExported": @(copied),
                @"byteIdenticalToOfficial": @(identical),
                @"activeAppCount": @(activeCount),
                @"allAppCount": @(allCount),
                @"outputLocation": @"LC_HOME_PATH/Documents/LCWidgetExport",
                @"note": @"Original SideStore widget JSON copied without format or date conversion. Guest App launch required to run this tweak."
            };
            if (directoryReady) {
                NSData *diagnostics = [NSJSONSerialization dataWithJSONObject:report
                                         options:NSJSONWritingPrettyPrinted error:nil];
                [diagnostics writeToFile:[outDir stringByAppendingPathComponent:@"probe.json"]
                                 options:NSDataWritingAtomic error:nil];
            }
            NSLog(@"[LCWidgetProbe] v4 result=%@ export=%@ bytesMatch=%@ active=%lu all=%lu",
                  status, copied ? @"YES" : @"NO", identical ? @"YES" : @"NO",
                  (unsigned long)activeCount, (unsigned long)allCount);
            if (error) NSLog(@"[LCWidgetProbe] v4 error code=%ld", (long)error.code);
        }
    });
}
