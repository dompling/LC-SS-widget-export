// LCWidgetProbe: metadata-only probe for stock LiveContainer + SideStore Nightly.
// Loaded as a Guest App tweak. Does NOT hook authentication or read credential contents.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

static NSDictionary *Inspect(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDir];
    NSMutableDictionary *item = [@{@"relativePath": path ?: @"", @"exists": @(exists), @"isDirectory": @(isDir)} mutableCopy];
    if (exists && isDir) {
        NSError *error = nil;
        NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:path error:&error];
        item[@"readable"] = @(names != nil);
        item[@"entryCount"] = @(names.count);
        // Only a small allowlisted set of metadata filenames; no file contents or secrets.
        NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
            NSString *lower = name.lowercaseString;
            return [lower containsString:@"widget"] || [lower containsString:@"appinfo"] ||
                   [lower containsString:@"expiration"] || [lower containsString:@"certificate"];
        }];
        NSArray<NSString *> *matches = [names filteredArrayUsingPredicate:filter];
        item[@"matchingNames"] = [matches subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)20, matches.count))];
        if (error) item[@"error"] = error.localizedDescription;
    }
    return item;
}

__attribute__((constructor)) static void LCWidgetProbeInit(void) {
    // Constructor may execute very early; perform file work later on utility queue.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *home = NSHomeDirectory();
            // These are candidate paths only; existence varies by LC version and guest routing.
            NSArray *candidate = @[
                @"Documents/SideStore", @"Documents/SideStore/Library",
                @"Library/Preferences", @"Library/Application Support",
                @"Documents", @"Library/Caches"
            ];
            NSMutableArray *checks = [NSMutableArray array];
            for (NSString *relative in candidate) {
                NSMutableDictionary *result = [Inspect([home stringByAppendingPathComponent:relative]) mutableCopy];
                result[@"relativePath"] = relative;
                [checks addObject:result];
            }
            NSString *outDir = [home stringByAppendingPathComponent:@"Documents/LCWidgetProbe"];
            NSError *error = nil;
            [fm createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:&error];
            NSDictionary *report = @{
                @"version": @1,
                @"status": @"probe-only",
                @"timestamp": @([[NSDate date] timeIntervalSince1970]),
                @"hostBundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
                @"candidateDirectories": checks,
                @"warning": @"This probe does not provide app expiration dates and cannot grant Scripting access to private LC files."
            };
            NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
            BOOL saved = data && [data writeToFile:[outDir stringByAppendingPathComponent:@"probe.json"] options:NSDataWritingAtomic error:&error];
            NSLog(@"[LCWidgetProbe] metadata probe %@: %@", saved ? @"saved" : @"failed", saved ? outDir : error.localizedDescription);
        }
    });
}
