// LCWidgetProbe v3 - reads only SideStore's existing widget_data.json.
// Runs as an optional Guest App tweak in the OFFICIAL LC+SS Nightly.
// Never reads the SideStore account database, keychain, cookies, or certificates.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>

static NSString *ISODate(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        // Apple's default JSONEncoder encodes Date relative to 2001-01-01.
        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:[value doubleValue]];
        NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        return [formatter stringFromDate:date];
    }
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSArray *SafeApps(id raw) {
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (id entry in raw) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *src = entry;
        NSMutableDictionary *app = [NSMutableDictionary dictionary];
        for (NSString *field in @[@"name", @"bundleIdentifier"]) {
            if ([src[field] isKindOfClass:NSString.class]) app[field] = src[field];
        }
        for (NSString *field in @[@"expirationDate", @"refreshedDate"]) {
            NSString *value = ISODate(src[field]);
            if (value) app[field] = value;
        }
        if ([app[@"name"] isKindOfClass:NSString.class]) [items addObject:app];
        if (items.count >= 200) break;
    }
    return items;
}

__attribute__((constructor)) static void LCWidgetProbeInit(void) {
    NSLog(@"[LCWidgetProbe] v3 started");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *outDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/LCWidgetProbe"];
            [fm createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:nil];

            Class utils = NSClassFromString(@"LCSharedUtils");
            NSURL *group = nil;
            if (utils && [utils respondsToSelector:@selector(appGroupPath)]) {
                group = ((NSURL *(*)(id, SEL))objc_msgSend)(utils, @selector(appGroupPath));
            }
            NSURL *widget = [group URLByAppendingPathComponent:@"widget_data.json"];
            BOOL found = widget && [fm fileExistsAtPath:widget.path];
            BOOL exported = NO;
            NSString *reason = @"not-found";
            if (found) {
                NSError *error = nil;
                NSData *raw = [NSData dataWithContentsOfURL:widget options:0 error:&error];
                id object = raw ? [NSJSONSerialization JSONObjectWithData:raw options:0 error:&error] : nil;
                if ([object isKindOfClass:NSDictionary.class]) {
                    NSDictionary *snapshot = object;
                    NSArray *active = SafeApps(snapshot[@"activeApps"]);
                    NSArray *all = SafeApps(snapshot[@"allApps"]);
                    NSMutableDictionary *output = [@{
                        @"source": @"SideStore official widget_data.json",
                        @"activeApps": active,
                        @"allApps": all
                    } mutableCopy];
                    NSString *lastUpdated = ISODate(snapshot[@"lastUpdated"]);
                    if (lastUpdated) output[@"lastUpdated"] = lastUpdated;
                    NSData *safeJSON = [NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:&error];
                    exported = safeJSON && [safeJSON writeToFile:[outDir stringByAppendingPathComponent:@"widget_data.json"]
                                                       options:NSDataWritingAtomic error:&error];
                    reason = exported ? @"ok" : @"write-failed";
                } else {
                    reason = @"invalid-json";
                }
            }
            NSDictionary *report = @{
                @"version": @3,
                @"status": @"probe-only",
                @"timestamp": @([[NSDate date] timeIntervalSince1970]),
                @"hostBundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
                @"lcHomePathAvailable": @(getenv("LC_HOME_PATH") != NULL),
                @"lcSharedUtilsAvailable": @(utils != Nil),
                @"appGroupAvailable": @(group != nil),
                @"officialWidgetDataExists": @(found),
                @"widgetExported": @(exported),
                @"widgetExportStatus": reason,
                @"note": @"Only app name, bundle ID, refresh and expiration dates are exported. This does not trigger a refresh."
            };
            NSData *probeData = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
            [probeData writeToFile:[outDir stringByAppendingPathComponent:@"probe.json"] atomically:YES];
            NSLog(@"[LCWidgetProbe] v3 appgroup=%@ widget=%@ export=%@ (%@)",
                  group ? @"YES" : @"NO", found ? @"YES" : @"NO", exported ? @"YES" : @"NO", reason);
        }
    });
}
