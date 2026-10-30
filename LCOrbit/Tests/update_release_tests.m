#import <Foundation/Foundation.h>
#import "../Core/LCOrbitUpdateRelease.h"
static NSUInteger Checks,Failures;
static void Check(BOOL good,NSString *name) {Checks++;if(!good){Failures++;fprintf(stderr,"FAIL %s\n",name.UTF8String);}}
static NSDictionary *Fixture(NSString *version,NSString *notes) {
    NSString *body=[NSString stringWithFormat:@"FM_VERSION=%@\nFM_COMMIT=%@\nFM_TAG=%@\n\n%@",version,
        [@"a" stringByPaddingToLength:40 withString:@"a" startingAtIndex:0],version,notes];
    return @{@"body":body,@"assets":@[@{@"name":@"LCFloatingMenu.dylib",
        @"browser_download_url":@"https://github.com/dompling/LC-SS-widget-export/releases/download/fm-latest/LCFloatingMenu.dylib",
        @"digest":[@"sha256:" stringByPaddingToLength:71 withString:@"a" startingAtIndex:0]}]};
}
int main(void) {@autoreleasepool {
    NSError *error=nil;
    NSDictionary *json=Fixture(@"1.0.8",@"修复切换\n- 新增 GitHub 访问设置");
    NSDictionary *r=[LCOrbitUpdateRelease releaseFromJSON:json error:&error];
    Check(r && !error && [r[@"version"] isEqual:@"1.0.8"],@"normalizes latest release");
    Check([r[@"notes"] containsString:@"修复切换"] && [r[@"notes"] containsString:@"新增 GitHub 访问设置"],@"preserves public release notes");
    Check(![r[@"notes"] containsString:@"FM_VERSION"] && ![r[@"notes"] containsString:@"FM_COMMIT"] &&
          ![r[@"notes"] containsString:@"FM_TAG"],@"internal metadata not shown as release notes");
    Check([LCOrbitUpdateRelease isNewerRelease:r thanVersion:@"1.0.7"],@"new release compares numerically");
    Check(![LCOrbitUpdateRelease isNewerRelease:r thanVersion:@"1.0.8"] &&
          ![LCOrbitUpdateRelease isNewerRelease:r thanVersion:@"1.0.9"],@"same or older not offered");
    Check([LCOrbitUpdateRelease shouldOfferRelease:r installedVersion:@"1.0.7" skippedVersion:nil],@"unskipped new version offered");
    Check(![LCOrbitUpdateRelease shouldOfferRelease:r installedVersion:@"1.0.7" skippedVersion:@"1.0.8"],@"exact skipped version suppressed");
    Check([LCOrbitUpdateRelease shouldOfferRelease:r installedVersion:@"1.0.7" skippedVersion:@"1.0.6"],@"higher version still offered after earlier skip");
    NSDictionary *ten=[LCOrbitUpdateRelease releaseFromJSON:Fixture(@"1.0.10",@"notes") error:nil];
    Check([LCOrbitUpdateRelease isNewerRelease:ten thanVersion:@"1.0.9"],@"two-digit patch compares numerically");
    Check(![LCOrbitUpdateRelease shouldOfferRelease:r installedVersion:@"1.0.8" skippedVersion:nil],@"installed version not offered");
    Check([LCOrbitUpdateRelease validatedRelease:r error:nil]!=nil,@"cached metadata revalidates");
    for(id bad in @[[NSNull null],@[],@"text",@{},@{@"body":@YES,@"assets":@[]},@{@"body":@"FM_VERSION=1.0.8",@"assets":@{}}]) {
        error=nil;Check(![LCOrbitUpdateRelease releaseFromJSON:bad error:&error] && error,@"invalid JSON rejected with bounded error");
    }
    for(NSString *version in @[@"",@"1.2",@"1.2.3.4",@"1.0.beta",@"-1.0.8",@"999999999999999.0.0"]) {
        error=nil;Check(![LCOrbitUpdateRelease releaseFromJSON:Fixture(version,@"notes") error:&error] && error,@"invalid version rejected");
    }
    for(NSString *field in @[@"commit",@"downloadURL",@"sha256",@"notes"]) {
        NSMutableDictionary *bad=[r mutableCopy];bad[field]=@42;error=nil;
        Check(![LCOrbitUpdateRelease validatedRelease:bad error:&error] && error,[@"wrong cache type rejected " stringByAppendingString:field]);
    }
    for(NSString *url in @[@"http://github.com/dompling/LC-SS-widget-export/releases/download/fm-latest/LCFloatingMenu.dylib",
        @"https://evil.test/LCFloatingMenu.dylib",@"https://github.com/evil/repo/releases/download/x/LCFloatingMenu.dylib",
        @"https://github.com@evil.test/dompling/LC-SS-widget-export/releases/download/x/LCFloatingMenu.dylib"]) {
        NSMutableDictionary *bad=[r mutableCopy];bad[@"downloadURL"]=url;
        Check(![LCOrbitUpdateRelease validatedRelease:bad error:nil],@"cache cannot redirect install to foreign release");
    }
    NSMutableDictionary *newlineVersion=[r mutableCopy];newlineVersion[@"version"]=@"1.0.8\n";
    Check(![LCOrbitUpdateRelease validatedRelease:newlineVersion error:nil],@"cache version cannot contain trailing newline");
    for(NSString *url in @[@"https://github.com/dompling/LC-SS-widget-export/releases/download/../../evil/LCFloatingMenu.dylib",
        @"https://github.com/dompling/LC-SS-widget-export/releases/download/%2e%2e/LCFloatingMenu.dylib"]) {
        NSMutableDictionary *bad=[r mutableCopy];bad[@"downloadURL"]=url;
        Check(![LCOrbitUpdateRelease validatedRelease:bad error:nil],@"release asset path cannot traverse repository");
    }
    NSMutableDictionary *badDigest=[r mutableCopy];badDigest[@"sha256"]=[@"sha256:" stringByPaddingToLength:71 withString:@"z" startingAtIndex:0];
    Check(![LCOrbitUpdateRelease validatedRelease:badDigest error:nil],@"digest must contain hexadecimal SHA256");
    NSMutableDictionary *badCommit=[r mutableCopy];badCommit[@"commit"]=[@"z" stringByPaddingToLength:40 withString:@"z" startingAtIndex:0];
    Check(![LCOrbitUpdateRelease validatedRelease:badCommit error:nil],@"commit must be a full hexadecimal source revision");
    NSDictionary *empty=[LCOrbitUpdateRelease releaseFromJSON:Fixture(@"1.0.8",@"") error:nil];
    Check([empty[@"notes"] length]>0 && ![empty[@"notes"] containsString:@"FM_"],@"missing release notes has clear fallback");
    NSString *longNotes=[@"说明" stringByPaddingToLength:24000 withString:@"说明" startingAtIndex:0];
    NSDictionary *longRelease=[LCOrbitUpdateRelease releaseFromJSON:Fixture(@"1.0.8",longNotes) error:nil];
    Check([longRelease[@"notes"] length]>0 && [longRelease[@"notes"] length]<=12500,@"release note size bounded for alert and cache");
    NSMutableDictionary *extra=[r mutableCopy];extra[@"unused"]=@"discard";
    Check([LCOrbitUpdateRelease validatedRelease:extra error:nil].count==5,@"cache only retains public normalized fields");
    fprintf(stdout,"Update release metadata and skip policy: %lu assertions, %lu failures\n",(unsigned long)Checks,(unsigned long)Failures);
    return Failures?1:0;
}}
