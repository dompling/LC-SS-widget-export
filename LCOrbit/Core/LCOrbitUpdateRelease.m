#import "LCOrbitUpdateRelease.h"

static NSDictionary *RFail(NSError **error) {
    if(error) *error=[NSError errorWithDomain:@"LCOrbit.UpdateRelease" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"发布信息不完整，缺少有效版本、提交、官方资源地址或 SHA-256 校验值，已取消更新。"}];
    return nil;
}
static BOOL RMatches(id value,NSString *pattern) {
    if(![value isKindOfClass:NSString.class]) return NO;
    NSRange match=[value rangeOfString:pattern options:NSRegularExpressionSearch];
    return match.location==0 && match.length==[value length];
}
static BOOL RVersion(id value) {
    return RMatches(value,@"^[0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9}$");
}
@implementation LCOrbitUpdateRelease
+ (NSString *)notesFromBody:(id)body {
    if(![body isKindOfClass:NSString.class]) return @"此版本未提供更新说明。";
    NSMutableArray<NSString *> *lines=[NSMutableArray array];
    for(NSString *raw in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if([line hasPrefix:@"FM_VERSION="] || [line hasPrefix:@"FM_COMMIT="] ||
           [line hasPrefix:@"FM_TAG="] || [line hasPrefix:@"```"]) continue;
        // Native alerts show plain text; retain list content without Markdown
        // heading markers or the workflow's private metadata/code fences.
        while([line hasPrefix:@"#"]) line=[line substringFromIndex:1];
        [lines addObject:[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
    }
    NSString *notes=[[lines componentsJoinedByString:@"\n"]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(notes.length>12000) {
        NSRange range=[notes rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,12000)];
        notes=[[notes substringWithRange:range] stringByAppendingString:@"\n…完整说明可在 GitHub 对应版本中查看。"];
    }
    return notes.length?notes:@"此版本未提供更新说明。";
}
+ (NSDictionary<NSString *,NSString *> *)releaseFromJSON:(id)json error:(NSError **)error {
    if(![json isKindOfClass:NSDictionary.class] || ![json[@"body"] isKindOfClass:NSString.class] ||
       ![json[@"assets"] isKindOfClass:NSArray.class]) return RFail(error);
    NSString *version=nil,*commit=nil;
    for(NSString *raw in [json[@"body"] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if([line hasPrefix:@"FM_VERSION="]) {
            if(version) return RFail(error);
            version=[[line substringFromIndex:11] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }
        if([line hasPrefix:@"FM_COMMIT="]) {
            if(commit) return RFail(error);
            commit=[[line substringFromIndex:10] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }
    }
    for(id asset in json[@"assets"]) {
        if(![asset isKindOfClass:NSDictionary.class] || ![asset[@"name"] isEqual:@"LCFloatingMenu.dylib"]) continue;
        return [self validatedRelease:@{@"version":version?:@"",@"commit":commit?:@"",
            @"downloadURL":asset[@"browser_download_url"]?:@"",@"sha256":asset[@"digest"]?:@"",
            @"notes":[self notesFromBody:json[@"body"]]} error:error];
    }
    return RFail(error);
}
+ (NSDictionary<NSString *,NSString *> *)validatedRelease:(id)release error:(NSError **)error {
    if(![release isKindOfClass:NSDictionary.class] || !RVersion(release[@"version"]) ||
       !RMatches(release[@"commit"],@"^[0-9a-fA-F]{40}$") ||
       !RMatches(release[@"sha256"],@"^sha256:[0-9a-fA-F]{64}$") ||
       ![release[@"downloadURL"] isKindOfClass:NSString.class] ||
       ![release[@"notes"] isKindOfClass:NSString.class]) return RFail(error);
    NSString *link=release[@"downloadURL"];
    NSString *prefix=@"https://github.com/dompling/LC-SS-widget-export/releases/download/";
    NSURL *url=[NSURL URLWithString:link];
    NSArray<NSString *> *parts=url.path.pathComponents;
    if(![link hasPrefix:prefix] || !url || url.user || url.password || url.fragment ||
       (url.port && url.port.integerValue!=443) ||
       parts.count!=7 || !RMatches(parts[5],@"^[A-Za-z0-9_-][A-Za-z0-9._-]*$") ||
       ![url.lastPathComponent isEqualToString:@"LCFloatingMenu.dylib"]) return RFail(error);
    NSString *notes=release[@"notes"];
    if(notes.length>12500) return RFail(error);
    return @{@"version":release[@"version"],@"commit":release[@"commit"],
        @"downloadURL":link,@"sha256":release[@"sha256"],
        @"notes":notes.length?notes:@"此版本未提供更新说明。"};
}
+ (BOOL)isNewerRelease:(NSDictionary *)release thanVersion:(NSString *)installed {
    NSDictionary *valid=[self validatedRelease:release error:nil];
    if(!valid || !RVersion(installed)) return NO;
    NSArray *latest=[valid[@"version"] componentsSeparatedByString:@"."];
    NSArray *current=[installed componentsSeparatedByString:@"."];
    for(NSUInteger i=0;i<3;i++) {
        NSInteger a=[latest[i] integerValue],b=[current[i] integerValue];
        if(a!=b) return a>b;
    }
    return NO;
}
+ (BOOL)shouldOfferRelease:(NSDictionary *)release installedVersion:(NSString *)installed skippedVersion:(NSString *)skipped {
    return [self isNewerRelease:release thanVersion:installed] &&
        !(skipped && [release[@"version"] isEqualToString:skipped]);
}
@end
