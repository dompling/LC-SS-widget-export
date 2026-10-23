// LCWidgetProbe v5 - SideStore Core Data snapshot (read-only).
// Independent Guest App tweak for OFFICIAL LiveContainer+SideStore Nightly.
// Does not use or require the official widget_data.json or a home-screen widget.
// Reads ONLY the InstalledApp row for com.kdt.livecontainer; never reads user account
// tables, authentication records, signing keys, certificate blobs, or provisioning profiles.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#import <sqlite3.h>
#import <math.h>
#import <stdlib.h>

static NSString *const kLCBundleID = @"com.kdt.livecontainer";

static BOOL HasInstalledAppColumns(sqlite3 *db) {
    sqlite3_stmt *stmt = NULL;
    const char *sql = "PRAGMA table_info('ZINSTALLEDAPP')";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return NO;
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *rawName = sqlite3_column_text(stmt, 1);
        if (rawName) {
            [names addObject:[NSString stringWithUTF8String:(const char *)rawName]];
        }
    }
    sqlite3_finalize(stmt);
    for (NSString *required in @[
        @"ZNAME", @"ZBUNDLEIDENTIFIER", @"ZRESIGNEDBUNDLEIDENTIFIER",
        @"ZREFRESHEDDATE", @"ZEXPIRATIONDATE", @"ZISACTIVE"
    ]) {
        if (![names containsObject:required]) return NO;
    }
    return YES;
}

static NSString *ColumnString(sqlite3_stmt *stmt, int column) {
    const unsigned char *raw = sqlite3_column_text(stmt, column);
    if (!raw) return nil;
    return [NSString stringWithUTF8String:(const char *)raw];
}

static NSDictionary *ReadLiveContainerFromDatabase(sqlite3 *db, NSUInteger *matchCount,
                                                    NSString **status) {
    // Query only the required InstalledApp properties and only the LC bundle id.
    const char *sql =
        "SELECT ZNAME, ZBUNDLEIDENTIFIER, ZRESIGNEDBUNDLEIDENTIFIER,"
        " ZREFRESHEDDATE, ZEXPIRATIONDATE, ZISACTIVE"
        " FROM ZINSTALLEDAPP"
        " WHERE ZBUNDLEIDENTIFIER = ?1 OR ZRESIGNEDBUNDLEIDENTIFIER = ?2"
        " ORDER BY ZISACTIVE DESC, ZREFRESHEDDATE DESC LIMIT 16";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        *status = @"query-prepare-failed";
        return nil;
    }
    sqlite3_bind_text(stmt, 1, kLCBundleID.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, kLCBundleID.UTF8String, -1, SQLITE_TRANSIENT);

    NSDictionary *selected = nil;
    NSUInteger count = 0;
    int stepResult = SQLITE_DONE;
    while ((stepResult = sqlite3_step(stmt)) == SQLITE_ROW) {
        count++;
        if (selected) continue; // Prefer active, then most recently refreshed.
        if (sqlite3_column_type(stmt, 3) != SQLITE_FLOAT &&
            sqlite3_column_type(stmt, 3) != SQLITE_INTEGER) continue;
        if (sqlite3_column_type(stmt, 4) != SQLITE_FLOAT &&
            sqlite3_column_type(stmt, 4) != SQLITE_INTEGER) continue;
        double refreshed = sqlite3_column_double(stmt, 3);
        double expiration = sqlite3_column_double(stmt, 4);
        // Core Data Date is seconds since 2001-01-01; reject corrupt/out-of-range dates.
        if (!isfinite(refreshed) || !isfinite(expiration) ||
            refreshed < 0 || expiration < refreshed || expiration > 3500000000.0) continue;
        NSString *name = ColumnString(stmt, 0);
        NSString *bundle = ColumnString(stmt, 1);
        NSString *resigned = ColumnString(stmt, 2);
        if (!bundle.length) bundle = resigned;
        if (!bundle.length) continue;
        selected = @{
            @"name": name.length ? name : @"LiveContainer",
            @"bundleIdentifier": bundle,
            @"refreshedDate": @(refreshed),
            @"expirationDate": @(expiration),
            @"tintColorHex": NSNull.null,
            @"isActive": @(sqlite3_column_int(stmt, 5) != 0)
        };
    }
    sqlite3_finalize(stmt);
    *matchCount = count;
    if (stepResult != SQLITE_DONE) {
        *status = @"query-step-failed";
        return nil;
    }
    *status = selected ? @"ok" : (count ? @"invalid-app-dates" : @"no-matching-livecontainer");
    return selected;
}

__attribute__((constructor)) static void LCWidgetProbeInit(void) {
    NSLog(@"[LCWidgetProbe] v5 Core Data reader starting");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            const char *lcHomeRaw = getenv("LC_HOME_PATH");
            NSString *lcHome = lcHomeRaw && lcHomeRaw[0]
                ? [NSString stringWithUTF8String:lcHomeRaw] : nil;
            if (!lcHome.length) {
                NSLog(@"[LCWidgetProbe] v5 missing LC_HOME_PATH");
                return;
            }
            NSString *outDir = [lcHome stringByAppendingPathComponent:@"Documents/LCWidgetExport"];
            NSError *outputError = nil;
            BOOL folderReady = [fm createDirectoryAtPath:outDir
                             withIntermediateDirectories:YES attributes:nil error:&outputError];

            Class utils = NSClassFromString(@"LCSharedUtils");
            NSURL *group = nil;
            if (utils && [utils respondsToSelector:@selector(appGroupPath)]) {
                group = ((NSURL *(*)(id, SEL))objc_msgSend)(utils, @selector(appGroupPath));
            }

            NSString *databaseName = @"SideStore.sqlite";
            NSString *dbPath = [[group URLByAppendingPathComponent:@"Database"]
                                  URLByAppendingPathComponent:databaseName].path;
            BOOL databaseExists = dbPath.length && [fm fileExistsAtPath:dbPath];
            // Older database file name is supported for diagnostics, never merged with current DB.
            if (!databaseExists && group) {
                NSString *legacy = [[group URLByAppendingPathComponent:@"Database"]
                                       URLByAppendingPathComponent:@"AltStore.sqlite"].path;
                if ([fm fileExistsAtPath:legacy]) {
                    dbPath = legacy;
                    databaseName = @"AltStore.sqlite";
                    databaseExists = YES;
                }
            }

            NSString *status = folderReady ? @"database-not-found" : @"output-folder-failed";
            NSUInteger matchingRecords = 0;
            BOOL success = NO;
            BOOL outputVerified = NO;
            BOOL schemaRecognized = NO;
            BOOL rowActive = NO;
            BOOL sourceHasWAL = databaseExists &&
                [fm fileExistsAtPath:[dbPath stringByAppendingString:@"-wal"]];

            if (folderReady && databaseExists) {
                sqlite3 *db = NULL;
                // SQLITE_OPEN_READONLY means this tweak cannot modify the SideStore database.
                int rc = sqlite3_open_v2(dbPath.UTF8String, &db,
                                        SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
                if (rc != SQLITE_OK) {
                    status = @"database-open-failed";
                } else {
                    sqlite3_busy_timeout(db, 800);
                    schemaRecognized = HasInstalledAppColumns(db);
                    if (!schemaRecognized) {
                        status = @"installedapp-schema-mismatch";
                    } else {
                        NSDictionary *row = ReadLiveContainerFromDatabase(db, &matchingRecords, &status);
                        if (row) {
                            rowActive = [row[@"isActive"] boolValue];
                            NSMutableDictionary *safeApp = [row mutableCopy];
                            [safeApp removeObjectForKey:@"isActive"];
                            NSDictionary *output = @{
                                @"activeApps": rowActive ? @[safeApp] : @[],
                                @"allApps": @[safeApp],
                                // Date encoded just like SideStore's default Swift JSONEncoder:
                                // seconds since 2001-01-01 00:00:00 UTC.
                                // Represents snapshot generation time, NOT the last DB write.
                                @"lastUpdated": @([[NSDate date] timeIntervalSinceReferenceDate])
                            };
                            NSError *error = nil;
                            NSData *json = [NSJSONSerialization dataWithJSONObject:output
                                                options:NSJSONWritingPrettyPrinted error:&error];
                            NSString *outputPath = [outDir stringByAppendingPathComponent:@"widget_data.json"];
                            success = json && [json writeToFile:outputPath
                                               options:NSDataWritingAtomic error:&error];
                            outputVerified = success && [[NSData dataWithContentsOfFile:outputPath] isEqualToData:json];
                            status = outputVerified ? @"ok" : @"export-write-failed";
                        }
                    }
                }
                if (db) sqlite3_close(db);
            }

            // All diagnostic metadata is nonsensitive; the database itself is never copied.
            NSDictionary *report = @{
                @"version": @5,
                @"status": status,
                @"timestamp": @([[NSDate date] timeIntervalSince1970]),
                @"source": @"SideStore InstalledApp Core Data (read-only SQLite)",
                @"sourceDatabaseName": databaseName,
                @"sourceDatabaseExists": @(databaseExists),
                @"sourceHasWAL": @(sourceHasWAL),
                @"schemaRecognized": @(schemaRecognized),
                @"matchingRecordCount": @(matchingRecords),
                @"selectedRecordIsActive": @(rowActive),
                @"widgetExported": @(outputVerified),
                @"officialWidgetRequired": @NO,
                @"outputLocation": @"LC_HOME_PATH/Documents/LCWidgetExport",
                @"hostBundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
                @"note": @"widget_data.json here is a derived SideStore Core Data snapshot, not an official widget cache; lastUpdated is export time."
            };
            if (folderReady) {
                NSData *meta = [NSJSONSerialization dataWithJSONObject:report
                                  options:NSJSONWritingPrettyPrinted error:nil];
                [meta writeToFile:[outDir stringByAppendingPathComponent:@"probe.json"]
                         options:NSDataWritingAtomic error:nil];
            }
            NSLog(@"[LCWidgetProbe] v5 %@ DB=%@ present=%@ wal=%@ schema=%@ records=%lu",
                  status, databaseName, databaseExists ? @"YES" : @"NO",
                  sourceHasWAL ? @"YES" : @"NO", schemaRecognized ? @"YES" : @"NO",
                  (unsigned long)matchingRecords);
            if (!folderReady && outputError) NSLog(@"[LCWidgetProbe] v5 output dir error code=%ld", (long)outputError.code);
        }
    });
}
