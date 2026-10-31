// LCFloatingMenu 1.0 | LC+SS Guest overlay and opt-in LC host UI overlay
// UIKit UI is rendered in the current Guest or developer-enabled LC host UI.
// The host can opt into LC's existing LiveProcess multitasking backend.
#import <UIKit/UIKit.h>
#import "../LCOrbit/Core/LCOrbitCore.h"
#import "../LCOrbit/Core/LCOrbitHost.h"
#import "../LCOrbit/Core/LCOrbitGitHub.h"
#import "../LCOrbit/Core/LCOrbitUpdateRelease.h"
#import "../LCOrbit/Core/LCOrbitStorage.h"
#import "../LCOrbit/Core/LCOrbitLog.h"
#import "../LCOrbit/Core/LCOrbitEventBus.h"
#import "../LCOrbit/Core/LCOrbitOverlayManager.h"
#import "../LCOrbit/Core/LCOrbitGuestService.h"
#import "../LCOrbit/Core/LCOrbitMultitask.h"
#import "../LCOrbit/Core/LCOrbitHostSettings.h"
#import "../LCOrbit/Core/LCOrbitPluginUpdater.h"
#import "../LCOrbit/Core/LCOrbitTweakAudit.h"
#import "../LCOrbit/Core/LCOrbitTweakSync.h"
#import "../LCOrbit/Core/LCOrbitSharedTweaksViewController.h"
#import "../LCOrbit/Core/LCOrbitLogViewer.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>

// Semantic version is maintained here; the exact source commit is embedded
// automatically by LCOrbit/Build/build.sh for reliable update comparison.
#define FM_MENU_VERSION @"1.0.13"
#ifndef FM_BUILD_COMMIT
#define FM_BUILD_COMMIT @"unknown"
#endif
static NSString *const FMRepositoryURL=@"https://github.com/dompling/LC-SS-widget-export";
static NSString *const FMUpdateAPI=@"https://api.github.com/repos/dompling/LC-SS-widget-export/releases/tags/fm-latest";
static NSString *const FMUpdateCacheVersion=@"LCFloatingMenu.updateIndicator.latestVersion";
static NSString *const FMUpdateCacheTime=@"LCFloatingMenu.updateIndicator.lastAttempt";
static NSString *const FMUpdateCacheSuccess=@"LCFloatingMenu.updateIndicator.lastSuccess";
static NSString *const FMUpdateCacheRelease=@"LCFloatingMenu.updateIndicator.release";
static NSString *const FMUpdateReleaseAvailable=@"LCFloatingMenuUpdateReleaseAvailable";
// Both the indicator and Settings use the same validated release metadata.
// fm-latest may contain only workflow metadata; its matching version tag
// holds the user-facing notes. A notes fetch failure still preserves a valid
// downloadable release and explicitly says notes are unavailable.
static NSUInteger FMUpdateRequestSequence=0;
static NSUInteger FMUpdateAcceptedSequence=0;
static void FMFetchUpdateRelease(NSTimeInterval timeout,void (^completion)(NSDictionary *,NSError *,NSUInteger)) {
    NSUInteger sequence=++FMUpdateRequestSequence;
    NSError *requestError=nil;
    NSURLRequest *request=[LCOrbitGitHub requestForURL:[NSURL URLWithString:FMUpdateAPI] timeout:timeout error:&requestError];
    if(!request) {completion(nil,requestError,sequence);return;}
    [LCOrbitGitHub performRequest:request completion:^(NSData *data,NSHTTPURLResponse *response,NSError *error) {
        if(error || response.statusCode!=200) {
            NSError *failure=error?:[NSError errorWithDomain:@"LCFloatingMenu.Update" code:response.statusCode
                userInfo:@{NSLocalizedDescriptionKey:[LCOrbitGitHub messageForStatusCode:response.statusCode]}];
            completion(nil,failure,sequence);return;
        }
        id json=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSError *metadataError=nil;
        NSDictionary *release=[LCOrbitUpdateRelease releaseFromJSON:json error:&metadataError];
        if(!release) {completion(nil,metadataError,sequence);return;}
        if(![release[@"notes"] isEqualToString:@"此版本未提供更新说明。"])
            {completion(release,nil,sequence);return;}
        NSString *version=release[@"version"];
        NSURL *notesURL=[NSURL URLWithString:[@"https://api.github.com/repos/dompling/LC-SS-widget-export/releases/tags/"
            stringByAppendingString:version]];
        NSURLRequest *notesRequest=[LCOrbitGitHub requestForURL:notesURL timeout:timeout error:nil];
        if(!notesRequest) {completion(release,nil,sequence);return;}
        [LCOrbitGitHub performRequest:notesRequest completion:^(NSData *notesData,NSHTTPURLResponse *notesResponse,NSError *notesError) {
            id detail=(!notesError && notesResponse.statusCode==200 && notesData.length)?
                [NSJSONSerialization JSONObjectWithData:notesData options:0 error:nil]:nil;
            if([detail isKindOfClass:NSDictionary.class] && [detail[@"tag_name"] isKindOfClass:NSString.class] &&
               [detail[@"tag_name"] isEqualToString:version]) {
                NSMutableDictionary *enriched=[release mutableCopy];
                enriched[@"notes"]=[LCOrbitUpdateRelease notesFromBody:detail[@"body"]];
                completion([enriched copy],nil,sequence);
            } else completion(release,nil,sequence);
        }];
    }];
}
// Cache updates run on the main queue. Version wins over request order;
// within a version, a newer request may accept a rebuilt artifact atomically.
// Matching artifacts can enrich missing notes without losing complete notes.
static NSDictionary *FMCacheUpdateRelease(NSDictionary *candidate,NSUInteger sequence) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSDictionary *incoming=[LCOrbitUpdateRelease validatedRelease:candidate error:nil];
    NSDictionary *current=[LCOrbitUpdateRelease validatedRelease:[defaults objectForKey:FMUpdateCacheRelease] error:nil];
    if(!incoming) return current;
    NSDictionary *accepted=incoming;
    if(!current || [LCOrbitUpdateRelease isNewerRelease:incoming thanVersion:current[@"version"]]) {
        FMUpdateAcceptedSequence=sequence;
    } else if([LCOrbitUpdateRelease isNewerRelease:current thanVersion:incoming[@"version"]]) {
        accepted=current;
    } else {
        BOOL sameArtifact=[incoming[@"version"] isEqual:current[@"version"]] &&
            [incoming[@"commit"] isEqual:current[@"commit"]] &&
            [incoming[@"sha256"] isEqual:current[@"sha256"]] &&
            [incoming[@"downloadURL"] isEqual:current[@"downloadURL"]];
        if(sameArtifact) {
            if(![current[@"notes"] isEqualToString:@"此版本未提供更新说明。"])
                accepted=current;
            FMUpdateAcceptedSequence=MAX(FMUpdateAcceptedSequence,sequence);
        } else if(sequence>=FMUpdateAcceptedSequence) FMUpdateAcceptedSequence=sequence;
        else accepted=current;
    }
    [defaults setObject:accepted forKey:FMUpdateCacheRelease];
    [defaults setObject:accepted[@"version"] forKey:FMUpdateCacheVersion];
    [defaults setDouble:NSDate.date.timeIntervalSince1970 forKey:FMUpdateCacheSuccess];
    if(![accepted isEqual:current])
        [NSNotificationCenter.defaultCenter postNotificationName:FMUpdateReleaseAvailable object:nil];
    return accepted;
}
static NSTimeInterval const FMUpdateRefreshInterval=6*60*60;
static NSTimeInterval const FMUpdateRetryInterval=15*60;
static NSInteger FMVersionCompare(NSString *latest,NSString *installed) {
    NSArray *a=[latest componentsSeparatedByString:@"."],*b=[installed componentsSeparatedByString:@"."];
    if(a.count!=3 || b.count!=3) return NSNotFound;
    for(NSUInteger i=0;i<3;i++) {
        for(NSString *part in @[a[i],b[i]]) {
            if(!part.length || [part rangeOfCharacterFromSet:[NSCharacterSet.decimalDigitCharacterSet invertedSet]].location!=NSNotFound)
                return NSNotFound;
        }
        NSInteger x=[a[i] integerValue],y=[b[i] integerValue];
        if(x>y) return NSOrderedDescending;
        if(x<y) return NSOrderedAscending;
    }
    return NSOrderedSame;
}
static NSString *FMCommitSummary(void) {
    NSString *hash=FM_BUILD_COMMIT;
    if(hash.length!=40) return @"未标记构建";
    return [hash substringToIndex:7];
}
static inline CGFloat Clamp(CGFloat x, CGFloat a, CGFloat b) { return fmax(a,fmin(b,x)); }
static UIColor *RGBA(CGFloat r,CGFloat g,CGFloat b,CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
// Reading a setting locks the config file and parses it twice (see LCOrbitStorage), and
// drawing the settings preview reads a few hundred of them. Between Begin and End the
// plugin's settings are served from one copy instead. Writes still go to the store.
@interface FMPreferenceSnapshot : LCOrbitPreferences
@property(nonatomic,copy) NSDictionary *values;
@end
@implementation FMPreferenceSnapshot
- (id)objectForKey:(NSString *)key {
    if(![key hasPrefix:@"LCFloatingMenu."] || [key isEqualToString:@"LCFloatingMenu.previousMultitaskMode"])
        return [super objectForKey:key];
    return self.values[key];
}
@end
static FMPreferenceSnapshot *FMSnapshot;
static NSUInteger FMSnapshotDepth;
static LCOrbitPreferences *HostDefaults(void) {
    if(FMSnapshot) return FMSnapshot;
    return [LCOrbitStorage preferences];
}
static void FMBeginPreferenceSnapshot(void) {
    if(FMSnapshotDepth++) return;
    FMSnapshot=[FMPreferenceSnapshot new];
    FMSnapshot.values=[[LCOrbitStorage preferences] dictionaryRepresentation];
}
static void FMEndPreferenceSnapshot(void) {
    if(FMSnapshotDepth && !--FMSnapshotDepth) FMSnapshot=nil;
}
static NSDictionary *GuestInfo(void) { return [LCOrbitHost guestInfo]; }
static BOOL FMHostUI(void) { return [LCOrbitHost isHostUI]; }
static NSString *GuestID(void) { return [LCOrbitHost guestIdentifier]; }
static NSString *FMAppKey(NSDictionary *app) { return app[@"identity"] ?: app[@"path"] ?: @""; }
static NSString *FMAppCaption(NSDictionary *app) {
    NSString *title=app[@"title"] ?: @"";
    NSString *state=[LCOrbitGuestService isCurrentGuest:app]?@"当前":app[@"status"];
    if(!state.length && [app[@"shared"] boolValue]) state=@"共享";
    return state.length?[NSString stringWithFormat:@"%@ · %@",title,state]:title;
}
// What a row shows. The current app already wears a green light, so its title does not
// have to say so as well; anything else (shared, unavailable) still belongs on the row.
static NSString *FMAppRowTitle(NSDictionary *app) {
    if([LCOrbitGuestService isCurrentGuest:app]) return app[@"title"] ?: @"";
    return FMAppCaption(app);
}
static NSString *Pref(NSString *key) { return [LCOrbitStorage key:key forModule:@"LCFloatingMenu"]; }
static BOOL BoolPref(NSString *key,BOOL def) {
    id v=[HostDefaults() objectForKey:Pref(key)];
    return v?[v boolValue]:def;
}
static CGFloat FloatPref(NSString *key,CGFloat def) {
    id v=[HostDefaults() objectForKey:Pref(key)];
    return v?[v doubleValue]:def;
}
static void SetPref(NSString *key,id value) {
    [HostDefaults() setObject:value forKey:Pref(key)];
    NSError *error=[LCOrbitStorage lastError];
    if(error) [NSNotificationCenter.defaultCenter postNotificationName:@"LCOrbitConfigurationWriteFailed"
        object:nil userInfo:@{@"error":error}];
}
static NSString *AppPref(void) {return [NSString stringWithFormat:@"appEnabled.%@", GuestID()];}
// Recency is independent of manual menu order and favorites. Store scoped
// identities so private/shared apps with identical filenames stay distinct.
static void FMRememberOpenedApp(NSDictionary *app) {
    if(!BoolPref(@"recentAppsFirst",NO) || ![app isKindOfClass:NSDictionary.class] ||
       [app[@"builtin"] boolValue]) return;
    NSString *key=FMAppKey(app);
    if(!key.length) return;
    id stored=[HostDefaults() objectForKey:Pref(@"recentOpenedAppKeys")];
    NSArray *previous=[stored isKindOfClass:NSArray.class]?stored:@[];
    if([previous.firstObject isEqualToString:key]) return;
    NSMutableArray<NSString *> *recent=[NSMutableArray arrayWithObject:key];
    for(id item in previous) {
        if([item isKindOfClass:NSString.class] && ![item isEqualToString:key] && recent.count<40)
            [recent addObject:item];
    }
    SetPref(@"recentOpenedAppKeys",recent);
}


// File work stays off the UI thread. Launch waits for sharing so the next
// shared Guest sees the updated dylib rather than racing the copy.
static void FMSyncSharedTweaks(void (^completion)(void)) {
    if(!FMHostUI() || ![LCOrbitTweakSync automaticSyncEnabled]) {
        if(completion) completion();
        return;
    }
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("LCOrbit.automatic-sharing",DISPATCH_QUEUE_SERIAL);});
    dispatch_async(queue,^{
        [LCOrbitTweakSync syncAutomaticallyIfNeeded];
        if(completion) dispatch_async(dispatch_get_main_queue(),completion);
    });
}

// Local diagnostics: bounded rotation, no app content, certificates or secrets.
static void FMLog(NSString *event, NSString *detail) {
    [LCOrbitLog appendEvent:event details:detail kind:@"runtime"];
}


// Public Guest APIs are implemented in LCOrbitGuestService for all future modules.
static NSArray<NSDictionary*> *InstalledApps(void) { return [LCOrbitGuestService installedApps]; }

// UIScreen describes the display's base appearance; a Guest's UIWindowScene
// can report its own forced Light/Dark appearance instead of the device choice.
// Read screen traits first so "Follow System" does not inherit Guest styling.
static __weak UIWindowScene *FMStyleScene;
static UIUserInterfaceStyle FMLastResolvedSystemStyle=UIUserInterfaceStyleLight;
static BOOL FMValidStyle(UIUserInterfaceStyle style) {
    return style==UIUserInterfaceStyleLight || style==UIUserInterfaceStyleDark;
}
static UIUserInterfaceStyle FMSystemAppearance(void) {
    UIUserInterfaceStyle style=UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    if(!FMValidStyle(style)) {
        style=FMStyleScene.traitCollection.userInterfaceStyle;
        if(!FMValidStyle(style)) {
            for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if(![scene isKindOfClass:UIWindowScene.class] ||
                   scene.activationState!=UISceneActivationStateForegroundActive) continue;
                style=((UIWindowScene *)scene).traitCollection.userInterfaceStyle;
                if(FMValidStyle(style)) break;
            }
        }
    }
    // Retain the last resolved style during transient Unspecified traits.
    if(FMValidStyle(style)) FMLastResolvedSystemStyle=style;
    return FMLastResolvedSystemStyle;
}
static UIUserInterfaceStyle FMMenuAppearance(void) {
    NSInteger mode=[HostDefaults() integerForKey:Pref(@"appearanceMode")];
    return mode==1?UIUserInterfaceStyleLight:mode==2?UIUserInterfaceStyleDark:FMSystemAppearance();
}
static UIUserInterfaceStyle FMMenuOverride(void) {
    // Even Follow System needs an explicit style: Unspecified inherits the
    // Guest's UIUserInterfaceStyle=Light / parent-window trait in some apps.
    // Override only our module view, never LCOrbit's shared UIWindow.
    return FMMenuAppearance();
}
static BOOL FMMenuDark(void) { return FMMenuAppearance()==UIUserInterfaceStyleDark; }
typedef NS_ENUM(NSUInteger, FMColorRole) {
    FMColorAccent, FMColorText, FMColorSecondary, FMColorBackground,
    FMColorSurface, FMColorGlass, FMColorRow, FMColorTool, FMColorBorder
};
static UIColor *FMFromHex(NSString *hex, unsigned fallback) {
    unsigned rgb=fallback;
    if([hex isKindOfClass:NSString.class] && hex.length==7 && [hex hasPrefix:@"#"]) {
        unsigned value=0;
        NSScanner *scanner=[NSScanner scannerWithString:[hex substringFromIndex:1]];
        if([scanner scanHexInt:&value] && scanner.isAtEnd) rgb=value;
    }
    return RGBA(((rgb>>16)&255)/255.,((rgb>>8)&255)/255.,(rgb&255)/255.,1);
}
static NSString *FMHex(UIColor *color) {
    CGFloat r=0,g=0,b=0,a=0;
    if(![color getRed:&r green:&g blue:&b alpha:&a]) return nil;
    return [NSString stringWithFormat:@"#%02X%02X%02X",
        (unsigned)round(Clamp(r,0,1)*255),(unsigned)round(Clamp(g,0,1)*255),
        (unsigned)round(Clamp(b,0,1)*255)];
}
static UIColor *FMMix(UIColor *a,UIColor *b,CGFloat ratio) {
    CGFloat ar=0,ag=0,ab=0,alpha=0,br=0,bg=0,bb=0;
    [a getRed:&ar green:&ag blue:&ab alpha:&alpha];
    [b getRed:&br green:&bg blue:&bb alpha:&alpha];
    ratio=Clamp(ratio,0,1);
    return RGBA(ar+(br-ar)*ratio,ag+(bg-ag)*ratio,ab+(bb-ab)*ratio,1);
}
static UIColor *FMAccentFor(BOOL dark) {
    return FMFromHex([HostDefaults() stringForKey:Pref(dark?@"accentDark":@"accentLight")],
                     dark?0x8AC9FF:0x245DAB);
}
static UIColor *FMThemeColor(FMColorRole role) {
    BOOL dark=FMMenuDark();
    UIColor *accent=FMAccentFor(dark);
    UIColor *surface=FMFromHex(nil,dark?0x1A2537:0xFFFFFF);
    switch(role) {
        case FMColorAccent: return accent;
        case FMColorText: return FMFromHex(nil,dark?0xF3F7FF:0x182638);
        case FMColorSecondary: return FMFromHex(nil,dark?0xC3CEDE:0x4B5B6C);
        case FMColorBackground: return FMMix(FMFromHex(nil,dark?0x0B1220:0xF7F9FD),accent,dark?.12:.085);
        case FMColorSurface: return FMMix(surface,accent,dark?.21:.075);
        case FMColorGlass: return FMMix(FMFromHex(nil,dark?0x22334A:0xF2F8FF),accent,.38);
        case FMColorRow: return FMMix(surface,accent,dark?.36:.18);
        case FMColorTool: return FMMix(surface,accent,dark?.43:.24);
        case FMColorBorder: return FMMix(FMFromHex(nil,dark?0x6B829A:0x97A8B8),accent,.36);
    }
    return surface;
}
static UIColor *FMAccent(void) { return FMThemeColor(FMColorAccent); }
static UIColor *FMSwitchGreen(void) {
    return [UIColor colorWithRed:52/255.0 green:199/255.0 blue:89/255.0 alpha:1.0];
}
// Recolor existing settings controls without replacing an active UIColorWell.
static NSArray<UIColor *> *FMSettingsPalette(void) {
    NSMutableArray *colors=[NSMutableArray array];
    for(NSUInteger role=FMColorAccent;role<=FMColorBorder;role++) [colors addObject:FMThemeColor(role)];
    for(NSNumber *alpha in @[@.20,@.25,@.35,@.50]) [colors addObject:[FMAccent() colorWithAlphaComponent:alpha.doubleValue]];
    return colors;
}
static UIColor *FMUpdatedSettingsColor(UIColor *color,NSArray *before,NSArray *after) {
    if(!color) return nil;
    NSUInteger index=[before indexOfObject:color];
    return index==NSNotFound?color:after[index];
}
static void FMRefreshSettingsColors(UIView *view,NSArray *before,NSArray *after) {
    if([view isKindOfClass:UIColorWell.class]) return;
    view.backgroundColor=FMUpdatedSettingsColor(view.backgroundColor,before,after);
    view.tintColor=FMUpdatedSettingsColor(view.tintColor,before,after);
    if(view.layer.borderColor) view.layer.borderColor=FMUpdatedSettingsColor(
        [UIColor colorWithCGColor:view.layer.borderColor],before,after).CGColor;
    if([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        label.textColor=FMUpdatedSettingsColor(label.textColor,before,after);
    }
    if([view isKindOfClass:UIButton.class]) {
        UIButton *button=(UIButton *)view;
        for(NSNumber *state in @[@(UIControlStateNormal),@(UIControlStateSelected)]) {
            UIColor *color=[button titleColorForState:state.unsignedIntegerValue];
            if(color) [button setTitleColor:FMUpdatedSettingsColor(color,before,after) forState:state.unsignedIntegerValue];
        }
    }
    if([view isKindOfClass:UISlider.class]) {view.tintColor=FMAccent();return;}
    if([view isKindOfClass:UISwitch.class]) {((UISwitch *)view).onTintColor=FMAccent();return;}
    for(UIView *child in view.subviews) FMRefreshSettingsColors(child,before,after);
}
static CGFloat FMOrbScale(void) {
    return Clamp(FloatPref(@"orbScale",Clamp(FloatPref(@"orbWidth",12)/12.,.70,1.90)),.70,1.90);
}
static NSArray<NSDictionary *> *FMOrbStyleOptions(void) {
    static NSArray *options;static dispatch_once_t once;
    dispatch_once(&once, ^{ options=@[
        // The first four shape the handle, with the wloc dock's ranges and steps.
        @{@"key":@"orbHandleReach",@"title":@"凸出宽度",@"min":@(14),@"max":@(34),@"default":@(22),@"unit":@"点",@"step":@(1)},
        @{@"key":@"orbHandleLength",@"title":@"长度",@"min":@(56),@"max":@(140),@"default":@(80),@"unit":@"点",@"step":@(2)},
        @{@"key":@"orbCapsuleCorner",@"title":@"圆角",@"min":@(0.55),@"max":@(1),@"default":@(0.83),@"unit":@"%",@"step":@(0.01)},
        @{@"key":@"orbSoftness",@"title":@"柔和度",@"min":@(0.4),@"max":@(1.6),@"default":@(1),@"unit":@"%",@"step":@(0.05)},
        @{@"key":@"orbGlowLength",@"title":@"背景散光长度",@"min":@(0),@"max":@(100),@"default":@(56),@"unit":@"点",@"step":@(1)},
        @{@"key":@"orbGlowBrightness",@"title":@"背景散光亮度",@"min":@(0),@"max":@(0.35),@"default":@(0.16),@"unit":@"%",@"step":@(0.01)},
        @{@"key":@"orbSnapDuration",@"title":@"吸边动画时长",@"min":@(0.2),@"max":@(0.65),@"default":@(0.34),@"unit":@"秒",@"step":@(0.01)},
        @{@"key":@"orbSnapDamping",@"title":@"吸边回弹阻尼",@"min":@(0.65),@"max":@(1),@"default":@(0.78),@"unit":@"%",@"step":@(0.01)},
        // How long the bead rests before it fades, and how faint it gets (the dock's ranges).
        @{@"key":@"fadeDelay",@"title":@"停手多久后淡化",@"min":@(2),@"max":@(15),@"default":@(5),@"unit":@"秒",@"step":@(1)},
        @{@"key":@"fadedOpacity",@"title":@"淡化后的透明度",@"min":@(0.05),@"max":@(0.6),@"default":@(0.2),@"unit":@"%",@"step":@(0.05)},
    ]; });
    return options;
}
static NSArray<NSDictionary *> *FMMenuStyleOptions(void) {
    return @[
        @{@"key":@"menuExtension",@"title":@"上下延展长度",@"min":@12,@"max":@44,@"default":@28,@"unit":@"点",@"step":@1},
        @{@"key":@"menuCornerRadius",@"title":@"外框圆角半径",@"min":@8,@"max":@36,@"default":@26,@"unit":@"点",@"step":@1},
        @{@"key":@"menuCurveSoftness",@"title":@"凹角弧度",@"min":@.2,@"max":@.9,@"default":@.64,@"unit":@"%",@"step":@.01},
        @{@"key":@"menuCompactIconSize",@"title":@"图标模式图标大小",@"min":@28,@"max":@50,@"default":@46,@"unit":@"点",@"step":@1},
        @{@"key":@"menuListIconSize",@"title":@"列表模式图标大小",@"min":@24,@"max":@44,@"default":@36,@"unit":@"点",@"step":@1}
    ];
}
static CGFloat FMMenuStyleValue(NSString *key) {
    for(NSDictionary *option in FMMenuStyleOptions()) if([option[@"key"] isEqualToString:key]) {
        CGFloat fallback=[option[@"default"] doubleValue],value=FloatPref(key,fallback);
        return Clamp(isfinite(value)?value:fallback,[option[@"min"] doubleValue],[option[@"max"] doubleValue]);
    }
    return 0;
}
static CGFloat FMOrbStyleValue(NSString *key) {
    for(NSDictionary *option in FMOrbStyleOptions()) if([option[@"key"] isEqualToString:key]) {
        CGFloat fallback=[option[@"default"] doubleValue];
        CGFloat value=FloatPref(key,fallback);
        return Clamp(isfinite(value)?value:fallback,[option[@"min"] doubleValue],[option[@"max"] doubleValue]);
    }
    return 0;
}
// 0 is the capsule, 1 the droplet.
static BOOL FMOrbHandleIsCapsule(void) {
    return !(FloatPref(@"orbHandleStyle",0)>=.5);
}
// The side silhouettes (the docked handle, the drawer) are members of one
// nine-segment family (M C L C L C L C Z), so any frame between two of them moves
// a handful of parameters instead of blending Bezier controls, which would bulge
// the shoulders. Values describe a right-hand dock; callers mirror the finished
// path for a left dock. A root flare with a negative vertical size is a convex
// corner of the body instead of a concave flare onto the wall.
typedef struct {
    CGFloat left,top,wall,bottom; // inner edge, top and bottom at the wall, docking wall
    CGFloat rx,ryt,ryb;           // root flares: horizontal size, vertical size of the top and the bottom one
    CGFloat a,b;                  // flare handle ratios (vertical / horizontal)
    CGFloat rdx,rdy,kx,ky;        // inner corners: radii and handle lengths
} FMNotchParams;
static inline CGFloat FMLerp(CGFloat from,CGFloat to,CGFloat t) { return from+(to-from)*t; }
static inline CGFloat FMSmooth(CGFloat x) { x=Clamp(x,0,1); return x*x*(3-2*x); }
static UIBezierPath *FMNotchFamilyPath(FMNotchParams p) {
    CGFloat x1=p.wall-p.rx,x2=p.left+p.rdx;
    CGFloat t0=p.top+p.ryt,b0=p.bottom-p.ryb;
    UIBezierPath *path=[UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(p.wall,p.top)];
    [path addCurveToPoint:CGPointMake(x1,t0)
            controlPoint1:CGPointMake(p.wall,p.top+p.ryt*p.a)
            controlPoint2:CGPointMake(x1+p.rx*p.b,t0)];
    [path addLineToPoint:CGPointMake(x2,t0)];
    [path addCurveToPoint:CGPointMake(p.left,t0+p.rdy)
            controlPoint1:CGPointMake(x2-p.kx,t0)
            controlPoint2:CGPointMake(p.left,t0+p.rdy-p.ky)];
    [path addLineToPoint:CGPointMake(p.left,b0-p.rdy)];
    [path addCurveToPoint:CGPointMake(x2,b0)
            controlPoint1:CGPointMake(p.left,b0-p.rdy+p.ky)
            controlPoint2:CGPointMake(x2-p.kx,b0)];
    [path addLineToPoint:CGPointMake(x1,b0)];
    [path addCurveToPoint:CGPointMake(p.wall,p.bottom)
            controlPoint1:CGPointMake(x1+p.rx*p.b,b0)
            controlPoint2:CGPointMake(p.wall,p.bottom-p.ryb*p.a)];
    [path closePath];
    return path;
}
// The open drawer, exactly as FMSideNotchPath draws it.
static FMNotchParams FMDrawerNotchParams(CGFloat w,CGFloat h,BOOL compact) {
    CGFloat r=MIN(FMMenuStyleValue(@"menuExtension")*(compact?26./28:30./28),MIN(w*.48,h*.17));
    CGFloat radius=MIN(FMMenuStyleValue(@"menuCornerRadius")*(compact?1:30./26),MIN(w-r,h*.25));
    CGFloat softness=FMMenuStyleValue(@"menuCurveSoftness");
    FMNotchParams p={0,0,w,h,r,r,r,softness,1,radius,radius,radius,radius*(1-(1-softness)*1.25)};
    return p;
}
// The docked handle as the wloc dock draws it (its DockLayout.metrics(at: 0) with
// DockMetrics.clamped()), in screen points and measured from the docking wall.
// The capsule has four convex corners of one size; the droplet has concave
// flares onto the wall (a negative length is a convex corner, as in the capsule).
typedef struct {
    CGFloat reach,half;                                  // protrusion from the wall, half the body length
    CGFloat topLength,topDepth,bottomLength,bottomDepth; // wall corners: along the wall / out from it
    CGFloat cornerX,cornerY,cornerK;                     // outer corner radii and handle ratio
} FMHandleMetrics;
static FMHandleMetrics FMHandleMetricsFor(CGFloat reach,CGFloat length,CGFloat softness,BOOL capsule,CGFloat cornerScale) {
    CGFloat depth=MIN(.586*reach*softness,.8*reach),tail=.675*reach*softness;
    FMHandleMetrics m={reach,length/2,depth*(.675/.586),depth,tail,depth,.413*reach,.525*reach,.575};
    if(capsule) {
        // The outer corners are rounded blunt ellipses (wider than they are tall)
        // and the wall corners turn into the same shape.
        CGFloat cx=cornerScale*reach/2,cy=MIN(cx*.525/.413,length/2);
        m.topLength=m.bottomLength=-cy;
        m.topDepth=m.bottomDepth=cx;
        m.cornerX=cx;m.cornerY=cy;
    }
    m.reach=MAX(m.reach,4);
    m.half=MAX(m.half,8);
    m.cornerX=Clamp(m.cornerX,0,m.reach*.5);
    m.cornerY=Clamp(m.cornerY,0,m.half);
    // A wall corner's depth plus the outer corner's radius must fit in the reach.
    CGFloat room=MAX(m.reach-m.cornerX,0);
    if(m.topLength<0) m.topLength=-MIN(-m.topLength,m.half);
    if(m.bottomLength<0) m.bottomLength=-MIN(-m.bottomLength,m.half);
    m.topDepth=Clamp(m.topDepth,0,room);
    m.bottomDepth=Clamp(m.bottomDepth,0,room);
    return m;
}
// The handle's own frame: reach wide, and as tall as the body plus the longer
// wall flare on each side.
static CGSize FMHandleFrameSize(FMHandleMetrics m) {
    return CGSizeMake(m.reach,2*m.half+2*MAX(0,MAX(m.topLength,m.bottomLength)));
}
// The handle as family parameters. unit converts screen points into the
// coordinates of the path; left and top place the handle's frame. At rest the
// top and bottom wall corners are equally deep and of one kind (see
// FMHandleMetricsFor), so they share a depth and a handle ratio; only their
// lengths along the wall can differ.
static FMNotchParams FMHandleNotchParams(FMHandleMetrics m,CGFloat unit,CGFloat left,CGFloat top) {
    CGFloat mid=FMHandleFrameSize(m).height*.5,bodyTop=mid-m.half,bodyBottom=mid+m.half;
    CGFloat flare=m.topLength>=0?.725:m.cornerK;
    FMNotchParams p={left,top+(bodyTop-m.topLength)*unit,left+m.reach*unit,top+(bodyBottom+m.bottomLength)*unit,
        m.topDepth*unit,m.topLength*unit,m.bottomLength*unit,flare,flare,
        m.cornerX*unit,m.cornerY*unit,m.cornerK*m.cornerX*unit,m.cornerK*m.cornerY*unit};
    return p;
}
// The handle the settings describe, in screen points. The bead-size setting
// scales reach and length; the rest follows from them.
static FMHandleMetrics FMOrbHandleMetrics(BOOL capsule) {
    CGFloat scale=FMOrbScale();
    return FMHandleMetricsFor(FMOrbStyleValue(@"orbHandleReach")*scale,FMOrbStyleValue(@"orbHandleLength")*scale,
        FMOrbStyleValue(@"orbSoftness"),capsule,FMOrbStyleValue(@"orbCapsuleCorner"));
}
// A mirrored, gently concave inner shoulder joins the side edge to the drawer.
// The glass and its shadow use exactly the same path.
static UIBezierPath *FMSideNotchPath(CGRect bounds, BOOL dockLeft, BOOL compact, BOOL collapsed) {
    CGFloat w=CGRectGetWidth(bounds),h=CGRectGetHeight(bounds);
    UIBezierPath *path;
    if(collapsed) {
        // The docked handle, in the style the settings choose: against the wall,
        // centered along the bounds.
        FMHandleMetrics handle=FMOrbHandleMetrics(FMOrbHandleIsCapsule());
        CGSize size=FMHandleFrameSize(handle);
        path=FMNotchFamilyPath(FMHandleNotchParams(handle,1,w-size.width,(h-size.height)*.5));
    } else {
        CGFloat r=MIN(FMMenuStyleValue(@"menuExtension")*(compact?26./28:30./28),MIN(w*.48,h*.17));
        path=[UIBezierPath bezierPath];
        CGFloat radius=MIN(FMMenuStyleValue(@"menuCornerRadius")*(compact?1:30./26),MIN(w-r,h*.25));
        CGFloat softness=FMMenuStyleValue(@"menuCurveSoftness");
        // Keep extension and the inward-facing corner radius independent.
        [path moveToPoint:CGPointMake(w,0)];
        [path addCurveToPoint:CGPointMake(w-r,r)
                controlPoint1:CGPointMake(w,r*softness)
                controlPoint2:CGPointMake(w,r)];
        CGFloat inner=radius;
        [path addLineToPoint:CGPointMake(inner,r)];
        [path addCurveToPoint:CGPointMake(0,r+radius)
                controlPoint1:CGPointMake(0,r)
                controlPoint2:CGPointMake(0,r+radius*(1-softness)*1.25)];
        [path addLineToPoint:CGPointMake(0,h-r-radius)];
        [path addCurveToPoint:CGPointMake(inner,h-r)
                controlPoint1:CGPointMake(0,h-r-radius*(1-softness)*1.25)
                controlPoint2:CGPointMake(0,h-r)];
        [path addLineToPoint:CGPointMake(w-r,h-r)];
        [path addCurveToPoint:CGPointMake(w,h)
                controlPoint1:CGPointMake(w,h-r)
                controlPoint2:CGPointMake(w,h-r*softness)];
        [path closePath];
    }
    if(dockLeft) {
        CGAffineTransform flip=CGAffineTransformMake(-1,0,0,1,w,0);
        [path applyTransform:flip];
    }
    return path;
}
static void FMApplySideNotch(UIView *glass,CALayer *shadow,BOOL dockLeft,BOOL compact,BOOL collapsed) {
    UIBezierPath *outline=FMSideNotchPath(glass.bounds,dockLeft,compact,collapsed);
    CAShapeLayer *clip=[CAShapeLayer layer];
    clip.frame=glass.bounds;
    clip.path=outline.CGPath;
    // Rounded-rectangle clipping would cut off the reverse shoulders.
    glass.layer.cornerRadius=0;
    glass.layer.borderWidth=0;
    glass.layer.mask=clip;
    shadow.shadowPath=outline.CGPath;
    // Native glass shades a rectangular boundary. Trace only the custom
    // contour so the reverse shoulders retain a quiet glass-edge highlight.
    CAShapeLayer *rim=[CAShapeLayer layer];
    rim.frame=glass.bounds;
    rim.path=outline.CGPath;
    rim.fillColor=UIColor.clearColor.CGColor;
    // The docked handle is a small shape with nothing but its own outline to stand on,
    // and on a pale screen a fainter one than this disappears into the wallpaper.
    rim.strokeColor=[(collapsed && !FMMenuDark()?UIColor.blackColor:UIColor.whiteColor) colorWithAlphaComponent:
        collapsed?(FMMenuDark()?.42:.32):(FMMenuDark()?.32:.58)].CGColor;
    rim.lineWidth=collapsed?.7:.75;
    [glass.layer addSublayer:rim];
    if(!collapsed) {
        // A broad, low-opacity reflection gives the custom silhouette depth
        // without replacing the live system material with an opaque fill.
        CAGradientLayer *reflection=[CAGradientLayer layer];
        reflection.frame=glass.bounds;
        reflection.colors=@[(id)[UIColor.whiteColor colorWithAlphaComponent:.13].CGColor,
                            (id)[UIColor.whiteColor colorWithAlphaComponent:.025].CGColor,
                            (id)[UIColor.blackColor colorWithAlphaComponent:.08].CGColor,
                            (id)[UIColor.whiteColor colorWithAlphaComponent:.07].CGColor];
        reflection.locations=@[@0,@.24,@.72,@1];
        reflection.startPoint=CGPointMake(dockLeft?1:0,0);
        reflection.endPoint=CGPointMake(dockLeft?0:1,1);
        [glass.layer insertSublayer:reflection atIndex:1];
    }
}
// The raised capsule has its own rounded optical fill, without an inset
// stroke. Its broader edge backing remains visible above and below it.
static void FMLayoutOrbCapsule(UIView *glass) {
    CGFloat w=glass.bounds.size.width,h=glass.bounds.size.height;
    // The fill is the capsule outline: all of the capsule handle, and for the
    // droplet just the body between its two flares.
    FMHandleMetrics pill=FMOrbHandleMetrics(YES);
    CGFloat body=FMHandleFrameSize(pill).height;
    for(CALayer *layer in glass.layer.sublayers) {
        if([layer.name isEqualToString:@"fm.orb.capsule"]) {
            layer.frame=CGRectMake(0,(h-body)*.5,w,body);
            layer.cornerRadius=0;
            CAShapeLayer *mask=(CAShapeLayer *)layer.mask;
            if(!mask) {mask=[CAShapeLayer layer];layer.mask=mask;}
            mask.frame=layer.bounds;
            __attribute__((objc_precise_lifetime)) UIBezierPath *fill=FMNotchFamilyPath(FMHandleNotchParams(pill,1,0,0));
            mask.path=fill.CGPath;
        } else if([layer.name isEqualToString:@"fm.orb.surface"]) {
            layer.frame=glass.bounds;
        }
    }
}
static void FMAddOrbCapsule(UIView *glass,BOOL left) {
    CAGradientLayer *surface=[CAGradientLayer layer];
    surface.name=@"fm.orb.surface";
    surface.colors=@[(id)[UIColor.whiteColor colorWithAlphaComponent:.08].CGColor,
                     (id)[UIColor.whiteColor colorWithAlphaComponent:.02].CGColor,
                     (id)[UIColor.whiteColor colorWithAlphaComponent:.10].CGColor];
    surface.locations=@[@0,@.48,@1];
    surface.startPoint=CGPointMake(0,0);surface.endPoint=CGPointMake(1,1);
    [glass.layer addSublayer:surface];
    CAGradientLayer *capsule=[CAGradientLayer layer];
    capsule.name=@"fm.orb.capsule";
    // Preserve a subtle highlight, but do not wash the dark bead back to
    // white when iOS native glass is sampling a Guest with a light canvas.
    capsule.colors=FMMenuDark()?@[(id)[UIColor.whiteColor colorWithAlphaComponent:.24].CGColor,
                     (id)[UIColor.whiteColor colorWithAlphaComponent:.09].CGColor,
                     (id)[UIColor.whiteColor colorWithAlphaComponent:.18].CGColor]:
                   @[(id)[UIColor.blackColor colorWithAlphaComponent:.16].CGColor,
                     (id)[UIColor.blackColor colorWithAlphaComponent:.07].CGColor,
                     (id)[UIColor.blackColor colorWithAlphaComponent:.12].CGColor];
    capsule.locations=@[@0,@.52,@1];
    capsule.startPoint=CGPointMake(left?1:0,0);capsule.endPoint=CGPointMake(left?0:1,1);
    capsule.cornerCurve=kCACornerCurveCircular;
    [glass.layer addSublayer:capsule];
    FMLayoutOrbCapsule(glass);
}
// This backdrop extends beyond the handle but never expands its hit target.
// Faded ends and a soft horizontal falloff prevent a second visible frame.
static void FMLayoutOrbBackdrop(UIView *orb,BOOL left) {
    UIView *backdrop=[orb viewWithTag:9204];
    CGFloat w=16*FMOrbScale(),h=orb.bounds.size.height;
    CGFloat reach=FMOrbStyleValue(@"orbGlowLength")*FMOrbScale();
    backdrop.frame=CGRectMake(left?0:orb.bounds.size.width-w*.85,-reach,w*.85,h+reach*2);
    for(CALayer *layer in backdrop.layer.sublayers) {
        if([layer.name isEqualToString:@"fm.edge.light"]) {
            layer.frame=backdrop.bounds;
            ((CAGradientLayer *)layer).startPoint=CGPointMake(left?1:0,.5);
            ((CAGradientLayer *)layer).endPoint=CGPointMake(left?0:1,.5);
        }
    }
    backdrop.layer.mask.frame=backdrop.bounds;
    CGFloat fade=reach/MAX(1,backdrop.bounds.size.height);
    ((CAGradientLayer *)backdrop.layer.mask).locations=@[@0,@(fade),@(1-fade),@1];
}
static void FMAddOrbBackdrop(UIView *orb,BOOL left) {
    UIView *backdrop=[[UIView alloc] initWithFrame:CGRectZero];
    backdrop.tag=9204;backdrop.userInteractionEnabled=NO;
    CAGradientLayer *light=[CAGradientLayer layer];
    light.name=@"fm.edge.light";
    light.colors=@[(id)UIColor.clearColor.CGColor,
                   (id)[UIColor.whiteColor colorWithAlphaComponent:FMOrbStyleValue(@"orbGlowBrightness")].CGColor];
    light.startPoint=CGPointMake(left?1:0,.5);
    light.endPoint=CGPointMake(left?0:1,.5);
    [backdrop.layer addSublayer:light];
    CAGradientLayer *fade=[CAGradientLayer layer];
    fade.colors=@[(id)UIColor.clearColor.CGColor,(id)UIColor.blackColor.CGColor,
                  (id)UIColor.blackColor.CGColor,(id)UIColor.clearColor.CGColor];
    fade.locations=@[@0,@.25,@.75,@1];backdrop.layer.mask=fade;
    [orb insertSubview:backdrop atIndex:0];
    FMLayoutOrbBackdrop(orb,left);
}
// One outline for the bead's clip, rim and shadow, set without animation. The
// caller owns the Bezier wrapper for the whole call, so the borrowed CGPath
// cannot be freed before every layer has retained it.
static void FMApplyOrbOutline(UIButton *button,UIBezierPath *outline) {
    UIView *glass=[button viewWithTag:9202];
    CAShapeLayer *mask=(CAShapeLayer *)glass.layer.mask;
    if(![mask isKindOfClass:CAShapeLayer.class]) return;
    mask.frame=glass.bounds;
    mask.path=outline.CGPath;
    for(CALayer *layer in glass.layer.sublayers)
        if([layer.name isEqualToString:@"fm.orb.rim"] && [layer isKindOfClass:CAShapeLayer.class]) {
            layer.frame=glass.bounds;
            ((CAShapeLayer *)layer).path=outline.CGPath;
            break;
        }
    button.layer.shadowPath=outline.CGPath;
}
// FMDrawerMotion:begin
// The drawer grows out of the docked handle as one continuous outline, a move
// between two members of the notch family (see FMNotchParams).
static FMNotchParams FMNotchLerp(FMNotchParams a,FMNotchParams b,CGFloat t) {
    FMNotchParams p={FMLerp(a.left,b.left,t),FMLerp(a.top,b.top,t),FMLerp(a.wall,b.wall,t),FMLerp(a.bottom,b.bottom,t),
        FMLerp(a.rx,b.rx,t),FMLerp(a.ryt,b.ryt,t),FMLerp(a.ryb,b.ryb,t),FMLerp(a.a,b.a,t),FMLerp(a.b,b.b,t),
        FMLerp(a.rdx,b.rdx,t),FMLerp(a.rdy,b.rdy,t),FMLerp(a.kx,b.kx,t),FMLerp(a.ky,b.ky,t)};
    return p;
}
// Width follows the finger one to one. Height starts later (t^1.3) so the first
// thing that appears is a round head. A capsule turns into the droplet within the
// first fifth of the way, as in the wloc dock, which is where the softness
// setting shows; from there both styles move alike. capsule and droplet are the
// two handles around one centre (pass the droplet twice for the droplet style).
static FMNotchParams FMNotchMorphParams(FMNotchParams capsule,FMNotchParams droplet,FMNotchParams drawer,CGFloat t) {
    t=Clamp(t,0,1);
    FMNotchParams bead=FMNotchLerp(droplet,capsule,1-FMSmooth(t/.2));
    CGFloat tw=t,th=pow(t,1.3);
    FMNotchParams p;
    p.left=FMLerp(bead.left,drawer.left,tw);
    p.top=FMLerp(bead.top,drawer.top,th);
    p.bottom=FMLerp(bead.bottom,drawer.bottom,th);
    p.wall=drawer.wall;
    p.rx=FMLerp(bead.rx,drawer.rx,tw);
    p.ryt=FMLerp(bead.ryt,drawer.ryt,th);
    p.ryb=FMLerp(bead.ryb,drawer.ryb,th);
    p.a=FMLerp(bead.a,drawer.a,t);
    p.b=FMLerp(bead.b,drawer.b,t);
    // A corner can neither pass the start of the root flare nor leave the
    // straight side shorter than zero. Its radii grow from the handle's to the
    // drawer's over the first 40% of the way.
    CGFloat reach=(p.wall-p.rx)-p.left;
    CGFloat room=((p.bottom-p.ryb)-(p.top+p.ryt))*.5;
    CGFloat grow=FMSmooth(t/.4);
    p.rdx=MAX(0,MIN(FMLerp(bead.rdx,drawer.rdx,grow),reach));
    p.rdy=MAX(0,MIN(FMLerp(bead.rdy,drawer.rdy,grow),room));
    CGFloat blend=FMSmooth(t/.5);
    p.kx=p.rdx*FMLerp(bead.kx/MAX(bead.rdx,1e-6),drawer.kx/MAX(drawer.rdx,1e-6),blend);
    p.ky=p.rdy*FMLerp(bead.ky/MAX(bead.rdy,1e-6),drawer.ky/MAX(drawer.rdy,1e-6),blend);
    return p;
}
// The silhouette at progress t, in the drawer's own coordinates. drawer comes
// from FMDrawerNotchParams for these same bounds (callers keep it for the whole
// transition so a frame never reads preferences). Progress 1 is the regular
// drawer outline so the last frame matches a normal build exactly.
static UIBezierPath *FMDrawerMorphPath(CGRect bounds,FMNotchParams capsule,FMNotchParams droplet,FMNotchParams drawer,BOOL dockLeft,BOOL compact,CGFloat t) {
    if(t>=1) return FMSideNotchPath(bounds,dockLeft,compact,NO);
    UIBezierPath *path=FMNotchFamilyPath(FMNotchMorphParams(capsule,droplet,drawer,t));
    if(dockLeft) [path applyTransform:CGAffineTransformMake(-1,0,0,1,CGRectGetWidth(bounds),0)];
    return path;
}
// Both handle styles laid out around one centre in the drawer's own coordinates, as a
// capsule turns into the droplet on its way out. unit converts screen points into
// those coordinates, pw and ph are the drawer's size, centre is where the bead sits
// along it. The centre is held where the taller of the two frames (the droplet's)
// still fits inside the drawer; shift is how far it had to move. NO when a handle
// cannot fit in the drawer at all. For the droplet style bead and dropletBead are
// the same.
static BOOL FMPlaceHandles(FMHandleMetrics capsule,FMHandleMetrics droplet,BOOL capsuleStyle,CGFloat unit,CGFloat pw,CGFloat ph,
                           CGFloat centre,FMNotchParams *bead,FMNotchParams *dropletBead,CGFloat *shift) {
    CGFloat capsuleHeight=FMHandleFrameSize(capsule).height*unit,dropletHeight=FMHandleFrameSize(droplet).height*unit;
    CGFloat tallest=MAX(capsuleHeight,dropletHeight);
    if(droplet.reach*unit>=pw || tallest>ph) return NO;
    CGFloat held=Clamp(centre,tallest*.5,ph-tallest*.5);
    *dropletBead=FMHandleNotchParams(droplet,unit,pw-droplet.reach*unit,held-dropletHeight*.5);
    *bead=capsuleStyle?FMHandleNotchParams(capsule,unit,pw-capsule.reach*unit,held-capsuleHeight*.5):*dropletBead;
    *shift=centre-held;
    return YES;
}
// Pull needed to commit opening: about a third of the travel, kept within a
// range a thumb can judge. scale follows the bead size setting.
static CGFloat FMDrawerCommitDistance(CGFloat travel,CGFloat scale) {
    return Clamp(travel*.35,28*scale,72*scale);
}
// What a drag that began on the bead is, from how far the finger has gone inward
// (toward the screen) and along the edge since it began: neither until it has gone a few
// points one way, so a vertical slide that merely drifts inward never starts building the
// drawer, and a pull that wobbles sideways never moves the bead.
enum { FMBeadPanUnclear,FMBeadPanPull,FMBeadPanMove };
static int FMBeadPanIntent(CGFloat inward,CGFloat vertical) {
    if(vertical>=8 && vertical>inward*1.2) return FMBeadPanMove;
    if(inward>=6 && inward>vertical) return FMBeadPanPull;
    return FMBeadPanUnclear;
}
// How far the bead must be pulled to count as opening when no drawer follows the
// finger (Reduce Motion). scale follows the bead size setting.
static CGFloat FMQuietPullDistance(CGFloat scale) {
    return 40*scale;
}
// Release after pulling the bead: far enough, flicked inward without drifting
// sideways, or barely moved at all (a tap that slipped into a pan).
static BOOL FMDrawerShouldOpenAfterPull(CGFloat pull,CGFloat commit,CGFloat inwardVelocity,CGFloat vertical,CGFloat total) {
    return pull>=commit || (inwardVelocity>180 && vertical<60) || total<6;
}
// Release after dragging the open drawer toward its edge. A fast flick
// decides alone; otherwise the progress it would reach in 0.12 s must fall
// below 0.62. progress is 1 when fully open, travel in screen points.
static BOOL FMDrawerShouldCloseAfterDrag(CGFloat progress,CGFloat outwardVelocity,CGFloat travel) {
    if(outwardVelocity>450) return YES;
    if(outwardVelocity<-450) return NO;
    return progress-outwardVelocity*.12/MAX(travel,1)<.62;
}
// Spring advanced by exactly dt seconds. It is the closed form, so the result
// does not depend on the frame rate. omega is the natural frequency in rad/s
// (2*pi/response); zeta is the damping ratio: 1 never overshoots, below 1 it
// overshoots by exp(-pi*zeta/sqrt(1-zeta^2)) (about 5.4% at .68) and rings down.
static void FMSpringStep(CGFloat *x,CGFloat *v,CGFloat target,CGFloat omega,CGFloat zeta,CGFloat dt) {
    CGFloat u=*x-target;
    if(zeta>=.999) {
        CGFloat c=*v+omega*u,decay=exp(-omega*dt);
        *x=target+(u+c*dt)*decay;
        *v=(*v-omega*c*dt)*decay;
        return;
    }
    CGFloat damping=zeta*omega,ringing=omega*sqrt(1-zeta*zeta);
    CGFloat decay=exp(-damping*dt),cosine=cos(ringing*dt),sine=sin(ringing*dt);
    CGFloat b=(*v+damping*u)/ringing;
    *x=target+decay*(u*cosine+b*sine);
    *v=decay*((*v)*cosine-(u*omega*omega+damping*(*v))/ringing*sine);
}
// Elastic resistance past a limit: it starts at slope one, so the finger and the
// drawer move together at first, and it never exceeds limit.
static CGFloat FMRubberBand(CGFloat over,CGFloat limit) {
    over=MAX(0,over);
    limit=MAX(limit,1e-6);
    return limit*(1-1/(1+over/limit));
}
// Progress as a finger drags it: beyond fully open the drawer stretches against
// rising resistance, up to about 6%, and springs back when released.
static CGFloat FMRubberProgress(CGFloat progress) {
    return progress<=1?progress:1+FMRubberBand(progress-1,.06);
}
// Pop-in of the drawer contents, after the wloc dock: the index-th of count
// elements (0 is the lowest one) starts this many seconds after the shell is
// wide enough. Neighbours are .07 s apart, squeezed so a long list still
// finishes its stagger within half a second.
static CGFloat FMPopDelay(NSUInteger index,NSUInteger count) {
    CGFloat step=MIN(.07,.5/MAX(1.,(CGFloat)count-1));
    return .04+(CGFloat)index*step;
}
// The pop-in setting: 0 one element after another (the dock's), 1 all together, 2 off.
static int FMPopMode(void) {
    CGFloat value=FloatPref(@"popAnimation",0);
    return !(value>=.5)?0:(value<1.5?1:2);
}
// Seconds before the index-th of count elements starts popping in under that
// setting, or a negative number when nothing should animate.
static CGFloat FMPopStart(int mode,NSUInteger index,NSUInteger count) {
    if(mode==2) return -1;
    return mode==1?FMPopDelay(0,1):FMPopDelay(index,count);
}
// A SwiftUI-style spring (response in seconds, damping fraction) as the
// mass-one stiffness and damping coefficient CASpringAnimation takes.
static CGFloat FMSpringStiffness(CGFloat response) {
    CGFloat omega=2*M_PI/MAX(response,1e-3);
    return omega*omega;
}
static CGFloat FMSpringDamping(CGFloat response,CGFloat fraction) {
    return 2*fraction*sqrt(FMSpringStiffness(response));
}
// Long-press scrub, after the wloc dock. The row under the finger, given every
// row's top and bottom in order; between rows the current one stays.
static NSInteger FMScrubIndexAtY(CGFloat y,const CGFloat *tops,const CGFloat *bottoms,NSUInteger count,NSInteger current) {
    for(NSUInteger index=0;index<count;index++)
        if(y>=tops[index] && y<bottoms[index]) return (NSInteger)index;
    return current;
}
// The lens follows the finger but stays between the first and last row centers.
static CGFloat FMScrubLensCenter(CGFloat y,CGFloat first,CGFloat last) {
    return Clamp(y,first,MAX(first,last));
}
// Dragging this far past either side of the drawer turns letting go into a cancel.
static BOOL FMScrubIsOutside(CGFloat x,CGFloat width) {
    return x<-44 || x>width+44;
}
// Sliding toward the top or bottom edge of a long list scrolls it that way, so every app
// can be reached without letting go: nothing until the finger is within 44 pt of the edge,
// then faster the nearer it gets, 560 pt/s at the edge itself and up to one and a half
// times that beyond it. Negative scrolls toward the top. It only counts when the finger
// has gone 12 pt toward that edge from where it first pressed (startY), so resting on a
// row that happens to sit near an edge never scrolls the list.
static CGFloat FMScrubScrollSpeed(CGFloat y,CGFloat top,CGFloat bottom,CGFloat startY) {
    const CGFloat zone=44,fastest=560,push=12;
    CGFloat above=startY-y>=push?Clamp((zone-(y-top))/zone,0,1.5):0;
    CGFloat below=y-startY>=push?Clamp((zone-(bottom-y))/zone,0,1.5):0;
    return fastest*(below-above);
}
// FMDrawerMotion:end
static BOOL FMClearGlassEnabled(void) {
    if(@available(iOS 26.0,*)) return BoolPref(@"clearGlass",NO);
    return NO;
}
static CGFloat FMGlassTintStrength(void) {
    return Clamp(.16+FloatPref(@"glassTint",0),0,.40);
}
// Clear keeps the full system glass visible. The accent supplies the selected
// theme's identity without placing an opaque sheet below the material.
static CGFloat FMClearGlassTintStrength(void) {
    return Clamp(.18+FloatPref(@"glassTint",0)*.65,.18,.29);
}
static CGFloat FMReadableRowAlpha(void) {
    if(UIAccessibilityIsReduceTransparencyEnabled()) return .94;
    if(UIAccessibilityDarkerSystemColorsEnabled()) return FMClearGlassEnabled()?.72:.90;
    return FMClearGlassEnabled()?(FMMenuDark()?.55:.52):.84;
}
// The line down the middle of the handle, at rest. Its colour is the view's own fill, so
// the red it turns while an update waits works the same on both styles.
static void FMApplyOrbLineRest(UIView *line) {
    BOOL glow=BoolPref(@"glowLine",YES);
    line.backgroundColor=FMClearGlassEnabled()?UIColor.systemBlueColor:FMAccent();
    line.layer.shadowColor=line.backgroundColor.CGColor;
    line.layer.shadowOffset=CGSizeZero;
    line.layer.shadowOpacity=glow?.5:0;
    line.layer.shadowRadius=glow?MAX(3,CGRectGetWidth(line.bounds)*.9):0;
}
// The author's line is a thin hairline. The other is the one from the reference render: a
// bar about a fifth of the handle wide and a third of its body tall, lit from the top and
// carrying a halo. bounds is the handle's frame, flares and all; the bar is measured
// against the straight body so a droplet's neck does not stretch it.
static UIView *FMOrbLine(CGRect bounds) {
    BOOL glow=BoolPref(@"glowLine",YES);
    CGFloat scale=FMOrbScale(),height=CGRectGetHeight(bounds);
    FMHandleMetrics handle=FMOrbHandleMetrics(FMOrbHandleIsCapsule());
    CGFloat body=2*handle.half;
    CGFloat w=glow?MAX(3*scale,handle.reach*.22):3*scale;
    CGFloat h=glow?MIN(body*.31,height*.42):MIN(18*scale,height*.30);
    UIView *line=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,h)];
    line.center=CGPointMake(CGRectGetWidth(bounds)*.5,height*.5);
    line.layer.cornerRadius=w*.5;
    line.layer.cornerCurve=kCACornerCurveCircular;
    line.layer.borderWidth=glow?.5:.4;
    line.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:glow?.55:.4].CGColor;
    line.userInteractionEnabled=NO;
    line.accessibilityIdentifier=@"fm.orb.update-indicator";
    if(glow) {
        // Lit from the top and deeper at the foot, over whatever colour the fill is. The
        // gradient has to mask itself: the line cannot clip its own sublayers without
        // losing the halo with them.
        CAGradientLayer *lit=[CAGradientLayer layer];
        lit.name=@"fm.orb.line.lit";
        lit.frame=line.bounds;
        lit.cornerRadius=w*.5;
        lit.cornerCurve=kCACornerCurveCircular;
        lit.masksToBounds=YES;
        lit.colors=@[(id)[UIColor.whiteColor colorWithAlphaComponent:.42].CGColor,
                     (id)UIColor.clearColor.CGColor,
                     (id)[UIColor.blackColor colorWithAlphaComponent:.20].CGColor];
        lit.locations=@[@0,@.45,@1];
        [line.layer addSublayer:lit];
    }
    FMApplyOrbLineRest(line);
    return line;
}
static void FMSwizzle(Class cls, SEL orig, SEL swiz) {
    Method origMethod = class_getInstanceMethod(cls, orig);
    Method swizMethod = class_getInstanceMethod(cls, swiz);
    if(!origMethod || !swizMethod) return;
    if(class_addMethod(cls, orig, method_getImplementation(swizMethod), method_getTypeEncoding(swizMethod))) {
        class_replaceMethod(cls, swiz, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, swizMethod);
    }
}

static void FMEnsureWindowOrientationLayout(void);

static UIInterfaceOrientationMask FMCurrentSupportedOrientations(UIViewController *vc) {
    if(!BoolPref(@"unlockOrientation", YES)) {
        return UIInterfaceOrientationMaskPortrait;
    }
    // 解锁向左横屏与竖屏（单向横屏，杜绝向右横屏白屏）
    return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscapeRight);
}

@interface UIViewController (FMOrientationUnlock)
- (UIInterfaceOrientationMask)fm_supportedInterfaceOrientations;
- (UIInterfaceOrientationMask)fm___supportedInterfaceOrientations;
- (UIInterfaceOrientationMask)fm__supportedInterfaceOrientations;
- (UIInterfaceOrientation)fm_preferredInterfaceOrientationForPresentation;
- (BOOL)fm_shouldAutorotate;
- (BOOL)fm_shouldAutorotateToInterfaceOrientation:(NSInteger)orientation;
- (void)fm_viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
@end

@implementation UIViewController (FMOrientationUnlock)
- (UIInterfaceOrientationMask)fm_supportedInterfaceOrientations {
    return FMCurrentSupportedOrientations(self);
}
- (UIInterfaceOrientationMask)fm___supportedInterfaceOrientations {
    return FMCurrentSupportedOrientations(self);
}
- (UIInterfaceOrientationMask)fm__supportedInterfaceOrientations {
    return FMCurrentSupportedOrientations(self);
}
- (UIInterfaceOrientation)fm_preferredInterfaceOrientationForPresentation {
    if(BoolPref(@"unlockOrientation", YES)) {
        UIDeviceOrientation dev = UIDevice.currentDevice.orientation;
        if(dev == UIDeviceOrientationLandscapeLeft) {
            return UIInterfaceOrientationLandscapeRight;
        }
        return UIInterfaceOrientationPortrait;
    }
    return [self fm_preferredInterfaceOrientationForPresentation];
}
- (BOOL)fm_shouldAutorotate {
    if(BoolPref(@"unlockOrientation", YES)) {
        return YES;
    }
    return [self fm_shouldAutorotate];
}
- (BOOL)fm_shouldAutorotateToInterfaceOrientation:(NSInteger)orientation {
    if(BoolPref(@"unlockOrientation", YES)) {
        return (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationLandscapeRight);
    }
    return [self fm_shouldAutorotateToInterfaceOrientation:orientation];
}
- (void)fm_viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [self fm_viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if(BoolPref(@"unlockOrientation", YES)) {
        if(coordinator) {
            [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
                FMEnsureWindowOrientationLayout();
            } completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
                FMEnsureWindowOrientationLayout();
            }];
        } else {
            FMEnsureWindowOrientationLayout();
        }
    }
}
@end

static UIInterfaceOrientationMask FMHooked_appDelegate_supportedInterfaceOrientations(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    if(BoolPref(@"unlockOrientation", YES)) {
        return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscapeRight);
    }
    SEL origSel = NSSelectorFromString(@"fm_orig_supportedInterfaceOrientationsForWindow:");
    if([self respondsToSelector:origSel]) {
        return ((UIInterfaceOrientationMask(*)(id, SEL, id, id))objc_msgSend)(self, origSel, application, window);
    }
    return UIInterfaceOrientationMaskPortrait;
}

static void FMHookAppDelegate(id<UIApplicationDelegate> delegate) {
    if(!delegate) return;
    Class cls = [delegate class];
    SEL sel = @selector(application:supportedInterfaceOrientationsForWindow:);
    SEL origSel = NSSelectorFromString(@"fm_orig_supportedInterfaceOrientationsForWindow:");
    if([cls instancesRespondToSelector:origSel]) return;
    Method origMethod = class_getInstanceMethod(cls, sel);
    if(origMethod) {
        class_addMethod(cls, origSel, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
        method_setImplementation(origMethod, (IMP)FMHooked_appDelegate_supportedInterfaceOrientations);
    } else {
        class_addMethod(cls, sel, (IMP)FMHooked_appDelegate_supportedInterfaceOrientations, "Q@:@@");
    }
}

@interface UIApplication (FMOrientationUnlock)
- (void)fm_setDelegate:(id<UIApplicationDelegate>)delegate;
- (UIInterfaceOrientationMask)fm_supportedInterfaceOrientationsForWindow:(UIWindow *)window;
@end

@implementation UIApplication (FMOrientationUnlock)
- (void)fm_setDelegate:(id<UIApplicationDelegate>)delegate {
    if(delegate) FMHookAppDelegate(delegate);
    [self fm_setDelegate:delegate];
}
- (UIInterfaceOrientationMask)fm_supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    if(BoolPref(@"unlockOrientation", YES)) {
        return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscapeRight);
    }
    return [self fm_supportedInterfaceOrientationsForWindow:window];
}
@end

static void FMEnsureWindowOrientationLayout(void) {
    if(!BoolPref(@"unlockOrientation", YES)) return;
    static BOOL isEnsuring = NO;
    if(isEnsuring) return;
    isEnsuring = YES;
    
    @try {
        UIScreen *screen = UIScreen.mainScreen;
        if(!screen) { isEnsuring = NO; return; }
        CGSize screenSize = screen.bounds.size;
        CGFloat portraitW = MIN(screenSize.width, screenSize.height);
        CGFloat portraitH = MAX(screenSize.width, screenSize.height);
        
        BOOL isLandscape = NO;
        if(@available(iOS 13.0, *)) {
            for(UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                if([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
                    UIInterfaceOrientation orient = ((UIWindowScene *)s).interfaceOrientation;
                    if(orient == UIInterfaceOrientationLandscapeRight) {
                        isLandscape = YES;
                        break;
                    }
                }
            }
        }
        if(!isLandscape) {
            UIDeviceOrientation dev = UIDevice.currentDevice.orientation;
            if(dev == UIDeviceOrientationLandscapeLeft) {
                isLandscape = YES;
            }
        }
        
        // 关键防护：竖屏状态下（包括应用启动）绝对不干涉 Window 布局，直接返回，杜绝死循环
        if(!isLandscape) {
            isEnsuring = NO;
            return;
        }
        
        CGRect targetBounds = CGRectMake(0, 0, portraitH, portraitW);
        CGFloat targetW = targetBounds.size.width;
        CGFloat targetH = targetBounds.size.height;
        
        NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
        if(@available(iOS 13.0, *)) {
            for(UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                if([s isKindOfClass:UIWindowScene.class]) {
                    [windows addObjectsFromArray:((UIWindowScene *)s).windows];
                }
            }
        }
        if(windows.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
        }
        
        for(UIWindow *w in windows) {
            if(w.windowLevel >= UIWindowLevelAlert) continue;
            if([w isKindOfClass:NSClassFromString(@"LCOrbitOverlayWindow")]) continue;
            if(fabs(w.bounds.size.width - targetW) > 1.0 || fabs(w.bounds.size.height - targetH) > 1.0) {
                w.frame = targetBounds;
                w.bounds = targetBounds;
                UIViewController *root = w.rootViewController;
                if(root && root.isViewLoaded) {
                    if([root isKindOfClass:NSClassFromString(@"LCOrbitOverlayController")]) continue;
                    if([root isKindOfClass:NSClassFromString(@"FMSettingsRootController")]) continue;
                    root.view.frame = targetBounds;
                    root.view.bounds = targetBounds;
                    [root.view setNeedsLayout];
                }
            }
        }
    } @catch(NSException *e) {
    }
    
    isEnsuring = NO;
}

@interface UIWindow (FMOrientationLayout)
- (void)fm_layoutSubviews;
@end

@implementation UIWindow (FMOrientationLayout)
- (void)fm_layoutSubviews {
    [self fm_layoutSubviews];
    if(!BoolPref(@"unlockOrientation", YES) || self.windowLevel >= UIWindowLevelAlert) return;
    if([self isKindOfClass:NSClassFromString(@"LCOrbitOverlayWindow")]) return;
    
    BOOL isLandscape = NO;
    if(@available(iOS 13.0, *)) {
        UIWindowScene *scene = self.windowScene;
        if(scene && scene.interfaceOrientation == UIInterfaceOrientationLandscapeRight) {
            isLandscape = YES;
        }
    }
    if(!isLandscape && UIDevice.currentDevice.orientation == UIDeviceOrientationLandscapeLeft) {
        isLandscape = YES;
    }
    if(!isLandscape) return; // 竖屏下完全不触发重排
    
    FMEnsureWindowOrientationLayout();
}
@end

static void FMInstallOrientationHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        
        FMSwizzle(UIViewController.class, @selector(supportedInterfaceOrientations), @selector(fm_supportedInterfaceOrientations));
        SEL dunder = NSSelectorFromString(@"__supportedInterfaceOrientations");
        if(class_getInstanceMethod(UIViewController.class, dunder)) {
            FMSwizzle(UIViewController.class, dunder, @selector(fm___supportedInterfaceOrientations));
        }
        SEL single = NSSelectorFromString(@"_supportedInterfaceOrientations");
        if(class_getInstanceMethod(UIViewController.class, single)) {
            FMSwizzle(UIViewController.class, single, @selector(fm__supportedInterfaceOrientations));
        }
        FMSwizzle(UIViewController.class, @selector(preferredInterfaceOrientationForPresentation), @selector(fm_preferredInterfaceOrientationForPresentation));
        FMSwizzle(UIViewController.class, @selector(shouldAutorotate), @selector(fm_shouldAutorotate));
        SEL shouldTo = NSSelectorFromString(@"shouldAutorotateToInterfaceOrientation:");
        if(class_getInstanceMethod(UIViewController.class, shouldTo)) {
            FMSwizzle(UIViewController.class, shouldTo, @selector(fm_shouldAutorotateToInterfaceOrientation:));
        }
        FMSwizzle(UIViewController.class, @selector(viewWillTransitionToSize:withTransitionCoordinator:), @selector(fm_viewWillTransitionToSize:withTransitionCoordinator:));
        
        FMSwizzle(UIWindow.class, @selector(layoutSubviews), @selector(fm_layoutSubviews));
        
        FMSwizzle(UIApplication.class, @selector(setDelegate:), @selector(fm_setDelegate:));
        FMSwizzle(UIApplication.class, @selector(supportedInterfaceOrientationsForWindow:), @selector(fm_supportedInterfaceOrientationsForWindow:));
        if(UIApplication.sharedApplication.delegate) {
            FMHookAppDelegate(UIApplication.sharedApplication.delegate);
        }
        
        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull note) {
            FMEnsureWindowOrientationLayout();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                FMEnsureWindowOrientationLayout();
            });
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull note) {
            FMEnsureWindowOrientationLayout();
        }];
    });
}

static void FMApplyNavigationTheme(UINavigationController *nav) {
    if(!nav) return;
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];
    [appearance configureWithDefaultBackground];
    appearance.backgroundColor=[FMThemeColor(FMColorSurface) colorWithAlphaComponent:.92];
    appearance.titleTextAttributes=@{NSForegroundColorAttributeName:FMThemeColor(FMColorText)};
    appearance.largeTitleTextAttributes=appearance.titleTextAttributes;
    nav.navigationBar.standardAppearance=appearance;
    nav.navigationBar.scrollEdgeAppearance=appearance;
    nav.navigationBar.compactAppearance=appearance;
    nav.navigationBar.tintColor=FMAccent();
}
static UIView *FMGlassContent(UIView *surface) {
    for(UIView *child in surface.subviews)
        if([child isKindOfClass:UIVisualEffectView.class])
            return ((UIVisualEffectView *)child).contentView;
    return surface;
}
static UIImage *FMGuestIcon(NSDictionary *app) {
    NSString *folder=app[@"folder"];
    if(![folder isKindOfClass:NSString.class] || !folder.length) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once,^{ cache=[NSCache new];cache.countLimit=90; });
    NSString *cacheKey=folder;
    id saved=[cache objectForKey:cacheKey];
    if(saved) return saved==NSNull.null?nil:saved;
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:@"Info.plist"]];
    if(![info isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *icons=info[@"CFBundleIcons"];
    if(![icons isKindOfClass:NSDictionary.class]) icons=info[@"CFBundleIcons~ipad"];
    NSDictionary *primary=[icons isKindOfClass:NSDictionary.class]?icons[@"CFBundlePrimaryIcon"]:nil;
    NSMutableArray<NSString*> *names=[NSMutableArray array];
    if([primary[@"CFBundleIconName"] isKindOfClass:NSString.class])
        [names addObject:primary[@"CFBundleIconName"]];
    NSArray *files=primary[@"CFBundleIconFiles"];
    if([files isKindOfClass:NSArray.class]) {
        for(id name in [files reverseObjectEnumerator])
            if([name isKindOfClass:NSString.class]) [names addObject:name];
    }
    for(id name in @[info[@"CFBundleIconFile"]?:@"", @"AppIcon60x60",@"AppIcon",@"Icon"])
        if([name isKindOfClass:NSString.class] && [name length]) [names addObject:name];
    // LC already exports the real rendered icon to these cache files.
    // This is the exact same source LCAppInfo.iconIsDarkIcon: displays in LC.
    UIImage *result=[UIImage imageWithContentsOfFile:
        [folder stringByAppendingPathComponent:@"LCAppIconLight.png"]];
    if(!result) result=[UIImage imageWithContentsOfFile:
        [folder stringByAppendingPathComponent:@"LCAppIconDark.png"]];
    NSBundle *bundle=[NSBundle bundleWithPath:folder];
    NSFileManager *fm=NSFileManager.defaultManager;
    for(NSString *name in result?@[]:names) {
        if(![name isKindOfClass:NSString.class] || !name.length) continue;
        @try {
            result=[UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
            if(result) break;
        } @catch(NSException *ex) {}
        NSString *base=name.stringByDeletingPathExtension;
        NSArray<NSString*> *variants=@[name,[base stringByAppendingString:@"@3x.png"],
            [base stringByAppendingString:@"@2x.png"],[base stringByAppendingString:@".png"],
            [base stringByAppendingString:@".jpg"]];
        for(NSString *variant in variants) {
            NSString *full=[folder stringByAppendingPathComponent:variant];
            if([fm fileExistsAtPath:full]) {
                result=[UIImage imageWithContentsOfFile:full];
                if(result) break;
            }
        }
        if(result) break;
    }
    if(result) [cache setObject:result forKey:cacheKey];
    return result;
}

@interface FMHitButton : UIButton
@property(nonatomic,assign) BOOL docksLeft;
@end
@implementation FMHitButton
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    // The bead is flush against a screen edge: symmetric insets waste half
    // the extra width offscreen. Keep >=44pt on the *inside* of that edge.
    CGFloat width=MAX(44.,CGRectGetWidth(self.bounds));
    CGFloat height=MAX(44.,CGRectGetHeight(self.bounds)+20.);
    CGFloat x=self.docksLeft?0:CGRectGetWidth(self.bounds)-width;
    CGRect hit=CGRectMake(x,(CGRectGetHeight(self.bounds)-height)*.5,width,height);
    return CGRectContainsPoint(hit,p);
}
@end

static UIControl *FMSettingsNavigationRow(NSString *name,NSString *subtitle,NSString *symbol,UIColor *badgeColor,id target,SEL action) {
    UIControl *row=[UIControl new];
    row.layer.cornerRadius=16;
    row.backgroundColor=FMThemeColor(FMColorSurface);

    UIView *badge=[UIView new];
    badge.translatesAutoresizingMaskIntoConstraints=NO;
    badge.layer.cornerRadius=8;
    badge.layer.masksToBounds=YES;
    badge.backgroundColor=badgeColor?:[UIColor colorWithRed:0 green:122/255.0 blue:255/255.0 alpha:1.0];
    [row addSubview:badge];

    UIImageView *icon=[[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:symbol] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    icon.translatesAutoresizingMaskIntoConstraints=NO;
    icon.tintColor=UIColor.whiteColor;
    icon.contentMode=UIViewContentModeScaleAspectFit;
    [badge addSubview:icon];

    UILabel *title=[UILabel new];
    title.translatesAutoresizingMaskIntoConstraints=NO;
    title.text=name;
    title.textColor=FMThemeColor(FMColorText);
    title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [row addSubview:title];
    UILabel *detail=[UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints=NO;
    detail.text=subtitle;
    detail.textColor=FMThemeColor(FMColorSecondary);
    detail.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    detail.numberOfLines=1;
    [row addSubview:detail];
    UIImageView *arrow=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    arrow.tintColor=FMThemeColor(FMColorSecondary);
    arrow.translatesAutoresizingMaskIntoConstraints=NO;
    [row addSubview:arrow];
    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [badge.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:32],
        [badge.heightAnchor constraintEqualToConstant:32],
        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:19],
        [icon.heightAnchor constraintEqualToConstant:19],
        [title.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:13],
        [title.topAnchor constraintEqualToAnchor:row.topAnchor constant:12],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:arrow.leadingAnchor constant:-8],
        [detail.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [detail.trailingAnchor constraintLessThanOrEqualToAnchor:arrow.leadingAnchor constant:-8],
        [arrow.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-17],
        [arrow.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [arrow.heightAnchor constraintEqualToConstant:15],
        [arrow.widthAnchor constraintEqualToConstant:10]
    ]];
    if(action) [row addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    else {arrow.hidden=YES;row.userInteractionEnabled=NO;}
    detail.tag=9235;
    row.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",name,subtitle];
    row.accessibilityTraits=action?UIAccessibilityTraitButton:UIAccessibilityTraitStaticText;
    return row;
}

@interface FMSettingsRootController : UIViewController
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,weak) UILabel *updateStatusLabel;
@property(nonatomic,assign) BOOL checkingUpdate;
@property(nonatomic,assign) BOOL requestedAutomaticUpdate;
@property(nonatomic,strong) NSMutableSet<NSString *> *automaticallyOfferedVersions;
@property(nonatomic,strong) id updateReleaseObserver;
@property(nonatomic,strong) id updateActivationObserver;
- (void)tryAutomaticUpdatePrompt;
- (void)rebuild;
@end
@interface FMSettingsSectionController : UIViewController
@property(nonatomic,copy) NSString *sectionKey;
@property(nonatomic,assign) NSUInteger githubGeneration;
@property(nonatomic,assign) BOOL checkingGitHub;
@property(nonatomic,copy) NSString *githubResult;
@property(nonatomic,strong) UIScrollView *contentScroll;
- (instancetype)initWithSection:(NSString *)key;
- (void)rebuild;
@end
// The sidebar page: the bead, the drawer and the pop-in, with a preview.
@interface FMDockSettingsController : UIViewController
- (void)rebuild;
@end

static id FMOrientationObserver=nil;
static id FMLayoutChangeObserver=nil;

// One element of the drawer popping in like the wloc dock icons: it starts
// small, transparent and pushed toward the wall, then springs into place
// (response .42 s, damping .62, about 8% overshoot). The model layer already
// holds the final state; the backwards fill keeps the first frame in place
// while the delay runs.
static void FMPopInLayer(CALayer *layer,CGFloat hidden,CFTimeInterval delay) {
    CGFloat stiffness=FMSpringStiffness(.42),damping=FMSpringDamping(.42,.62);
    NSArray<NSArray *> *specs=@[@[@"opacity",@0,@1],@[@"transform.scale",@.6,@1],
                                @[@"transform.translation.x",@(hidden),@0]];
    NSMutableArray<CAAnimation *> *parts=[NSMutableArray array];
    CFTimeInterval length=0;
    for(NSArray *spec in specs) {
        CASpringAnimation *spring=[CASpringAnimation animationWithKeyPath:spec[0]];
        spring.mass=1;spring.stiffness=stiffness;spring.damping=damping;spring.initialVelocity=0;
        spring.fromValue=spec[1];spring.toValue=spec[2];
        spring.duration=spring.settlingDuration;
        length=MAX(length,spring.duration);
        [parts addObject:spring];
    }
    CAAnimationGroup *group=[CAAnimationGroup animation];
    group.animations=parts;
    group.duration=length;
    group.beginTime=[layer convertTime:CACurrentMediaTime() fromLayer:nil]+delay;
    group.fillMode=kCAFillModeBackwards;
    [layer addAnimation:group forKey:@"fm.pop.in"];
}
// A divider only fades in, after everything else has popped.
static void FMPopInDivider(CALayer *layer,CFTimeInterval delay) {
    CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue=@0;fade.toValue=@1;
    fade.duration=.4;
    fade.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    fade.beginTime=[layer convertTime:CACurrentMediaTime() fromLayer:nil]+delay;
    fade.fillMode=kCAFillModeBackwards;
    [layer addAnimation:fade forKey:@"fm.pop.in"];
}
// Pulling back: quick and without a bounce, so nothing hangs outside a shell
// that has already shrunk away. The layer stays hidden until the drawer goes.
static void FMPopOutLayer(CALayer *layer,CGFloat hidden,BOOL fadeOnly) {
    CGFloat shown=layer.presentationLayer?layer.presentationLayer.opacity:layer.opacity;
    [layer removeAnimationForKey:@"fm.pop.in"];
    NSArray<NSArray *> *specs=fadeOnly?@[@[@"opacity",@(shown),@0]]:
        @[@[@"opacity",@(shown),@0],@[@"transform.scale",@1,@.6],@[@"transform.translation.x",@0,@(hidden)]];
    NSMutableArray<CAAnimation *> *parts=[NSMutableArray array];
    for(NSArray *spec in specs) {
        CABasicAnimation *move=[CABasicAnimation animationWithKeyPath:spec[0]];
        move.fromValue=spec[1];move.toValue=spec[2];
        move.duration=.14;
        move.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        [parts addObject:move];
    }
    CAAnimationGroup *group=[CAAnimationGroup animation];
    group.animations=parts;
    group.duration=.14;
    group.fillMode=kCAFillModeForwards;
    group.removedOnCompletion=NO;
    [layer addAnimation:group forKey:@"fm.pop.out"];
}
// Plays the drawer contents in or out. Each item is @{view,row,gap}: lowest row first and,
// within a row, the one nearest the wall first, one after another or all at once as the
// pop-in setting says. Dividers only fade, after the rest. With the setting off nothing
// animates. The real drawer and the settings preview both go through here.
static void FMPopItems(NSArray<NSDictionary *> *items,NSArray<UIView *> *dividers,BOOL left,BOOL reveal) {
    NSArray<NSDictionary *> *ordered=[items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSComparisonResult lowerFirst=[b[@"row"] compare:a[@"row"]];
        return lowerFirst!=NSOrderedSame?lowerFirst:[a[@"gap"] compare:b[@"gap"]];
    }];
    CGFloat toWall=left?-1:1;
    NSUInteger count=ordered.count;
    int mode=FMPopMode();
    for(NSUInteger index=0;index<count;index++) {
        UIView *view=ordered[index][@"view"];
        CGFloat hidden=toWall*(MIN(CGRectGetHeight(view.bounds),56)+16);
        if(reveal) {
            [view.layer removeAnimationForKey:@"fm.pop.out"];
            CGFloat start=FMPopStart(mode,index,count);
            if(start>=0) FMPopInLayer(view.layer,hidden,start);
        } else if(mode!=2) FMPopOutLayer(view.layer,hidden,NO);
    }
    for(UIView *divider in dividers) {
        if(reveal) {
            [divider.layer removeAnimationForKey:@"fm.pop.out"];
            CGFloat start=FMPopStart(mode,count,count+1);
            if(start>=0) FMPopInDivider(divider.layer,start);
        } else if(mode!=2) FMPopOutLayer(divider.layer,0,YES);
    }
}

@interface FMManager : NSObject <UIScrollViewDelegate,UIGestureRecognizerDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *overlayView;
@property(nonatomic,strong) LCOrbitContext *orbitContext;
@property(nonatomic,strong) UIButton *orb;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,assign) CGFloat panelContentScale;
@property(nonatomic,assign) CGFloat panelFooterHeight;
@property(nonatomic,assign) BOOL panelShowsHeader;
@property(nonatomic,weak) UIColorWell *lightColorWell;
@property(nonatomic,weak) UIColorWell *darkColorWell;
@property(nonatomic,strong) UIView *dismissLayer;
@property(nonatomic,strong) NSMutableArray<UIView*> *manageRows;
@property(nonatomic,weak) UIScrollView *settingsScroll;
@property(nonatomic,weak) UIScrollView *appsScroll;
@property(nonatomic,weak) UIView *appsHeaderGlass;
@property(nonatomic,copy) NSArray<UIView *> *appsHeaderTiles;
@property(nonatomic,assign) BOOL appsScrollRestorePending;
@property(nonatomic,assign) BOOL appsRefreshScheduled;
@property(nonatomic,assign) NSUInteger morphGeneration;
@property(nonatomic,assign) NSUInteger launchGeneration;
@property(nonatomic,assign) BOOL launchPending;
@property(nonatomic,assign) BOOL launchMultitaskMode;
@property(nonatomic,assign) BOOL launchSystemMenuMode;
@property(nonatomic,strong) UIView *settingsScreen;
@property(nonatomic,strong) UIWindow *settingsWindow;
@property(nonatomic,strong) UIView *orbPreviewHost;
@property(nonatomic,weak) UIView *dimensionsPreview;
@property(nonatomic,strong) UINavigationController *settingsNavigation;
@property(nonatomic,weak) UIWindow *previousKeyWindow;
@property(nonatomic,assign) UIUserInterfaceStyle lastSystemStyle;
@property(nonatomic,assign) UIUserInterfaceStyle lastMenuStyle;
@property(nonatomic,weak) UIWindowScene *appearanceScene;
@property(nonatomic,strong) id appearanceRegistration;
@property(nonatomic,assign) BOOL appearanceRefreshPending;
@property(nonatomic,assign) BOOL appearancePollScheduled;
@property(nonatomic,assign) NSUInteger appearancePollGeneration;
@property(nonatomic,assign) CGFloat settingsScrollOffset;
@property(nonatomic,assign) CGFloat appsScrollOffset;
@property(nonatomic,assign) CGFloat orbY;
@property(nonatomic,assign) BOOL left;
@property(nonatomic,assign) BOOL isOpen;
@property(nonatomic,strong) NSTimer *orbFadeTimer;
@property(nonatomic,assign) BOOL orbFaded;
@property(nonatomic,assign) CGFloat orbNormalAlpha;
@property(nonatomic,strong) id screenTouchObserver;
@property(nonatomic,weak) UIView *orbUpdateLine;
@property(nonatomic,assign) BOOL orbUpdateAvailable;
@property(nonatomic,assign) BOOL orbUpdateChecking;
@property(nonatomic,strong) NSTimer *orbUpdateTimer;
@property(nonatomic,copy) NSString *page;
@property(nonatomic,strong) NSArray<NSDictionary*> *apps;
+ (instancetype)shared;
- (void)installIfPossible;
- (void)checkOrbUpdateIfNeeded;
- (void)applyOrbUpdateIndicator;
- (void)draw;
- (void)refreshSystemAppearance;
- (void)scheduleAppearanceCheck;
- (void)cancelAppearanceCheck;
- (void)detachFromScene;
- (void)observeAppearanceInScene:(UIWindowScene *)scene;
- (void)queueAppearanceRefresh;
- (void)refreshUI;
- (void)refreshAppsContent;
- (void)requestAppsRefresh;
- (void)persistAppsScroll;
- (void)loadAppsScroll;
- (void)rememberCurrentApp;
- (NSArray<NSDictionary *> *)orderedAppsForMenu;
- (void)closeSettings;
- (void)populateSettingsCategory:(NSString *)category stack:(UIStackView *)stack;
- (void)updateSettingsContent;
- (void)appendResetStyleRow:(UIStackView *)stack;
- (void)launchApp:(NSDictionary *)app;
- (void)invalidatePendingLaunch;
- (void)showMessage:(NSString *)title details:(NSString *)detail;
- (void)showMultitaskMenuExpanded:(BOOL)expanded;
- (void)openSettingsInScene:(UIWindowScene *)scene;
@end
@implementation FMManager {
    CGPoint _panStartPoint;
    CGPoint _panOriginalCenter;
    BOOL _panOriginalLeft;
    CGFloat _panMaxInwardDist;
    CGFloat _panMaxVerticalDist;
    BOOL _panIsRepositioning;
    BOOL _panIsInwardPull;
    BOOL _isPanning;
    // Bead <-> drawer morph. Progress 0 is the docked bead, 1 the open drawer;
    // a finger or a spring moves it, and every transition goes through it.
    FMNotchParams _morphBead,_morphDroplet,_morphDrawer;
    CGPoint _morphRestCenter,_morphShift;
    CGFloat _morphProgress,_morphVelocity,_morphTarget,_morphTravel,_morphCommit;
    CGFloat _morphBeadAlpha,_morphShadow,_morphElapsed,_panelDragStart;
    CGFloat _morphScale,_morphOmega,_morphZeta;
    CFTimeInterval _morphTick;
    CADisplayLink *_morphLink;
    BOOL _morphCompact,_morphActive,_morphDragging,_morphOpening,_morphFromBead;
    BOOL _morphCommitHaptic,_drawDeferred,_panUsesMorph,_panelDragLive;
    BOOL _popRevealed,_popStarted;
    // Long-press scrub: a glass lens over the app list.
    UIView *_scrubLens,*_scrubLabel;
    NSArray<UIView *> *_scrubRows;
    NSArray<UIControl *> *_scrubControls;
    NSArray<NSValue *> *_scrubFrames;
    CGRect _scrubViewport;
    CGFloat _scrubFirstMid,_scrubLastMid,_scrubHalf,_scrubStartY;
    CGPoint _scrubPoint;
    CADisplayLink *_scrubLink;
    CFTimeInterval _scrubScrollTick;
    NSInteger _scrubIndex;
    BOOL _scrubActive,_scrubCancelling;
    UISelectionFeedbackGenerator *_scrubTick;
}
+ (instancetype)shared {
    static FMManager *m;
    static dispatch_once_t once;
    dispatch_once(&once,^{m=[FMManager new];});
    return m;
}
- (UIWindowScene *)foregroundScene {
    if(@available(iOS 13.0,*)) {
        for(UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if([s isKindOfClass:UIWindowScene.class] &&
               s.activationState==UISceneActivationStateForegroundActive)
                return (UIWindowScene*)s;
        }
    }
    return nil;
}
- (void)installIfPossible {
    UIWindowScene *scene=[self foregroundScene];
    if(!scene || (!GuestInfo() && !FMHostUI())) return;
    // During scene transitions UIKit can briefly report invalid geometry.
    // Never feed NaN, infinite, or zero dimensions into a CALayer.
    CGRect sceneBounds=scene.coordinateSpace.bounds;
    if(!isfinite(sceneBounds.origin.x) || !isfinite(sceneBounds.origin.y) ||
       !isfinite(sceneBounds.size.width) || !isfinite(sceneBounds.size.height) ||
       sceneBounds.size.width<=0 || sceneBounds.size.height<=0) return;
    SEL sideSel=NSSelectorFromString(@"isSideStore");
    SEL procSel=NSSelectorFromString(@"isLiveProcess");
    if(![NSUserDefaults respondsToSelector:sideSel] || ![NSUserDefaults respondsToSelector:procSel]) return;
    if(((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,sideSel) ||
       ((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,procSel)) return;
    if(self.window && self.window.windowScene != scene) [self detachFromScene];
    FMStyleScene=scene;
    [self observeAppearanceInScene:scene];
    if(self.window) {
        CGRect nextFrame=scene.coordinateSpace.bounds;
        if(!CGRectEqualToRect(self.window.frame,nextFrame)) {
            [self.orbitContext.overlays updateFrame];
            if(self.settingsWindow) {
                self.settingsWindow.frame=nextFrame;
                [self updateSettingsContent];
            } else [self draw];
        }
        [self refreshSystemAppearance];
        [self scheduleAppearanceCheck];
        [self checkOrbUpdateIfNeeded];
        return;
    }
    self.overlayView=[self.orbitContext.overlays mountModule:@"FloatingMenu" inScene:scene];
    if(!self.overlayView) return;
    self.window=self.orbitContext.overlays.window;
    self.lastSystemStyle=FMSystemAppearance();
    self.lastMenuStyle=FMMenuAppearance();
    // Never style Core's shared UIWindow: each module owns only its own layer.
    self.overlayView.overrideUserInterfaceStyle=FMMenuOverride();
    self.orbY=Clamp(FloatPref(@"orbY",.50),.10,.90);
    self.left=BoolPref(@"onLeft",NO);
    self.page=@"apps";
    self.apps=InstalledApps();
    [self rememberCurrentApp];
    if(!self.screenTouchObserver) {
        __weak typeof(self) weakSelf=self;
        self.screenTouchObserver=[NSNotificationCenter.defaultCenter addObserverForName:@"LCOrbitScreenTouchedNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull note) {
            [weakSelf wakeOrb];
        }];
    }
    if(!FMOrientationObserver) {
        __weak typeof(self) weakSelf=self;
        FMOrientationObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull note) {
            [weakSelf handleOrientationOrLayoutChange];
        }];
    }
    if(!FMLayoutChangeObserver) {
        __weak typeof(self) weakSelf=self;
        FMLayoutChangeObserver=[NSNotificationCenter.defaultCenter addObserverForName:@"LCOrbitOverlayLayoutDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull note) {
            [weakSelf handleOrientationOrLayoutChange];
        }];
    }
    FMLog(@"overlay-ready",[NSString stringWithFormat:@"available=%lu context=%@",
        (unsigned long)self.apps.count,FMHostUI()?@"lc-host":@"guest"]);
    [self draw];
    [self scheduleAppearanceCheck];
    if(!self.orbUpdateTimer) {
        __weak typeof(self) weakSelf=self;
        self.orbUpdateTimer=[NSTimer scheduledTimerWithTimeInterval:60*60 repeats:YES block:^(NSTimer *timer) {
            [weakSelf checkOrbUpdateIfNeeded];
        }];
    }
    [self checkOrbUpdateIfNeeded];
}
- (void)handleOrientationOrLayoutChange {
    if(_isPanning) return;
    [self refreshLayoutForOrientation];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.12*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(self->_isPanning) return;
        [self refreshLayoutForOrientation];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(self->_isPanning) return;
        [self refreshLayoutForOrientation];
    });
}
- (void)refreshLayoutForOrientation {
    if(_isPanning || !self.window) return;
    UIWindowScene *scene=self.window.windowScene?:[self foregroundScene];
    if(!scene) return;
    CGRect sceneBounds=scene.coordinateSpace.bounds;
    if(!isfinite(sceneBounds.size.width) || !isfinite(sceneBounds.size.height) ||
       sceneBounds.size.width<=0 || sceneBounds.size.height<=0) return;
    [self.orbitContext.overlays updateFrame];
    if(self.settingsWindow) {
        self.settingsWindow.frame=sceneBounds;
        [self updateSettingsContent];
    } else {
        [self draw];
    }
}
- (CGFloat)orbWidth { return FMHandleFrameSize(FMOrbHandleMetrics(FMOrbHandleIsCapsule())).width; }
- (CGFloat)orbHeight { return FMHandleFrameSize(FMOrbHandleMetrics(FMOrbHandleIsCapsule())).height; }
- (CGRect)orbFrame {
    CGRect b=self.window.bounds;
    CGFloat w=self.orbWidth,h=self.orbHeight;
    CGFloat x=self.left?0:b.size.width-w;
    CGFloat top=MAX(25,self.window.safeAreaInsets.top+6);
    CGFloat bottom=MAX(24,self.window.safeAreaInsets.bottom+8);
    CGFloat latest=b.size.height-h-bottom;
    CGFloat y=latest<top?MAX(0,(b.size.height-h)*.5):Clamp(b.size.height*self.orbY-h*.5,top,latest);
    return CGRectMake(x,y,w,h);
}
// One native glass shell owns the foreground via contentView. Rows and tools
// use ordinary fills, avoiding nested refraction behind small text and symbols.
- (UIView *)glass:(CGRect)frame radius:(CGFloat)radius strong:(BOOL)strong {
    UIView *surface=[[UIView alloc] initWithFrame:frame];
    // A Guest can force Light globally. Pin the glass subtree's UIKit traits
    // to our selected theme instead of trusting the parent window or scene.
    surface.overrideUserInterfaceStyle=FMMenuOverride();
    surface.backgroundColor=UIColor.clearColor;
    surface.layer.cornerRadius=radius;
    surface.clipsToBounds=YES;
    UIVisualEffect *effect=nil;
    BOOL nativeGlass=NO;
    BOOL clear=FMClearGlassEnabled();
    if(@available(iOS 26.0,*)) {
        // Resolve native UIKit glass at runtime: macOS 15 GitHub runners ship
        // an older iOS SDK without UIGlassEffect declarations. This retains
        // native glass on iOS 26+ without requiring its compile-time headers.
        Class glassClass=NSClassFromString(@"UIGlassEffect");
        SEL factory=NSSelectorFromString(@"effectWithStyle:");
        if(glassClass && [glassClass respondsToSelector:factory]) {
            // UIGlassEffectStyleRegular=0, UIGlassEffectStyleClear=1.
            NSInteger style=clear?1:0;
            id glassEffect=((id(*)(id,SEL,NSInteger))objc_msgSend)(glassClass,factory,style);
            if([glassEffect isKindOfClass:UIVisualEffect.class]) {
                SEL setInteractive=NSSelectorFromString(@"setInteractive:");
                if([glassEffect respondsToSelector:setInteractive])
                    ((void(*)(id,SEL,BOOL))objc_msgSend)(glassEffect,setInteractive,!strong);
                SEL setTint=NSSelectorFromString(@"setTintColor:");
                if([glassEffect respondsToSelector:setTint]) {
                    UIColor *tint=[(clear?FMAccent():FMThemeColor(FMColorGlass))
                        colorWithAlphaComponent:clear?FMClearGlassTintStrength():FMGlassTintStrength()];
                    ((void(*)(id,SEL,id))objc_msgSend)(glassEffect,setTint,tint);
                }
                effect=(UIVisualEffect *)glassEffect;
                nativeGlass=YES;
            }
        }
    }
    if(!effect) {
        BOOL dark=FMMenuDark();
        UIBlurEffectStyle style=strong?
            (dark?UIBlurEffectStyleSystemMaterialDark:UIBlurEffectStyleSystemMaterialLight):
            (dark?UIBlurEffectStyleSystemThinMaterialDark:UIBlurEffectStyleSystemThinMaterialLight);
        effect=[UIBlurEffect effectWithStyle:style];
    }
    if(nativeGlass && clear && UIAccessibilityIsReduceTransparencyEnabled()) {
        // Accessibility is the only case for a whole-surface backing.
        // The normal Clear path must not sample a mostly opaque flat panel.
        UIView *backing=[[UIView alloc] initWithFrame:surface.bounds];
        backing.backgroundColor=[FMThemeColor(FMColorSurface) colorWithAlphaComponent:.94];
        backing.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        backing.userInteractionEnabled=NO;
        [surface addSubview:backing];
    }
    UIVisualEffectView *material=[[UIVisualEffectView alloc] initWithEffect:effect];
    material.overrideUserInterfaceStyle=FMMenuOverride();
    material.frame=surface.bounds;
    material.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    material.userInteractionEnabled=YES;
    [surface addSubview:material];
    if(nativeGlass && !strong && FMMenuDark()) {
        // iOS 26+ glass adapts optically to the background even when the
        // effect view has a Dark trait. In a forced-Light Guest its thin bead
        // consequently becomes nearly white while the expanded menu is dark.
        // Tint only the collapsed bead's glass content, keeping real system
        // refraction underneath and preserving both expanded and Light modes.
        UIView *nightBacking=[[UIView alloc] initWithFrame:material.contentView.bounds];
        nightBacking.tag=9217; // Runtime contrast regression identifier.
        nightBacking.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        nightBacking.backgroundColor=[FMThemeColor(FMColorBackground) colorWithAlphaComponent:.68];
        nightBacking.userInteractionEnabled=NO;
        [material.contentView addSubview:nightBacking];
    }
    // LC's colorful app cards and translucent TabView show through the
    // native drawer. Give only the host drawer a light readability backing.
    if(strong && FMHostUI()) {
        UIView *backing=[[UIView alloc] initWithFrame:material.contentView.bounds];
        backing.tag=9231; // Material backing, not content: the drawer morph leaves it alone.
        backing.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        backing.backgroundColor=[FMThemeColor(FMColorSurface) colorWithAlphaComponent:
            clear?.42:.26];
        backing.userInteractionEnabled=NO;
        [material.contentView addSubview:backing];
    }
    if(!nativeGlass) {
        // Only older iOS receives the limited compatibility approximation.
        UIView *scrim=[[UIView alloc] initWithFrame:surface.bounds];
        scrim.tag=9231;
        scrim.backgroundColor=[FMThemeColor(FMColorGlass) colorWithAlphaComponent:
            strong?(FMMenuDark()?.25:.34):.10];
        scrim.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        scrim.userInteractionEnabled=NO;
        [material.contentView addSubview:scrim];
        surface.layer.borderWidth=.6;
        surface.layer.borderColor=[FMThemeColor(FMColorBorder) colorWithAlphaComponent:.32].CGColor;
    }
    return surface;
}
- (void)captureAppsScroll {
    if(!self.appsScroll || self.appsScrollRestorePending) return;
    CGFloat y=self.appsScroll.contentOffset.y;
    if(isfinite(y)) self.appsScrollOffset=MAX(0,y);
}
- (void)persistAppsScroll {
    if(BoolPref(@"recentAppsFirst",NO)) return; // Opening resets to top; do not overwrite saved OFF-mode position.
    [self captureAppsScroll];
    CGFloat y=self.appsScrollOffset;
    if(!isfinite(y)) return;
    // The LCOrbit JSON settings live under LC_HOME_PATH and can be read by the
    // next Guest process. Persist only at gesture/transition boundaries.
    id old=[HostDefaults() objectForKey:Pref(@"appsScrollOffset")];
    if(![old isKindOfClass:NSNumber.class] || fabs([old doubleValue]-y)>.5) {
        SetPref(@"appsScrollOffset",@(y));
        FMLog(@"apps-scroll-saved",[NSString stringWithFormat:@"offset=%.1f",y]);
    }
}
- (void)loadAppsScroll {
    if(BoolPref(@"recentAppsFirst",NO)) {
        self.appsScrollOffset=0;
        FMLog(@"apps-scroll-reset",@"recent-apps-first");
        return;
    }
    id saved=[HostDefaults() objectForKey:Pref(@"appsScrollOffset")];
    if([saved isKindOfClass:NSNumber.class] && isfinite([saved doubleValue])) {
        self.appsScrollOffset=MAX(0,[saved doubleValue]);
        FMLog(@"apps-scroll-loaded",[NSString stringWithFormat:@"offset=%.1f",self.appsScrollOffset]);
    }
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if(scrollView!=self.appsScroll || self.appsScrollRestorePending) return;
    CGFloat y=scrollView.contentOffset.y;
    if(isfinite(y)) self.appsScrollOffset=MAX(0,y);
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if(scrollView==self.appsScroll && !decelerate) [self persistAppsScroll];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if(scrollView==self.appsScroll) [self persistAppsScroll];
}
- (void)removePanel {
    // Closing a running task refreshes this panel. Both the compact icon list
    // and the normal app rows must retain their shared scroll position.
    [self captureAppsScroll];
    // Whatever was animating this panel ends with it.
    [self endDrawerMorph];
    [self endScrubAnimated:NO];
    _drawDeferred=NO;
    self.morphGeneration++;
    self.appsHeaderGlass=nil;
    self.appsHeaderTiles=nil;
    self.appsScroll=nil;
    self.appsScrollRestorePending=NO;
    [self.panel removeFromSuperview]; self.panel=nil;
    [self.dismissLayer removeFromSuperview]; self.dismissLayer=nil;
}
- (void)applyOrbUpdateIndicator {
    UIView *line=self.orbUpdateLine;
    if(!line) return;
    [line.layer removeAnimationForKey:@"fm.update.red-breath"];
    if(!self.orbUpdateAvailable) {
        FMApplyOrbLineRest(line);
        line.alpha=1;
        if(!self.isOpen && BoolPref(@"idleFade",YES)) [self scheduleOrbFade];
        return;
    }
    [self cancelOrbFade];
    self.orbFaded=NO;
    if(self.orb && !self.isOpen) self.orb.alpha=1;
    line.backgroundColor=[UIColor colorWithRed:1 green:.17 blue:.23 alpha:1];
    line.layer.shadowColor=[UIColor colorWithRed:1 green:.09 blue:.16 alpha:1].CGColor;
    line.layer.shadowOpacity=.85;
    line.layer.shadowRadius=5;
    line.layer.shadowOffset=CGSizeZero;
    line.alpha=1;
    if(!UIAccessibilityIsReduceMotionEnabled()) {
        CABasicAnimation *pulse=[CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue=@.38;
        pulse.toValue=@1;
        pulse.duration=1.15;
        pulse.autoreverses=YES;
        pulse.repeatCount=HUGE_VALF;
        pulse.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [line.layer addAnimation:pulse forKey:@"fm.update.red-breath"];
    }
}
- (void)checkOrbUpdateIfNeeded {
    if(self.orbUpdateChecking || !self.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)
        return;
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSString *saved=[defaults stringForKey:FMUpdateCacheVersion];
    BOOL wasAvailable=FMVersionCompare(saved?:@"",FM_MENU_VERSION)==NSOrderedDescending;
    if(self.orbUpdateAvailable!=wasAvailable) {
        self.orbUpdateAvailable=wasAvailable;
        [self applyOrbUpdateIndicator];
    }
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSTimeInterval last=[defaults doubleForKey:FMUpdateCacheTime];
    NSTimeInterval success=[defaults doubleForKey:FMUpdateCacheSuccess];
    if(last>0 && now>=last && now-last<(success>=last?FMUpdateRefreshInterval:FMUpdateRetryInterval)) return;
    self.orbUpdateChecking=YES;
    [defaults setDouble:now forKey:FMUpdateCacheTime];
    __weak typeof(self) weakSelf=self;
    FMFetchUpdateRelease(12,^(NSDictionary *release,NSError *error,NSUInteger sequence) {
        dispatch_async(dispatch_get_main_queue(), ^{
            FMManager *owner=weakSelf;
            owner.orbUpdateChecking=NO;
            if(!release) return; // failures never clear a known update
            NSDictionary *accepted=FMCacheUpdateRelease(release,sequence);
            if(!owner) return;
            BOOL available=[LCOrbitUpdateRelease isNewerRelease:accepted thanVersion:FM_MENU_VERSION];
            if(owner.orbUpdateAvailable!=available) {
                owner.orbUpdateAvailable=available;
                [owner applyOrbUpdateIndicator];
            }
        });
    });
}

- (void)scheduleOrbFade {
    [self.orbFadeTimer invalidate];
    if(!BoolPref(@"idleFade",YES) || self.orbUpdateAvailable) return;
    if(self.isOpen || !self.orb) return;
    __weak typeof(self) weakSelf=self;
    self.orbFadeTimer=[NSTimer scheduledTimerWithTimeInterval:FMOrbStyleValue(@"fadeDelay") repeats:NO block:^(NSTimer * _Nonnull timer) {
        [weakSelf fadeOrb];
    }];
}
- (void)cancelOrbFade {
    [self.orbFadeTimer invalidate];
    self.orbFadeTimer=nil;
}
- (void)fadeOrb {
    if(_morphActive || self.isOpen || !self.orb || self.orbFaded || self.orbUpdateAvailable) return;
    self.orbFaded=YES;
    [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionAllowUserInteraction animations:^{
        self.orb.alpha=FMOrbStyleValue(@"fadedOpacity");
    } completion:nil];
}
- (void)wakeOrb {
    if(!self.orb || self.isOpen || _morphActive) return;
    [self cancelOrbFade];
    if(self.orbFaded || self.orb.alpha < (self.orbNormalAlpha?:0.72) - 0.05) {
        self.orbFaded=NO;
        [UIView animateWithDuration:0.20 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionAllowUserInteraction animations:^{
            self.orb.alpha=self.orbNormalAlpha?:0.72;
        } completion:nil];
    }
    if(BoolPref(@"idleFade",YES)) {
        [self scheduleOrbFade];
    }
}

- (void)drawOrb {
    if(_isPanning || _morphActive) return;
    [self cancelOrbFade];
    for(UIView *sub in [self.overlayView.subviews copy]) {
        if([sub isKindOfClass:[FMHitButton class]] || sub.tag==9200 || sub==self.orb) {
            [sub removeFromSuperview];
        }
    }
    self.orb=nil;
    CGRect f=[self orbFrame];
    FMHitButton *button=[FMHitButton buttonWithType:UIButtonTypeCustom];
    button.tag=9200;
    button.docksLeft=self.left;
    button.frame=f;
    button.layer.shadowColor=FMAccent().CGColor;
    button.layer.shadowOpacity=.24;button.layer.shadowRadius=6;
    button.layer.shadowOffset=CGSizeMake(0,1);
    FMAddOrbBackdrop(button,self.left);
    UIView *bead=[self glass:button.bounds radius:f.size.width*.5 strong:NO];
    FMApplySideNotch(bead,button.layer,self.left,YES,YES);
    FMAddOrbCapsule(bead,self.left);
    for(CALayer *layer in bead.layer.sublayers)
        if([layer isKindOfClass:CAShapeLayer.class]) layer.name=@"fm.orb.rim";
    bead.userInteractionEnabled=NO;
    bead.tag=9202;
    [button addSubview:bead];
    UIView *line=FMOrbLine(button.bounds);
    [bead addSubview:line];
    self.orbUpdateLine=line;
    CGFloat alpha=BoolPref([@"override." stringByAppendingString:GuestID()],NO)?
        FloatPref([@"appAlpha." stringByAppendingString:GuestID()],FloatPref(@"idleAlpha",.72)):
        FloatPref(@"idleAlpha",.72);
    self.orbNormalAlpha=Clamp(alpha,.25,1);
    self.orbFaded=NO;
    button.alpha=self.isOpen?0:(self.orbUpdateAvailable?1:self.orbNormalAlpha);
    button.userInteractionEnabled=!self.isOpen;
    button.accessibilityElementsHidden=self.isOpen;
    button.accessibilityLabel=@"LC 悬浮菜单";
    button.accessibilityHint=@"轻触展开，拖动移动，长按进入菜单设置";
    button.accessibilityTraits=UIAccessibilityTraitButton;
    [button addTarget:self action:@selector(wakeOrb) forControlEvents:UIControlEventTouchDown];
    if(BoolPref([@"override." stringByAppendingString:GuestID()],NO) &&
       BoolPref([@"doubleTap." stringByAppendingString:GuestID()],NO)) {
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        tap.numberOfTapsRequired=2;[button addGestureRecognizer:tap];
    } else [button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
    hold.minimumPressDuration=.55;
    [button addGestureRecognizer:hold];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    pan.cancelsTouchesInView = YES;
    [button addGestureRecognizer:pan];
    [self.overlayView addSubview:button];
    self.orb=button;
    [self applyOrbUpdateIndicator];
}
- (void)hold:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan) return;
    if(BoolPref(@"haptic",YES)) [[[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    FMLog(@"settings-gesture",@"orb-long-press");
    [self openSettings];
}
- (void)holdPanel:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan) return;
    if(BoolPref(@"haptic",YES)) [[[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    FMLog(@"settings-gesture",@"panel-long-press");
    [self openSettings];
}
- (void)draw {
    if(!self.window) return;
    // A scene detached mid-flight leaves a morph with no drawer to animate.
    if(_morphActive && !self.panel) [self endDrawerMorph];
    // A drag or settle owns the bead and the drawer; redraw when it is done.
    if(_morphActive) { _drawDeferred=YES; return; }
    if(_isPanning) return;
    if(self.settingsWindow) { [self updateSettingsContent]; return; }
    BOOL visible=[LCOrbitMultitask shouldShowFloatingMenu];
    [self.orbitContext.overlays setModule:@"FloatingMenu" visible:visible];
    if(!visible) {
        self.isOpen=NO;
        [self removePanel];
        [self.orb removeFromSuperview];self.orb=nil;
        return;
    }
    [self removePanel];
    [self drawOrb];
    if(self.isOpen) {
        [self buildPanel];
        // A transient scene with no panel space must keep a usable edge tab.
        if(!self.panel) {
            self.isOpen=NO;
            [self drawOrb];
        }
        [self.overlayView bringSubviewToFront:self.orb];
    }
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint p=[g locationInView:self.overlayView];
    if(g.state==UIGestureRecognizerStateBegan) {
        // Grabbing the bead again while a let-go pull is still springing back
        // lets that finish at once, so this drag starts from the docked bead.
        if(_morphActive) [self completeDrawerMorphNow];
        _isPanning=YES;
        // With Reduce Motion nothing follows the finger: a long enough pull
        // opens the drawer once it is let go.
        _panUsesMorph=!UIAccessibilityIsReduceMotionEnabled();
        _panStartPoint=p;
        _panOriginalCenter=self.orb.center;
        _panOriginalLeft=self.left;
        _panMaxInwardDist=0;
        _panMaxVerticalDist=0;
        _panIsRepositioning=NO;
        _panIsInwardPull=NO;
        _morphCommitHaptic=NO;
        [self cancelOrbFade];
        self.orbFaded=NO;
        self.orb.alpha=1;
    } else if(g.state==UIGestureRecognizerStateChanged) {
        _isPanning=YES;
        [self cancelOrbFade];
        self.orbFaded=NO;
        self.orb.alpha=1;
        
        CGFloat inwardDist = _panOriginalLeft ? (p.x - _panStartPoint.x) : (_panStartPoint.x - p.x);
        CGFloat verticalDist = fabs(p.y - _panStartPoint.y);
        if(inwardDist > _panMaxInwardDist) _panMaxInwardDist = inwardDist;
        if(verticalDist > _panMaxVerticalDist) _panMaxVerticalDist = verticalDist;
        
        // 模式判定（将向内拉出与沿边缘上下滑动明确分离）：
        if(!_panIsRepositioning && !_panIsInwardPull) {
            int intent=FMBeadPanIntent(inwardDist,verticalDist);
            // The reposition branch below owns the compact moving capsule.
            if(intent==FMBeadPanMove) _panIsRepositioning = YES;
            else if(intent==FMBeadPanPull) _panIsInwardPull = YES;
        }
        
        // 在向内拉出过程中，若用户大幅垂直滑动，平滑切换为换位
        if(_panIsInwardPull && !_panIsRepositioning) {
            if(verticalDist > 38.0 && verticalDist > inwardDist * 1.4) {
                _panIsRepositioning = YES;
                _panIsInwardPull = NO;
            }
        }
        
        if(_panIsRepositioning) {
            // A pull that turned into a slide drops the drawer it had started.
            if(_morphActive) [self abortDrawerMorph];
            [self.orb viewWithTag:9204].alpha=0;
            // === 换位模式：自由平移，毫秒级跟手 ===
            CGFloat w=self.window.bounds.size.width,h=self.window.bounds.size.height;
            // Off the wall the handle is a free pill: the capsule outline, in either style.
            FMHandleMetrics pill=FMOrbHandleMetrics(YES);
            CGFloat orbW=FMHandleFrameSize(pill).width,orbH=FMHandleFrameSize(pill).height;
            UIEdgeInsets safe=self.window.safeAreaInsets;
            CGFloat minX=orbW*.5,maxX=MAX(minX,w-orbW*.5);
            CGFloat minY=MAX(60,safe.top+6)+orbH/2;
            CGFloat maxY=MAX(minY,h-MAX(36,safe.bottom+8)-orbH/2);
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.orb.bounds=CGRectMake(0,0,orbW,orbH);
            UIView *bead=[self.orb viewWithTag:9202];
            bead.frame=self.orb.bounds;
            FMApplyOrbOutline(self.orb,FMNotchFamilyPath(FMHandleNotchParams(pill,1,0,0)));
            // Keep the raised fill aligned with the pill.
            FMLayoutOrbCapsule(bead);
            self.orbUpdateLine.hidden=NO;
            self.orbUpdateLine.center=CGPointMake(orbW*.5,orbH*.5);
            [self.orb viewWithTag:9204].alpha=0;
            [CATransaction commit];
            self.orb.center=CGPointMake(Clamp(p.x,minX,maxX),Clamp(p.y,minY,maxY));
            
        } else if(_panUsesMorph && (_morphActive || (_panIsInwardPull && [self beginDrawerDragFromBead]))) {
            // === 抽屉从微珠里长出来，内侧边与手指一比一 ===
            [self applyMorphProgress:FMRubberProgress(inwardDist/_morphTravel)];
            if(inwardDist>=_morphCommit) {
                if(!_morphCommitHaptic && BoolPref(@"haptic",YES))
                    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
                _morphCommitHaptic=YES;
            } else if(inwardDist<_morphCommit*.8) _morphCommitHaptic=NO;
        } else if(_panUsesMorph && !_panIsInwardPull) {
            // Not pulling inward yet: the bead stays exactly where it is.
        } else {
            // No drawer follows the finger (Reduce Motion, or none could be built):
            // the pull is judged when the finger lifts; passing the distance is
            // marked once.
            _panUsesMorph=NO;
            CGFloat commit=FMQuietPullDistance(FMOrbScale());
            if(inwardDist>=commit) {
                if(!_morphCommitHaptic && BoolPref(@"haptic",YES))
                    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
                _morphCommitHaptic=YES;
            } else if(inwardDist<commit*.8) _morphCommitHaptic=NO;
        }
    } else if(g.state==UIGestureRecognizerStateEnded) {
        _isPanning=NO;
        CGPoint v = CGPointZero;
        @try {
            v = [g velocityInView:self.overlayView];
        } @catch(id e) {}
        CGFloat inwardV = _panOriginalLeft ? v.x : -v.x;
        CGFloat finalVerticalDist = fabs(p.y - _panStartPoint.y);
        CGFloat finalTotalDist = hypot(p.x - _panStartPoint.x, p.y - _panStartPoint.y);
        
        if(_panIsRepositioning) {
            // === 移动位置模式：吸附最近边缘并持久化 ===
            self.left=self.orb.center.x<self.window.bounds.size.width*.5;
            ((FMHitButton *)self.orb).docksLeft=self.left;
            self.orbY=Clamp(self.orb.center.y/self.window.bounds.size.height,.1,.9);
            SetPref(@"onLeft",@(self.left));SetPref(@"orbY",@(self.orbY));
            if(UIAccessibilityIsReduceMotionEnabled()) {
                [self drawOrb];
            } else {
                UIButton *dragged=self.orb;
                CGPoint destination=CGPointMake(CGRectGetMidX([self orbFrame]),
                                                CGRectGetMidY([self orbFrame]));
                [UIView animateWithDuration:FMOrbStyleValue(@"orbSnapDuration") delay:0 usingSpringWithDamping:FMOrbStyleValue(@"orbSnapDamping")
                    initialSpringVelocity:.25 options:UIViewAnimationOptionBeginFromCurrentState
                    animations:^{dragged.center=destination;}
                    completion:^(BOOL finished){
                        if(!finished || self.orb!=dragged) return;
                        UIView *capsule=[dragged snapshotViewAfterScreenUpdates:NO];
                        capsule.frame=dragged.frame;capsule.userInteractionEnabled=NO;
                        [self.overlayView addSubview:capsule];
                        [self drawOrb];
                        UIButton *docked=self.orb;
                        CGFloat alpha=docked.alpha;docked.alpha=0;
                        [UIView animateWithDuration:FMOrbStyleValue(@"orbSnapDuration")*.8
                            delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionAllowUserInteraction
                            animations:^{capsule.alpha=0;docked.alpha=alpha;}
                            completion:^(BOOL done){[capsule removeFromSuperview];}];
                    }];
            }
        } else if(_morphActive && _morphDragging) {
            // === 抽屉跟手松开：拉得够远、或甩得够快就展开，否则收回 ===
            CGFloat pulled=_panOriginalLeft?(p.x-_panStartPoint.x):(_panStartPoint.x-p.x);
            // The drawer only follows a pull of several points, so letting go near where the finger
            // started means it was pulled back: that closes it, it is not a tap.
            BOOL open=FMDrawerShouldOpenAfterPull(pulled,_morphCommit,inwardV,finalVerticalDist,CGFLOAT_MAX);
            if(open) [self commitDrawerOpen];
            [self settleDrawerMorphOpen:open velocity:inwardV/_morphTravel];
        } else {
            // === 没有抽屉跟手（减少动态效果，或抽屉造不出来）：按松手时的拉动距离判断 ===
            CGFloat pulled=_panOriginalLeft?(p.x-_panStartPoint.x):(_panStartPoint.x-p.x);
            if(FMDrawerShouldOpenAfterPull(pulled,FMQuietPullDistance(FMOrbScale()),inwardV,finalVerticalDist,finalTotalDist)) {
                if(BoolPref(@"haptic", YES)) {
                    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
                }
                if(!self.isOpen) {
                    [self toggle];
                }
            } else {
                // 微珠没有动过，只恢复自动淡化
                [self scheduleOrbFade];
            }
        }
    } else if(g.state==UIGestureRecognizerStateCancelled || g.state==UIGestureRecognizerStateFailed) {
        _isPanning=NO;
        if(_panIsRepositioning) [self drawOrb];
        else if(_morphActive && _morphDragging) [self settleDrawerMorphOpen:NO velocity:0];
        else [self scheduleOrbFade];
    }
}
- (void)announceDrawerState {
    FMLog(self.isOpen?@"menu-open":@"menu-close",nil);
    [self.orbitContext.events publish:@"orbit.floatingMenu.visibility"
                          payload:@{@"open":@(self.isOpen),@"guestID":GuestID()}];
    if(BoolPref(@"haptic",YES)) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    }
}
// A pull that was let go far enough: the state flips now, the spring finishes.
// The fading bead must not be grabbable again while the drawer comes out (the
// gesture that pulled it has already ended, so this cannot cancel it).
- (void)commitDrawerOpen {
    self.isOpen=YES;
    self.orb.userInteractionEnabled=NO;
    [self announceDrawerState];
}
- (void)commitDrawerClose {
    [self persistAppsScroll];
    self.isOpen=NO;
    [self announceDrawerState];
    self.orbFaded=NO;
    [self scheduleOrbFade];
}
- (void)toggle {
    // A drag or settle already owns the drawer; its release decides the state.
    if(_morphActive) return;
    [self endScrubAnimated:NO];
    BOOL opening=!self.isOpen;
    if(opening) {
        [self cancelOrbFade];
        [self loadAppsScroll];
    } else {
        [self persistAppsScroll];
    }
    self.isOpen=opening; self.page=@"apps";
    if(self.isOpen) {
        self.apps=InstalledApps();
        [self rememberCurrentApp];
    }
    [self announceDrawerState];
    if(!opening) {
        self.orbFaded=NO;
        self.orb.alpha=self.orbNormalAlpha?:0.72;
        [self scheduleOrbFade];
    }
    if(opening) {
        [self draw];
        if(self.panel && self.orb) [self morphDrawerOpen:YES];
    } else if(self.panel && self.orb) {
        [self morphDrawerOpen:NO];
    } else [self draw];
}

// ---------------------------------------------------------------------------
// Bead <-> drawer morph. The drawer is one glass shell whose outline grows out
// of the docked bead. A finger sets the progress directly while dragging; a
// critically damped spring finishes it after release or a tap. With Reduce
// Motion the drawer simply appears and disappears.

// Reads the resting geometry of the freshly built drawer and the docked bead.
// The drawer is slid toward the screen edge by the gap between the two walls
// (landscape safe area) and along its height so the bead lies inside it.
- (BOOL)prepareDrawerMorph {
    UIView *panel=self.panel,*glass=[panel viewWithTag:9230],*orb=self.orb;
    CAShapeLayer *clip=(CAShapeLayer *)glass.layer.mask;
    if(!panel || !orb || !self.window || ![clip isKindOfClass:CAShapeLayer.class]) return NO;
    CGFloat scale=panel.transform.a;
    if(!isfinite(scale) || scale<=0) return NO;
    CGFloat unit=1/scale;
    CGRect rest=panel.frame,bead=orb.frame;
    CGFloat pw=CGRectGetWidth(glass.bounds),ph=CGRectGetHeight(glass.bounds);
    CGFloat dx=self.left?CGRectGetMinX(bead)-CGRectGetMinX(rest):CGRectGetMaxX(bead)-CGRectGetMaxX(rest);
    CGFloat shift=0;
    if(!FMPlaceHandles(FMOrbHandleMetrics(YES),FMOrbHandleMetrics(NO),FMOrbHandleIsCapsule(),unit,pw,ph,
                       (CGRectGetMidY(bead)-CGRectGetMinY(rest))*unit,&_morphBead,&_morphDroplet,&shift)) return NO;
    _morphScale=scale;
    _morphRestCenter=panel.center;
    _morphShift=CGPointMake(dx,shift*scale);
    _morphCompact=BoolPref(@"compactMode",NO);
    // Read the style once per transition; the preference store is a file.
    _morphDrawer=FMDrawerNotchParams(pw,ph,_morphCompact);
    _morphShadow=panel.layer.shadowOpacity;
    // The inner edge moves linearly between these two screen positions, so a
    // finger that travels this far has taken the drawer from bead to fully open.
    _morphTravel=MAX(1,self.left?CGRectGetMaxX(rest)-CGRectGetMaxX(bead):CGRectGetMinX(bead)-CGRectGetMinX(rest));
    // A large bead on a narrow drawer must still be able to reach the commit line.
    _morphCommit=MIN(FMDrawerCommitDistance(_morphTravel,FMOrbScale()),_morphTravel*.8);
    _morphCommitHaptic=NO;
    _morphBeadAlpha=self.orbUpdateAvailable?1:(self.orbNormalAlpha?:.72);
    return YES;
}
// One frame of the morph. Everything that changes with progress is set here,
// so a drag, a settle and the first and last frames cannot disagree.
- (void)applyMorphProgress:(CGFloat)progress {
    UIView *panel=self.panel,*glass=[panel viewWithTag:9230];
    CAShapeLayer *clip=(CAShapeLayer *)glass.layer.mask;
    if(!panel || ![clip isKindOfClass:CAShapeLayer.class]) return;
    // The outline stops at fully open; progress beyond 1 (a spring overshooting
    // or a finger pulling past the end) shows as a stretch toward the screen.
    CGFloat raw=MAX(progress,0),t=MIN(raw,1),stretch=Clamp(raw-1,0,.08);
    _morphProgress=raw;
    // Hold the Bezier wrapper for the whole frame: its CGPath is borrowed.
    __attribute__((objc_precise_lifetime)) UIBezierPath *outline=
        FMDrawerMorphPath(glass.bounds,_morphBead,_morphDroplet,_morphDrawer,self.left,_morphCompact,t);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    clip.path=outline.CGPath;
    for(CALayer *layer in glass.layer.sublayers)
        if([layer.name isEqualToString:@"fm.panel.rim"] && [layer isKindOfClass:CAShapeLayer.class])
            ((CAShapeLayer *)layer).path=outline.CGPath;
    panel.layer.shadowPath=outline.CGPath;
    panel.layer.shadowOpacity=_morphShadow*FMSmooth(t/.5);
    [CATransaction commit];
    // Stretch about the docking wall: scaling about the center moves the wall
    // too, so the center slides back by half the added width.
    panel.transform=CGAffineTransformMakeScale(_morphScale*(1+stretch),_morphScale);
    CGFloat slide=(self.left?1:-1)*stretch*CGRectGetWidth(glass.bounds)*_morphScale*.5;
    panel.center=CGPointMake(_morphRestCenter.x+_morphShift.x*(1-t)+slide,_morphRestCenter.y+_morphShift.y*(1-t));
    // The bead fades out above the glass that replaces it; the panel itself
    // stays opaque, since alpha below one on an ancestor of a visual effect
    // view can flatten the material. The contents stay hidden until the shell
    // is half open, then pop in one after another; they go out together once
    // it falls back below the lower line.
    BOOL reveal=_popRevealed?t>=.42:t>=.5,flipped=reveal!=_popRevealed;
    _popRevealed=reveal;
    if(reveal) _popStarted=YES;
    for(UIView *child in FMGlassContent(glass).subviews)
        if(child.tag!=9217 && child.tag!=9231) child.alpha=_popStarted?1:0;
    if(flipped) [self popContent:reveal];
    [panel viewWithTag:9204].alpha=FMSmooth((t-.1)/.5);
    self.dismissLayer.alpha=FMSmooth(t);
    self.orb.alpha=_morphBeadAlpha*(1-FMSmooth(t/.3));
}
// The drawer contents come in one after another, like the wloc dock icons:
// the lowest first (within a row, the one nearest the wall first), then upward,
// the dividers last. Only rows in view take part. Going out is all at once. The pop-in
// setting can make them come all at once instead, or not animate at all.
- (void)popContent:(BOOL)reveal {
    UIView *glass=[self.panel viewWithTag:9230],*content=FMGlassContent(glass);
    if(!glass || content==glass) return;
    [glass layoutIfNeeded];
    CGFloat wall=self.left?0:CGRectGetWidth(glass.bounds);
    NSMutableArray<NSDictionary *> *items=[NSMutableArray array];
    NSMutableArray<UIView *> *dividers=[NSMutableArray array];
    void (^add)(UIView *)=^(UIView *view) {
        CGRect frame=[view convertRect:view.bounds toView:glass];
        [items addObject:@{@"view":view,@"row":@(lround(CGRectGetMidY(frame)/8)),
                           @"gap":@(fabs(CGRectGetMidX(frame)-wall))}];
    };
    for(UIView *view in self.appsHeaderTiles) {
        if([view isKindOfClass:UIControl.class]) add(view); else [dividers addObject:view];
    }
    for(UIView *view in [content viewWithTag:9232].subviews) {
        if([view isKindOfClass:UIControl.class]) add(view); else [dividers addObject:view];
    }
    UIScrollView *scroll=self.appsScroll;
    CGRect window=scroll?[scroll convertRect:scroll.bounds toView:glass]:CGRectZero;
    for(UIView *view in scroll.subviews) {
        if(![view isKindOfClass:UIStackView.class]) continue;
        for(UIView *row in ((UIStackView *)view).arrangedSubviews)
            if(CGRectIntersectsRect([row convertRect:row.bounds toView:glass],window)) add(row);
        break;
    }
    // With the pop-in off the contents leave with the shell instead of waiting for it to shrink around them.
    if(!reveal && FMPopMode()==2) _popStarted=NO;
    FMPopItems(items,dividers,self.left,reveal);
}
// Builds the drawer behind the bead the moment the pull starts. NO means the
// drawer cannot be shown (no room, a settings window): the droplet carries on.
- (BOOL)beginDrawerDragFromBead {
    if(self.isOpen || self.settingsWindow || !self.orb) return NO;
    [self cancelOrbFade];
    self.page=@"apps";
    [self loadAppsScroll];
    self.apps=InstalledApps();
    [self rememberCurrentApp];
    [self buildPanel];
    if(![self prepareDrawerMorph]) {
        [self removePanel];
        return NO;
    }
    _morphActive=YES;_morphDragging=YES;_morphOpening=YES;_morphFromBead=YES;
    _morphBeadAlpha=1;
    _popRevealed=NO;_popStarted=NO;
    [self.orb.layer removeAnimationForKey:@"opacity"];
    self.panel.userInteractionEnabled=NO;
    self.dismissLayer.userInteractionEnabled=NO;
    [self.overlayView bringSubviewToFront:self.orb];
    [self applyMorphProgress:0];
    return YES;
}
// Plays the open or close transition of a drawer that is already built.
- (void)morphDrawerOpen:(BOOL)open {
    if(UIAccessibilityIsReduceMotionEnabled() || ![self prepareDrawerMorph]) {
        if(!open) [self draw];
        return;
    }
    _morphFromBead=NO;
    // Opening starts with the contents hidden; closing starts with them out.
    _popRevealed=!open;_popStarted=!open;
    [self.overlayView bringSubviewToFront:self.orb];
    [self applyMorphProgress:open?0:1];
    [self settleDrawerMorphOpen:open velocity:0];
}
// Hands the progress to the spring. velocity is in progress per second.
- (void)settleDrawerMorphOpen:(BOOL)open velocity:(CGFloat)velocity {
    _morphActive=YES;
    _morphDragging=NO;
    _morphOpening=open;
    _morphTarget=open?1:0;
    _morphVelocity=Clamp(velocity,-24,24);
    // Opening is the dock's springy one (response .46 s, damping .68); closing is
    // firmer (.40 s, .82) so it does not hang around after the bead is back.
    _morphOmega=2*M_PI/(open?.46:.40);
    _morphZeta=open?.68:.82;
    _morphTick=0;
    _morphElapsed=0;
    _panelDragLive=NO;
    self.panel.userInteractionEnabled=NO;
    self.dismissLayer.userInteractionEnabled=NO;
    if(!_morphLink) {
        _morphLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(morphFrame:)];
        [_morphLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)morphFrame:(CADisplayLink *)link {
    if(!self.panel) { [self endDrawerMorph]; return; }
    CFTimeInterval dt=_morphTick>0?MIN(link.timestamp-_morphTick,1/20.):1/60.;
    _morphTick=link.timestamp;
    _morphElapsed+=dt;
    CGFloat x=_morphProgress,v=_morphVelocity;
    FMSpringStep(&x,&v,_morphTarget,_morphOmega,_morphZeta,dt);
    _morphVelocity=v;
    // Opening is done when the bounce has died down to about a point; closing is
    // done the moment the shell reaches the bead (it cannot go further in).
    BOOL arrived=_morphTarget>.5?(fabs(x-1)<.004 && fabs(v)<.15):x<=.0015;
    arrived=arrived || _morphElapsed>1.2;
    [self applyMorphProgress:arrived?_morphTarget:x];
    if(arrived) [self finishDrawerMorph];
}
- (void)endDrawerMorph {
    [_morphLink invalidate];
    _morphLink=nil;
    _morphActive=NO;_morphDragging=NO;_panelDragLive=NO;
}
// The spring has arrived. Open: hand the drawer back to the user. Closed: a
// pull that was let go early never moved the bead, so only the drawer goes;
// a close from the open drawer rebuilds the docked bead.
- (void)finishDrawerMorph {
    BOOL open=_morphOpening,fromBead=_morphFromBead;
    [self endDrawerMorph];
    if(open) {
        self.panel.userInteractionEnabled=YES;
        self.dismissLayer.userInteractionEnabled=YES;
        self.orb.userInteractionEnabled=NO;
        self.orb.accessibilityElementsHidden=YES;
        if(_drawDeferred) { _drawDeferred=NO; [self draw]; }
    } else if(fromBead && !self.isOpen) {
        BOOL redraw=_drawDeferred;
        [self removePanel];
        if(redraw) { [self draw]; return; }
        self.orbFaded=NO;
        self.orb.alpha=1;
        [self scheduleOrbFade];
    } else {
        _drawDeferred=NO;
        [self draw];
    }
}
// Skips the rest of a settle: used when a new gesture arrives mid-flight.
- (void)completeDrawerMorphNow {
    if(!_morphActive) return;
    if(_morphDragging) { [self abortDrawerMorph]; return; }
    // A redraw asked for meanwhile would replace the bead being grabbed.
    _drawDeferred=NO;
    [self applyMorphProgress:_morphTarget];
    [self finishDrawerMorph];
}
// Drops a drawer that was growing out of the bead without any ceremony.
- (void)abortDrawerMorph {
    if(!_morphActive) return;
    [self removePanel];
    self.orbFaded=NO;
    self.orb.alpha=1;
}
// Dragging the open drawer toward its docking edge shrinks it back into the
// bead under the finger, and a flick or a long enough drag closes it.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if([gestureRecognizer isKindOfClass:UILongPressGestureRecognizer.class]) {
        // A long press over an app row belongs to the scrub lens (but not on a
        // close badge); anywhere else it still opens settings.
        CGPoint point=[gestureRecognizer locationInView:self.appsScroll];
        BOOL overRow=[self scrubRowIndexAtPoint:point]!=NSNotFound;
        if(gestureRecognizer.view!=self.appsScroll) return !overRow;
        UIView *hit=[self.appsScroll hitTest:point withEvent:nil];
        return self.isOpen && !_morphActive && overRow && ![hit isKindOfClass:UIButton.class];
    }
    if(![gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    if(!self.isOpen || _morphActive || UIAccessibilityIsReduceMotionEnabled()) return NO;
    CGPoint move=[(UIPanGestureRecognizer *)gestureRecognizer translationInView:self.overlayView];
    // Only a deliberate horizontal drag toward the edge belongs to the drawer;
    // everything else stays with the list and its buttons.
    return fabs(move.x)>fabs(move.y)*1.2 && (self.left?move.x<0:move.x>0);
}
- (void)panelPan:(UIPanGestureRecognizer *)g {
    CGPoint p=[g locationInView:self.overlayView];
    if(g.state==UIGestureRecognizerStateBegan) {
        _panelDragStart=p.x;
        _panelDragLive=!_morphActive && self.isOpen && [self prepareDrawerMorph];
        if(!_panelDragLive) return;
        [self cancelOrbFade];
        _morphActive=YES;_morphDragging=YES;_morphOpening=NO;_morphFromBead=NO;
        _morphProgress=1;
        _popRevealed=YES;_popStarted=YES;
        [self.orb.layer removeAnimationForKey:@"opacity"];
        self.dismissLayer.userInteractionEnabled=NO;
        [self.overlayView bringSubviewToFront:self.orb];
        [self applyMorphProgress:1];
        return;
    }
    if(!_panelDragLive) return;
    CGFloat outward=self.left?_panelDragStart-p.x:p.x-_panelDragStart;
    if(g.state==UIGestureRecognizerStateChanged) {
        [self applyMorphProgress:FMRubberProgress(1-outward/_morphTravel)];
    } else if(g.state==UIGestureRecognizerStateEnded) {
        CGPoint v=[g velocityInView:self.overlayView];
        CGFloat outwardV=self.left?-v.x:v.x;
        BOOL close=FMDrawerShouldCloseAfterDrag(_morphProgress,outwardV,_morphTravel);
        if(close) [self commitDrawerClose];
        [self settleDrawerMorphOpen:!close velocity:-outwardV/_morphTravel];
    } else if(g.state==UIGestureRecognizerStateCancelled || g.state==UIGestureRecognizerStateFailed) {
        [self settleDrawerMorphOpen:YES velocity:0];
    }
}
// ---------------------------------------------------------------------------
// Long-press scrub, after the wloc dock: hold an app for 0.28 s and a glass lens
// appears under it; slide up and down and the lens follows, the app under it
// grows and ticks, and letting go switches to it. Dragging far past either side
// of the drawer turns letting go into a cancel.

- (UIControl *)switchControlIn:(UIView *)view {
    if([view isKindOfClass:UIControl.class] &&
       [[(UIControl *)view actionsForTarget:self forControlEvent:UIControlEventTouchUpInside]
            containsObject:NSStringFromSelector(@selector(switchFromRow:))]) return (UIControl *)view;
    for(UIView *child in view.subviews) {
        UIControl *found=[self switchControlIn:child];
        if(found) return found;
    }
    return nil;
}
// The app rows of the open list, top to bottom, and the control that switches to each.
- (NSArray<UIView *> *)scrubRowsWithControls:(NSArray<UIControl *> **)controls {
    NSMutableArray<UIView *> *rows=[NSMutableArray array];
    NSMutableArray<UIControl *> *found=[NSMutableArray array];
    for(UIView *view in self.appsScroll.subviews) {
        if(![view isKindOfClass:UIStackView.class]) continue;
        for(UIView *row in ((UIStackView *)view).arrangedSubviews) {
            UIControl *control=[self switchControlIn:row];
            if(!control) continue;
            [rows addObject:row];
            [found addObject:control];
        }
        break;
    }
    if(controls) *controls=found;
    return rows;
}
// point is in the scroll view's own coordinates.
- (NSUInteger)scrubRowIndexAtPoint:(CGPoint)point {
    NSArray<UIView *> *rows=[self scrubRowsWithControls:nil];
    for(NSUInteger index=0;index<rows.count;index++)
        if(CGRectContainsPoint([rows[index] convertRect:rows[index].bounds toView:self.appsScroll],point)) return index;
    return NSNotFound;
}
// The lens: a soft light pill with a bright edge fading downward, like the dock's.
- (UIView *)scrubLensWithFrame:(CGRect)frame {
    CGFloat radius=frame.size.height*.34;
    UIView *lens=[[UIView alloc] initWithFrame:frame];
    lens.userInteractionEnabled=NO;
    lens.backgroundColor=[UIColor.whiteColor colorWithAlphaComponent:FMMenuDark()?.16:.26];
    lens.layer.cornerRadius=radius;
    lens.layer.cornerCurve=kCACornerCurveContinuous;
    lens.layer.shadowColor=UIColor.blackColor.CGColor;
    lens.layer.shadowOpacity=.18;
    lens.layer.shadowRadius=8;
    lens.layer.shadowOffset=CGSizeMake(0,2);
    CAGradientLayer *edge=[CAGradientLayer layer];
    edge.frame=lens.bounds;
    edge.colors=@[(id)[UIColor.whiteColor colorWithAlphaComponent:.9].CGColor,
                  (id)[UIColor.whiteColor colorWithAlphaComponent:.2].CGColor];
    CAShapeLayer *ring=[CAShapeLayer layer];
    ring.frame=lens.bounds;
    ring.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(lens.bounds,.45,.45) cornerRadius:radius].CGPath;
    ring.fillColor=UIColor.clearColor.CGColor;
    ring.strokeColor=UIColor.blackColor.CGColor;
    ring.lineWidth=.9;
    edge.mask=ring;
    [lens.layer addSublayer:edge];
    return lens;
}
// The app's name floats beside the lens, on the side away from the wall. The
// standard list already shows names, so only the icon-only list needs it.
- (void)updateScrubLabel {
    [_scrubLabel removeFromSuperview];
    _scrubLabel=nil;
    if(!BoolPref(@"compactMode",NO) || !_scrubLens || _scrubCancelling ||
       _scrubIndex<0 || _scrubIndex>=(NSInteger)_scrubControls.count) return;
    NSDictionary *app=objc_getAssociatedObject(_scrubControls[_scrubIndex],@selector(switchFromRow:));
    UILabel *text=[self label:FMAppRowTitle(app) size:13 weight:UIFontWeightSemibold];
    text.numberOfLines=1;
    CGFloat width=MIN(190,[text sizeThatFits:CGSizeMake(190,30)].width)+24;
    UIView *holder=[[UIView alloc] initWithFrame:CGRectMake(0,0,width,30)];
    holder.userInteractionEnabled=NO;
    holder.layer.shadowColor=UIColor.blackColor.CGColor;
    holder.layer.shadowOpacity=.15;
    holder.layer.shadowRadius=6;
    holder.layer.shadowOffset=CGSizeMake(0,2);
    UIView *capsule=[self glass:holder.bounds radius:15 strong:NO];
    [holder addSubview:capsule];
    text.frame=CGRectMake(12,0,width-24,30);
    [FMGlassContent(capsule) addSubview:text];
    CGRect panel=self.panel.frame;
    CGFloat x=self.left?CGRectGetMaxX(panel)+8:CGRectGetMinX(panel)-8-width;
    CGPoint center=[_scrubLens.superview convertPoint:_scrubLens.center toView:self.overlayView];
    holder.frame=CGRectMake(x,center.y-15,width,30);
    [self.overlayView addSubview:holder];
    _scrubLabel=holder;
}
// The app under the lens grows; the one it left settles back.
- (void)scrubFocus:(NSInteger)index {
    BOOL calm=UIAccessibilityIsReduceMotionEnabled();
    for(NSUInteger row=0;row<_scrubRows.count;row++) {
        UIView *icon=[_scrubRows[row] viewWithTag:9233];
        CGAffineTransform want=(NSInteger)row==index?CGAffineTransformMakeScale(1.16,1.16):CGAffineTransformIdentity;
        if(!icon || CGAffineTransformEqualToTransform(icon.transform,want)) continue;
        if(calm) icon.transform=want;
        else [UIView animateWithDuration:.4 delay:0 usingSpringWithDamping:.7 initialSpringVelocity:0
                options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                animations:^{ icon.transform=want; } completion:nil];
    }
    [self updateScrubLabel];
}
- (void)beginScrub:(UILongPressGestureRecognizer *)g {
    UIView *glass=[self.panel viewWithTag:9230],*content=FMGlassContent(glass);
    NSArray<UIControl *> *controls=nil;
    NSArray<UIView *> *rows=[self scrubRowsWithControls:&controls];
    NSUInteger found=[self scrubRowIndexAtPoint:[g locationInView:self.appsScroll]];
    if(!glass || content==glass || found==NSNotFound || !self.isOpen || _morphActive) return;
    [glass layoutIfNeeded];
    _scrubRows=rows;_scrubControls=controls;
    _scrubViewport=[self.appsScroll convertRect:self.appsScroll.bounds toView:glass];
    _scrubIndex=(NSInteger)found;
    _scrubCancelling=NO;_scrubActive=YES;
    _scrubPoint=[g locationInView:glass];
    _scrubStartY=_scrubPoint.y;
    CGRect box=CGRectInset([rows[found] convertRect:rows[found].bounds toView:glass],-3,-3);
    _scrubHalf=box.size.height*.5;
    [self scrubMeasure];
    UIView *lens=[self scrubLensWithFrame:box];
    lens.center=CGPointMake(CGRectGetMidX(box),FMScrubLensCenter(_scrubPoint.y,_scrubFirstMid,_scrubLastMid));
    // Icon-only rows are clear, so the lens goes under them like the dock's;
    // the standard rows are cards, so there it goes over them.
    if(BoolPref(@"compactMode",NO)) [content insertSubview:lens belowSubview:self.appsScroll];
    else [content insertSubview:lens aboveSubview:self.appsScroll];
    _scrubLens=lens;
    lens.alpha=0;
    if(UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:.15 animations:^{ lens.alpha=1; }];
    } else {
        lens.transform=CGAffineTransformMakeScale(.7,.7);
        [UIView animateWithDuration:.5 delay:0 usingSpringWithDamping:.72 initialSpringVelocity:0
            options:UIViewAnimationOptionAllowUserInteraction
            animations:^{ lens.alpha=1;lens.transform=CGAffineTransformIdentity; } completion:nil];
    }
    [self scrubFocus:_scrubIndex];
    if(BoolPref(@"haptic",YES)) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft] impactOccurredWithIntensity:.9];
        _scrubTick=[UISelectionFeedbackGenerator new];
        [_scrubTick prepare];
    }
}
// Where every row is now, and how far the lens may travel: between the centres of the
// first and last row in view. A long list scrolls under a sliding finger, so this is
// measured again each time.
- (void)scrubMeasure {
    UIView *glass=[self.panel viewWithTag:9230];
    NSMutableArray<NSValue *> *frames=[NSMutableArray array];
    CGFloat first=CGFLOAT_MAX,last=-CGFLOAT_MAX;
    for(UIView *row in _scrubRows) {
        CGRect frame=[row convertRect:row.bounds toView:glass];
        [frames addObject:[NSValue valueWithCGRect:frame]];
        if(!CGRectIntersectsRect(frame,_scrubViewport)) continue;
        first=MIN(first,CGRectGetMidY(frame));
        last=MAX(last,CGRectGetMidY(frame));
    }
    _scrubFrames=frames;
    _scrubFirstMid=MAX(CGRectGetMinY(_scrubViewport)+_scrubHalf,first);
    _scrubLastMid=MIN(CGRectGetMaxY(_scrubViewport)-_scrubHalf,last);
}
// The row under y (the lens centre), among the rows in view only: a row scrolled out of
// sight has a frame over the header or footer, and must not be picked from there.
- (NSInteger)scrubIndexAtLensY:(CGFloat)y {
    NSUInteger count=_scrubFrames.count;
    CGFloat tops[count+1],bottoms[count+1];
    for(NSUInteger index=0;index<count;index++) {
        CGRect frame=_scrubFrames[index].CGRectValue;
        BOOL visible=CGRectIntersectsRect(frame,_scrubViewport);
        tops[index]=visible?CGRectGetMinY(frame):CGFLOAT_MAX;
        bottoms[index]=visible?CGRectGetMaxY(frame):-CGFLOAT_MAX;
    }
    return FMScrubIndexAtY(y,tops,bottoms,count,_scrubIndex);
}
// Puts the focus and the lens where the finger is, and on whichever row is now under the
// lens when the list has moved beneath a finger that stayed put.
- (void)refreshScrub {
    UIView *glass=[self.panel viewWithTag:9230];
    if(!glass || !_scrubLens) return;
    [self scrubMeasure];
    CGPoint point=_scrubPoint;
    CGFloat lensY=FMScrubLensCenter(point.y,_scrubFirstMid,_scrubLastMid);
    NSInteger index=[self scrubIndexAtLensY:lensY];
    BOOL outside=FMScrubIsOutside(point.x,CGRectGetWidth(glass.bounds));
    BOOL moved=index!=_scrubIndex,flipped=outside!=_scrubCancelling;
    _scrubIndex=index;
    _scrubCancelling=outside;
    if(moved) {
        [_scrubTick selectionChanged];
        [_scrubTick prepare];
        [self scrubFocus:index];
    } else if(flipped) [self updateScrubLabel];
    // The lens follows the finger on a short spring; leaving the drawer shrinks and dims it.
    UIView *lens=_scrubLens;
    if(fabs(lens.center.y-lensY)<.01 && !flipped) return;
    CGPoint center=CGPointMake(lens.center.x,lensY);
    CGAffineTransform shape=outside?CGAffineTransformMakeScale(.85,.85):CGAffineTransformIdentity;
    CGFloat alpha=outside?.45:1;
    void (^follow)(void)=^{
        lens.center=center;lens.transform=shape;lens.alpha=alpha;
        if(self->_scrubLabel) {
            CGPoint inOverlay=[lens.superview convertPoint:center toView:self.overlayView];
            self->_scrubLabel.center=CGPointMake(self->_scrubLabel.center.x,inOverlay.y);
        }
    };
    if(UIAccessibilityIsReduceMotionEnabled()) follow();
    else [UIView animateWithDuration:.25 delay:0 usingSpringWithDamping:.8 initialSpringVelocity:0
            options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
            animations:follow completion:nil];
}
- (void)moveScrub:(UILongPressGestureRecognizer *)g {
    UIView *glass=[self.panel viewWithTag:9230];
    if(!glass || !_scrubLens) return;
    _scrubPoint=[g locationInView:glass];
    [self refreshScrub];
    [self updateScrubAutoScroll];
}
// The list's scrollable range, as content offsets.
- (void)scrubScrollRangeLow:(CGFloat *)low high:(CGFloat *)high {
    UIScrollView *scroll=self.appsScroll;
    *low=-scroll.adjustedContentInset.top;
    *high=MAX(*low,scroll.contentSize.height-scroll.bounds.size.height+scroll.adjustedContentInset.bottom);
}
// How fast the finger is asking the list to scroll right now: zero unless it is pushing
// toward an end that can still move.
- (CGFloat)scrubAutoScrollSpeed {
    UIScrollView *scroll=self.appsScroll;
    if(!_scrubActive || !scroll) return 0;
    CGFloat speed=FMScrubScrollSpeed(_scrubPoint.y,CGRectGetMinY(_scrubViewport),CGRectGetMaxY(_scrubViewport),_scrubStartY);
    CGFloat low,high,offset=scroll.contentOffset.y;
    [self scrubScrollRangeLow:&low high:&high];
    return (speed<0 && offset>low+.01) || (speed>0 && offset<high-.01)?speed:0;
}
// A finger pushing toward the top or bottom of the list keeps scrolling it, one frame at
// a time, for as long as it stays there (or until the end of the list).
- (void)updateScrubAutoScroll {
    if([self scrubAutoScrollSpeed]==0) {
        [_scrubLink invalidate];
        _scrubLink=nil;
        return;
    }
    if(_scrubLink) return;
    _scrubScrollTick=0;
    _scrubLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(scrubScrollFrame:)];
    [_scrubLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)scrubScrollFrame:(CADisplayLink *)link {
    UIScrollView *scroll=self.appsScroll;
    // The list went away under the finger (the scene detached): nothing left to scroll.
    if(!scroll || !_scrubLens) { [self endScrubAnimated:NO]; return; }
    CGFloat speed=[self scrubAutoScrollSpeed];
    CFTimeInterval dt=_scrubScrollTick>0?MIN(link.timestamp-_scrubScrollTick,1/20.):1/60.;
    _scrubScrollTick=link.timestamp;
    if(speed==0) { [self updateScrubAutoScroll]; return; }
    CGFloat low,high;
    [self scrubScrollRangeLow:&low high:&high];
    scroll.contentOffset=CGPointMake(scroll.contentOffset.x,Clamp(scroll.contentOffset.y+speed*dt,low,high));
    [self refreshScrub];
}

- (void)endScrubAnimated:(BOOL)animated {
    if(!_scrubActive && !_scrubLens && !_scrubLabel) return;
    UIView *lens=_scrubLens,*label=_scrubLabel;
    NSArray<UIView *> *rows=_scrubRows;
    _scrubActive=NO;_scrubCancelling=NO;
    _scrubLens=nil;_scrubLabel=nil;_scrubRows=nil;_scrubControls=nil;_scrubFrames=nil;_scrubTick=nil;
    [_scrubLink invalidate];
    _scrubLink=nil;
    void (^settle)(void)=^{
        for(UIView *row in rows) [row viewWithTag:9233].transform=CGAffineTransformIdentity;
    };
    if(animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:.4 delay:0 usingSpringWithDamping:.7 initialSpringVelocity:0
            options:UIViewAnimationOptionBeginFromCurrentState animations:settle completion:nil];
        [UIView animateWithDuration:.16 delay:0
            options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionBeginFromCurrentState
            animations:^{ lens.alpha=0;label.alpha=0; }
            completion:^(BOOL finished) { [lens removeFromSuperview];[label removeFromSuperview]; }];
    } else {
        settle();
        [lens removeFromSuperview];
        [label removeFromSuperview];
    }
}
// Letting go on an app switches to it, exactly as tapping it would; letting go
// after dragging off the side, or on the app already running, does nothing.
- (void)finishScrub:(BOOL)commit {
    if(!_scrubActive) return;
    UIControl *target=nil;
    if(commit && !_scrubCancelling && _scrubIndex>=0 && _scrubIndex<(NSInteger)_scrubControls.count)
        target=_scrubControls[_scrubIndex];
    [self endScrubAnimated:YES];
    if(target.enabled) [target sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)scrubPress:(UILongPressGestureRecognizer *)g {
    if(g.state==UIGestureRecognizerStateBegan) [self beginScrub:g];
    else if(!_scrubActive) return;
    else if(g.state==UIGestureRecognizerStateChanged) [self moveScrub:g];
    else if(g.state==UIGestureRecognizerStateEnded) [self finishScrub:YES];
    else if(g.state==UIGestureRecognizerStateCancelled || g.state==UIGestureRecognizerStateFailed) [self finishScrub:NO];
}
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l=[UILabel new]; l.text=text; l.font=[UIFont systemFontOfSize:size weight:weight];
    l.textColor=FMThemeColor(FMColorText); l.numberOfLines=0; return l;
}
- (UIView *)rowForTitle:(NSString *)title icon:(NSString *)icon height:(CGFloat)height action:(SEL)action {
    UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,278,height)];
    row.backgroundColor=FMThemeColor(FMColorSurface);
    row.layer.cornerRadius=MIN(18,height*.38);
    row.layer.borderWidth=.4;
    row.layer.borderColor=FMThemeColor(FMColorBorder).CGColor;
    UIImageView *symbol=[[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]]];
    symbol.tintColor=FMAccent();
    symbol.contentMode=UIViewContentModeScaleAspectFit;
    symbol.frame=CGRectMake(13,(height-22)/2,22,22);
    [row addSubview:symbol];
    UILabel *name=[self label:title size:14 weight:UIFontWeightMedium];
    name.frame=CGRectMake(47,0,225,height);
    [row addSubview:name];
    if(action) [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return row;
}
// A restrained emerald status light, not a large success badge.
// The outer halo breathes subtly; the solid center always stays readable.
static UIView *FMRunningBreathingLight(CGFloat size) {
    UIView *light=[[UIView alloc] initWithFrame:CGRectMake(0,0,size,size)];
    light.userInteractionEnabled=NO;
    light.accessibilityIdentifier=@"fm.running.breathing-light";
    UIView *halo=[[UIView alloc] initWithFrame:CGRectInset(light.bounds,1,1)];
    halo.layer.cornerRadius=CGRectGetWidth(halo.bounds)*.5;
    halo.backgroundColor=[UIColor colorWithRed:.16 green:.79 blue:.41 alpha:.28];
    [light addSubview:halo];
    CGFloat coreSize=MAX(5,MIN(7,size*.50));
    UIView *core=[[UIView alloc] initWithFrame:CGRectMake((size-coreSize)*.5,(size-coreSize)*.5,coreSize,coreSize)];
    core.backgroundColor=[UIColor colorWithRed:.19 green:.88 blue:.47 alpha:1];
    core.layer.cornerRadius=coreSize*.5;
    core.layer.shadowColor=core.backgroundColor.CGColor;
    core.layer.shadowRadius=2;
    core.layer.shadowOpacity=.30;
    core.layer.shadowOffset=CGSizeZero;
    [light addSubview:core];
    if(!UIAccessibilityIsReduceMotionEnabled()) {
        CABasicAnimation *breath=[CABasicAnimation animationWithKeyPath:@"opacity"];
        breath.fromValue=@.18;breath.toValue=@.78;
        breath.duration=1.85;breath.autoreverses=YES;breath.repeatCount=HUGE_VALF;
        breath.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [halo.layer addAnimation:breath forKey:@"fm.running.breath"];
    }
    return light;
}
- (UIView *)iconViewForApp:(NSDictionary*)app size:(CGFloat)size {
    UIView *box=[[UIView alloc] initWithFrame:CGRectMake(0,0,size,size)];
    box.tag=9233; // The long-press scrub enlarges the icon under its lens.
    box.layer.cornerRadius=size*.22;box.clipsToBounds=YES;
    box.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:.50];
    UIImage *real=FMGuestIcon(app);
    if(real) {
        UIImageView *iv=[[UIImageView alloc] initWithImage:
                         [real imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]];
        iv.frame=box.bounds;iv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        iv.contentMode=UIViewContentModeScaleAspectFill;
        [box addSubview:iv];
    } else {
        UIImageView *fallback=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"app.fill"]];
        fallback.tintColor=FMAccent();fallback.contentMode=UIViewContentModeScaleAspectFit;
        fallback.frame=CGRectInset(box.bounds,size*.26,size*.26);
        [box addSubview:fallback];
    }
    BOOL current=[LCOrbitGuestService isCurrentGuest:app];
    BOOL blocked=![app[@"launchable"] boolValue] && ![app[@"builtin"] boolValue];
    if(current) {
        CGFloat side=MIN(13,MAX(10,size*.30));
        UIView *light=FMRunningBreathingLight(side);
        light.frame=CGRectMake(size-side,size-side,side,side);
        [box addSubview:light];
    } else if(blocked) {
        CGFloat side=MIN(size*.45,MAX(13,MIN(18,size*.36)));
        UIImageView *mark=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.circle.fill"]];
        mark.frame=CGRectMake(size-side-1,size-side-1,side,side);
        mark.backgroundColor=FMThemeColor(FMColorSurface);
        mark.tintColor=FMThemeColor(FMColorSecondary);
        mark.layer.cornerRadius=side*.5;mark.clipsToBounds=YES;
        mark.userInteractionEnabled=NO;
        [box addSubview:mark];
    }
    return box;
}
- (CGFloat)taskCloseSize {
    return 48/MAX(.50,self.panelContentScale?:1);
}
- (CGFloat)appRowHeight {
    return MAX(56,[self taskCloseSize]);
}
- (UIView *)appRow:(NSDictionary *)app {
    // Standard mode extends the drawer without changing its optical material.
    CGFloat height=[self appRowHeight];
    UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,216,height)];
    row.backgroundColor=UIColor.clearColor;
    row.layer.cornerRadius=17;
    // Localized contrast only under list text, not behind the entire glass.
    row.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:
        FMHostUI()?(FMClearGlassEnabled()?.79:.88):FMReadableRowAlpha()];
    CGFloat iconSize=FMMenuStyleValue(@"menuListIconSize");
    UIView *icon=[self iconViewForApp:app size:iconSize];
    icon.frame=CGRectMake(12,(height-iconSize)*.5,iconSize,iconSize);icon.userInteractionEnabled=NO;
    [row addSubview:icon];
    UILabel *title=[self label:FMAppRowTitle(app) size:13 weight:UIFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints=NO;
    title.numberOfLines=1;
    title.lineBreakMode=NSLineBreakByTruncatingTail;
    [row addSubview:title];
    BOOL current=[LCOrbitGuestService isCurrentGuest:app];
    BOOL running=[LCOrbitMultitask isRunningGuest:app];
    UIImageView *arrow=[[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"chevron.right"]];
    arrow.translatesAutoresizingMaskIntoConstraints=NO;
    arrow.tintColor=FMThemeColor(FMColorText);
    arrow.contentMode=UIViewContentModeScaleAspectFit;
    arrow.hidden=running || current;
    [row addSubview:arrow];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [title.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:arrow.leadingAnchor constant:-4],
        [arrow.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [arrow.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-4],
        [arrow.widthAnchor constraintEqualToConstant:18],
        [arrow.heightAnchor constraintEqualToConstant:18]
    ]];
    row.accessibilityLabel=FMAppCaption(app);
    row.accessibilityTraits=UIAccessibilityTraitButton;
    row.enabled=!current;
    objc_setAssociatedObject(row,@selector(switchFromRow:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [row addTarget:self action:@selector(switchFromRow:)
        forControlEvents:UIControlEventTouchUpInside];
    if(!running) return row;
    // Sibling controls keep close taps independent of the row's switch action.
    UIView *container=[[UIView alloc] initWithFrame:row.frame];
    CGFloat closeSize=[self taskCloseSize];
    row.frame=CGRectMake(0,0,container.bounds.size.width-closeSize-4,height);
    row.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [container addSubview:row];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeCustom];
    close.frame=CGRectMake(container.bounds.size.width-closeSize,(height-closeSize)*.5,
                           closeSize,closeSize);
    close.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    UIImageSymbolConfiguration *symbol=[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:symbol] forState:UIControlStateNormal];
    close.tintColor=UIColor.systemRedColor;
    close.accessibilityLabel=[@"关闭 " stringByAppendingString:FMAppCaption(app)];
    objc_setAssociatedObject(close,@selector(closeTaskFromButton:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [close addTarget:self action:@selector(closeTaskFromButton:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:close];
    return container;
}
- (UIStackView *)stack {
    UIStackView *s=[UIStackView new]; s.axis=UILayoutConstraintAxisVertical;
    s.spacing=9; s.alignment=UIStackViewAlignmentFill; s.distribution=UIStackViewDistributionFill;
    s.translatesAutoresizingMaskIntoConstraints=NO;
    return s;
}
- (void)spacer:(UIStackView *)stack size:(CGFloat)height {
    UIView *spacer=[UIView new];[spacer.heightAnchor constraintEqualToConstant:height].active=YES;
    [stack addArrangedSubview:spacer];
}
- (void)addRow:(UIView *)row height:(CGFloat)height to:(UIStackView *)stack {
    [row.heightAnchor constraintEqualToConstant:height].active=YES;
    [stack addArrangedSubview:row];
}
- (void)buildPanel {
    CGRect bounds=self.window.bounds;
    CGFloat safeTop=MAX(38,self.window.safeAreaInsets.top+6);
    CGFloat safeBottom=MAX(26,self.window.safeAreaInsets.bottom+10);
    BOOL hostUI=FMHostUI();
    // UIKit's home-indicator inset does not reserve LC's floating tab bar.
    if(hostUI) safeBottom=MAX(safeBottom,100);
    CGFloat available=bounds.size.height-safeTop-safeBottom;
    // Split-view transitions may temporarily leave no room for a valid panel.
    if(!isfinite(available) || available<96 || bounds.size.width<90) return;
    BOOL small=[self.page isEqualToString:@"apps"];
    BOOL compact=BoolPref(@"compactMode",NO);
    CGFloat shoulder=FMMenuStyleValue(@"menuExtension")*(compact?22./28:1);
    // Compact drawer is 76pt before scaling; only the icon column scrolls.
    // Keep the 63pt logical row hit region even when users choose 50% visual scale.
    UIEdgeInsets safe=self.window.safeAreaInsets;
    CGFloat usableWidth=bounds.size.width-safe.left-safe.right;
    CGFloat pw=MIN(small?(compact?76:240):346,usableWidth-24);
    if(pw<=0) return;
    // A real side drawer: apps and actions share one continuous vertical
    // capsule. Heights depend on the number of visible guests and footer keys.
    NSUInteger appCount=[self visibleApps].count;
    // Nothing pinned (or everything pinned): no strip, and no band reserved for one.
    BOOL showsFavorites=small && !compact && [self pinnedApps].count>0;
    // Compact drawer has exactly one footer control: LC home.
    NSUInteger compactActions=1+([LCOrbitMultitask isPiPActive]?1:0);
    CGFloat actualScale=small?MIN(Clamp(FloatPref(@"panelScale",1.0),.50,1.20),
                                   (usableWidth-20)/pw):1;
    if(!isfinite(actualScale) || actualScale<.50) return;
    CGFloat footerHeight=0,top=0,bottom=0;
    BOOL fits=NO;
    // Fit complete controls before choosing panel height. A short scene trades
    // the favorites strip and padding for a usable list, never overlapping it.
    for(NSUInteger attempt=0;attempt<12;attempt++) {
        self.panelContentScale=actualScale;
        BOOL tight=available/actualScale<360;
        self.panelShowsHeader=showsFavorites && !tight;
        footerHeight=compact?(tight?MAX(50,44/actualScale)*compactActions+4:10+compactActions*63+3):
                              (small?44:(tight?MAX(60,44/actualScale)+8:74));
        top=compact?shoulder+8:(self.panelShowsHeader?64+shoulder:shoulder+6);
        bottom=footerHeight+6+shoulder;
        CGFloat rowHeight=compact?63:[self appRowHeight];
        if(!small || (top+bottom+rowHeight)*actualScale<=available) { fits=YES;break; }
        if(actualScale<=.50) break;
        actualScale=MAX(.50,actualScale*.95);
    }
    if(!fits) return;
    self.panelFooterHeight=footerHeight;
    CGFloat target=small?(compact?MIN(566,20+MAX(1,MIN(appCount,5))*65+footerHeight+12+2*shoulder):
        top+bottom+MAX(1,MIN(appCount,5))*([self appRowHeight]+4)):610;
    if(small) target=MAX(target,top+bottom+(compact?63:[self appRowHeight]));
    if([self.page isEqualToString:@"manage"]) target=620;
    if([self.page isEqualToString:@"diy"]) target=675;
    CGFloat ph=MIN(available/actualScale,target);
    if(!isfinite(ph) || ph<=0 || !isfinite(pw) || pw<=0) return;
    if(hostUI && small) {
        FMLog(@"panel-layout",[NSString stringWithFormat:@"context=lc-host mode=%@ size=%.0fx%.0f safeBottom=%.0f actions=%lu apps=%lu",
            compact?@"compact":@"normal",pw,ph,safeBottom,
            (unsigned long)(compact?compactActions:2),(unsigned long)appCount]);
    }
    CGFloat visualW=pw*actualScale, visualH=ph*actualScale;
    CGFloat edgeInset=(self.left?safe.left:safe.right)+(small?0:10);
    CGFloat centerX=self.left?(edgeInset+visualW*.5):(bounds.size.width-edgeInset-visualW*.5);
    CGFloat topY=small?Clamp(CGRectGetMidY(self.orb.frame)-visualH*.48,
                          safeTop,bounds.size.height-safeBottom-visualH)
                   :safeTop+(available-visualH)*.5;
    CGFloat centerY=topY+visualH*.5;
    UIControl *under=[[UIControl alloc] initWithFrame:bounds];
    under.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:.06];
    [under addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayView addSubview:under];
    self.dismissLayer=under;
    UIView *shadow=[[UIView alloc] initWithFrame:CGRectMake(0,0,pw,ph)];
    shadow.center=CGPointMake(centerX,centerY);
    if(small) {
        // Long-press anywhere on the drawer to enter menu settings, without
        // replacing normal taps on apps, task-close badges, or the footer.
        UILongPressGestureRecognizer *settingsHold=
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(holdPanel:)];
        settingsHold.minimumPressDuration=.65;
        settingsHold.delegate=self; // yields to the scrub lens over the app rows
        [shadow addGestureRecognizer:settingsHold];
        shadow.accessibilityHint=@"长按打开微珠菜单设置";
        // Dragging the drawer toward its docking edge closes it with the finger.
        UIPanGestureRecognizer *edgePan=[[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(panelPan:)];
        edgePan.delegate=self;
        [shadow addGestureRecognizer:edgePan];
    }
    BOOL night=FMMenuDark();
    UIColor *shadowTint=UIColor.blackColor;
    shadow.layer.shadowColor=shadowTint.CGColor;
    shadow.layer.shadowOpacity=small?(night?.30:.18):.18;
    shadow.layer.shadowRadius=small?18:22;
    shadow.layer.shadowOffset=CGSizeMake(0,3);
    // Both layouts share the same inward-curved side-notch silhouette.
    CGFloat radius=small?(compact?MIN(25,pw*.33):29):32;
    UIView *glass=[self glass:shadow.bounds radius:radius strong:YES];
    glass.tag=9230; // The drawer morph reshapes this view's clip, rim and shadow.
    if(small) {
        FMAddOrbBackdrop(shadow,self.left);
        FMApplySideNotch(glass,shadow.layer,self.left,compact,NO);
        for(CALayer *layer in glass.layer.sublayers)
            if([layer isKindOfClass:CAShapeLayer.class]) layer.name=@"fm.panel.rim";
    }
    [shadow addSubview:glass];
    // The native material supplies depth; the shared notch adds only its rim.
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:CGRectInset(glass.bounds,14,14)];
    scroll.showsVerticalScrollIndicator=NO;
    scroll.alwaysBounceVertical=NO;
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    scroll.contentInset=UIEdgeInsetsMake(0,0,4,0);
    [FMGlassContent(glass) addSubview:scroll];
    if(small) {
        // Only the central application list scrolls; header and footer never move.
        if(self.panelShowsHeader) [self buildAppHeader:glass];
        scroll.frame=CGRectMake(compact?3:12,top,pw-(compact?6:24),
                                ph-top-bottom);
        scroll.clipsToBounds=YES;
        [self buildAppFooter:glass];
    }
    UIStackView *stack=[self stack];
    stack.spacing=small?(compact?3:4):10;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    if(small) {
        self.appsScroll=scroll;
        scroll.delegate=self;
        // Hold an app for a moment and a glass lens slides over the list (after
        // the wloc dock): slide to pick, let go to switch. Moving before the
        // delay is a scroll or a tap, as before.
        UILongPressGestureRecognizer *scrubPress=[[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(scrubPress:)];
        scrubPress.minimumPressDuration=.28;
        scrubPress.allowableMovement=10;
        scrubPress.delegate=self;
        [scroll addGestureRecognizer:scrubPress];
        self.appsScrollRestorePending=YES;
        [self appPage:stack];
        CGFloat offset=self.appsScrollOffset;
        dispatch_async(dispatch_get_main_queue(), ^{
            if(self.appsScroll!=scroll || !scroll.superview) return;
            [scroll.superview layoutIfNeeded];
            [scroll layoutIfNeeded];
            CGFloat maxY=MAX(0,scroll.contentSize.height-scroll.bounds.size.height+
                                  scroll.adjustedContentInset.bottom);
            [scroll setContentOffset:CGPointMake(0,MIN(MAX(0,offset),maxY)) animated:NO];
            self.appsScrollRestorePending=NO;
        });
    } else {
        self.settingsScroll=scroll;
        [self settingsPage:stack];
        CGFloat offset=self.settingsScrollOffset;
        dispatch_async(dispatch_get_main_queue(), ^{
            if(self.settingsScroll != scroll || !scroll.superview) return;
            [scroll layoutIfNeeded];
            CGFloat maxY=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
            [scroll setContentOffset:CGPointMake(0,MIN(offset,maxY)) animated:NO];
        });
    }
    [self.overlayView addSubview:shadow];
    self.panel=shadow;
    // Never reposition the bead when opening a compact drawer.
    // drawOrb uses the saved orbY/onLeft values on both open and close;
    // mutating its center here caused the handle to jump every time.
    shadow.alpha=1;
    shadow.transform=CGAffineTransformMakeScale(actualScale,actualScale);
}
- (void)header:(UIStackView *)stack title:(NSString *)title sub:(NSString *)sub {
    UILabel *a=[self label:title size:22 weight:UIFontWeightBold]; [stack addArrangedSubview:a];
    UILabel *b=[self label:sub size:12 weight:UIFontWeightRegular]; b.textColor=FMThemeColor(FMColorSecondary);
    [stack addArrangedSubview:b]; [self spacer:stack size:8];
}
- (NSArray<NSDictionary*> *)visibleApps {
    // Visibility is not launch eligibility. Keep the current app and blocked
    // entries; controls and the guest service independently guard execution.
    NSMutableArray *found=[self.apps mutableCopy] ?: [NSMutableArray array];
    NSArray *order=[HostDefaults() arrayForKey:Pref(@"menuOrder")];
    if([order isKindOfClass:NSArray.class] && order.count) {
        [found sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
            NSUInteger ai=[order indexOfObject:a[@"identity"] ?: a[@"path"]];
            NSUInteger bi=[order indexOfObject:b[@"identity"] ?: b[@"path"]];
            // Read pre-fix preferences without merging new private/shared keys.
            if(ai==NSNotFound) ai=[order indexOfObject:a[@"path"]];
            if(bi==NSNotFound) bi=[order indexOfObject:b[@"path"]];
            if(ai!=bi) return ai<bi?NSOrderedAscending:NSOrderedDescending;
            return [a[@"title"] localizedStandardCompare:b[@"title"]];
        }];
    }
    return found;
}
// Only the visible launcher is reordered. App management and pinned favorites
// continue to use the user's manual order, regardless of this switch.
- (void)rememberCurrentApp {
    if(!BoolPref(@"recentAppsFirst",NO)) return;
    for(NSDictionary *app in self.apps) {
        if([LCOrbitGuestService isCurrentGuest:app]) {
            FMRememberOpenedApp(app);
            break;
        }
    }
}
- (NSArray<NSDictionary *> *)orderedAppsForMenu {
    NSArray<NSDictionary *> *apps=[self visibleApps];
    if(!BoolPref(@"recentAppsFirst",NO) || apps.count<2) return apps;
    id preference=[HostDefaults() objectForKey:Pref(@"recentOpenedAppKeys")];
    NSArray *recent=[preference isKindOfClass:NSArray.class]?preference:@[];
    NSMutableArray<NSDictionary *> *sorted=[apps mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        BOOL currentA=[LCOrbitGuestService isCurrentGuest:a];
        BOOL currentB=[LCOrbitGuestService isCurrentGuest:b];
        if(currentA!=currentB) return currentA?NSOrderedAscending:NSOrderedDescending;
        NSUInteger indexA=[recent indexOfObject:FMAppKey(a)];
        NSUInteger indexB=[recent indexOfObject:FMAppKey(b)];
        if(indexA!=indexB) return indexA<indexB?NSOrderedAscending:NSOrderedDescending;
        NSUInteger manualA=[apps indexOfObjectIdenticalTo:a];
        NSUInteger manualB=[apps indexOfObjectIdenticalTo:b];
        return manualA<manualB?NSOrderedAscending:manualA>manualB?NSOrderedDescending:NSOrderedSame;
    }];
    return sorted;
}
- (NSArray<NSString*> *)favorites {
    NSArray *v=[HostDefaults() arrayForKey:Pref(@"favoritePaths")];
    return [v isKindOfClass:NSArray.class]?v:@[];
}
- (NSArray<NSString*> *)unavailableFavorites {
    // Guest inventories can be partial. Expose absent identities for explicit
    // removal without assuming that a missing entry has been uninstalled.
    NSMutableArray *missing=[NSMutableArray array];
    NSArray *apps=[self visibleApps];
    for(NSString *key in [self favorites]) {
        BOOL found=NO;
        for(NSDictionary *app in apps)
            if([key isEqualToString:FMAppKey(app)] || [key isEqualToString:app[@"path"]]) {
                found=YES;break;
            }
        if(!found) [missing addObject:key];
    }
    return missing;
}
- (void)appPage:(UIStackView *)stack {
    NSArray<NSDictionary*> *apps=[self orderedAppsForMenu];
    if(BoolPref(@"compactMode",NO)) {
        for(NSDictionary *app in apps) {
            // Preserve the 63pt full-width hit area, independent of the
            // smaller 46pt icon and its painted backing.
            UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,88,63)];
            row.backgroundColor=UIColor.clearColor;
            // The 63pt row stays clickable, but its painted backing is inset
            // around the app icon so compact/single-task tiles feel lighter. The plate
            // used to be drawn in the LC host only; it is what gives an icon its seat on
            // the glass, so it is a setting now and a Guest gets one too.
            if(BoolPref(@"iconFrame",YES)) {
                UIView *backing=[UIView new];
                backing.translatesAutoresizingMaskIntoConstraints=NO;
                backing.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:
                    FMClearGlassEnabled()?.64:.74];
                backing.layer.cornerRadius=14;
                backing.layer.borderWidth=.5;
                backing.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:
                    FMMenuDark()?.26:.40].CGColor;
                backing.userInteractionEnabled=NO;
                [row addSubview:backing];
                [NSLayoutConstraint activateConstraints:@[
                    [backing.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
                    [backing.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
                    [backing.widthAnchor constraintEqualToConstant:54],
                    [backing.heightAnchor constraintEqualToConstant:54]
                ]];
            }
            row.accessibilityLabel=FMAppCaption(app);
            row.accessibilityTraits=UIAccessibilityTraitButton;
            row.enabled=![LCOrbitGuestService isCurrentGuest:app];
            CGFloat iconSize=FMMenuStyleValue(@"menuCompactIconSize");
            UIView *icon=[self iconViewForApp:app size:iconSize];
            icon.translatesAutoresizingMaskIntoConstraints=NO;
            icon.userInteractionEnabled=NO;
            icon.layer.borderWidth=.55;
            icon.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:
                                    FMMenuDark()?.54:.36].CGColor;
            icon.layer.shadowColor=UIColor.blackColor.CGColor;
            icon.layer.shadowOpacity=FMMenuDark()?.22:.13;
            icon.layer.shadowRadius=4;
            [row addSubview:icon];
            [NSLayoutConstraint activateConstraints:@[
                [icon.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
                [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
                [icon.widthAnchor constraintEqualToConstant:iconSize],
                [icon.heightAnchor constraintEqualToConstant:iconSize]
            ]];
            objc_setAssociatedObject(row,@selector(switchFromRow:),
                                     app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [row addTarget:self action:@selector(switchFromRow:)
                forControlEvents:UIControlEventTouchUpInside];
            if([LCOrbitMultitask isRunningGuest:app]) {
                CGFloat closeSize=MIN(32,24/MAX(.70,self.panelContentScale?:1));
                UIView *container=[[UIView alloc] initWithFrame:CGRectMake(0,0,70,63)];
                // A bounded corner target preserves the icon's center for
                // switching and keeps running/nonrunning rows equally tall.
                row.translatesAutoresizingMaskIntoConstraints=NO;
                [container addSubview:row];
                [NSLayoutConstraint activateConstraints:@[
                    [row.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
                    [row.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
                    [row.topAnchor constraintEqualToAnchor:container.topAnchor],
                    [row.heightAnchor constraintEqualToConstant:63]
                ]];
                UIButton *close=[UIButton buttonWithType:UIButtonTypeCustom];
                close.translatesAutoresizingMaskIntoConstraints=NO;
                close.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
                close.contentVerticalAlignment=UIControlContentVerticalAlignmentTop;
                UIImageSymbolConfiguration *symbol=[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
                [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:symbol] forState:UIControlStateNormal];
                close.tintColor=UIColor.systemRedColor;
                close.accessibilityLabel=[@"关闭 " stringByAppendingString:FMAppCaption(app)];
                objc_setAssociatedObject(close,@selector(closeTaskFromButton:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [close addTarget:self action:@selector(closeTaskFromButton:) forControlEvents:UIControlEventTouchUpInside];
                [container addSubview:close];
                [NSLayoutConstraint activateConstraints:@[
                    [close.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-2],
                    [close.topAnchor constraintEqualToAnchor:container.topAnchor],
                    [close.widthAnchor constraintEqualToConstant:closeSize],
                    [close.heightAnchor constraintEqualToConstant:closeSize]
                ]];
                [self addRow:container height:63 to:stack];
            } else [self addRow:row height:63 to:stack];
        }
    } else {
        for(NSDictionary *app in apps)
            [self addRow:[self appRow:app] height:[self appRowHeight] to:stack];
    }
    if(!apps.count) {
        UILabel *empty=[self label:@"暂无应用" size:13 weight:UIFontWeightMedium];
        empty.textAlignment=NSTextAlignmentCenter;
        empty.textColor=FMClearGlassEnabled()?FMThemeColor(FMColorText):FMThemeColor(FMColorSecondary);
        [self addRow:empty height:BoolPref(@"compactMode",NO)?68:[self appRowHeight] to:stack];
    }
}
- (void)buildAppHeader:(UIView *)glass {
    for(UIView *tile in self.appsHeaderTiles) [tile removeFromSuperview];
    self.appsHeaderGlass=glass;
    NSMutableArray<UIView *> *tiles=[NSMutableArray array];
    CGFloat w=glass.bounds.size.width, inner=w-24;
    // Favorites show icons only; app names remain available to VoiceOver.
    NSArray<NSDictionary *> *pinned=[self pinnedApps];
    BOOL compact=BoolPref(@"compactMode",NO);
    CGFloat gap=4,cell=(inner-gap*3)/4;
    // Fewer than four sit in the middle instead of leaving the whole gap at one end.
    CGFloat left=12+(inner-(cell*pinned.count+gap*(pinned.count?pinned.count-1:0)))*.5;
    for(NSUInteger i=0;i<pinned.count;i++) {
        NSDictionary *app=pinned[i];
        UIControl *tile=[[UIControl alloc] initWithFrame:
            CGRectMake(left+i*(cell+gap),(compact?5:8)+(compact?22:28),cell,compact?48:40)];
        tile.backgroundColor=UIColor.clearColor;
        CGFloat iconSize=compact?40:32;
        UIView *icon=[self iconViewForApp:app size:iconSize];
        icon.frame=CGRectMake((cell-iconSize)*.5,4,iconSize,iconSize);
        icon.userInteractionEnabled=NO;
        [tile addSubview:icon];
        objc_setAssociatedObject(tile,@selector(switchFromRow:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [tile addTarget:self action:@selector(switchFromRow:) forControlEvents:UIControlEventTouchUpInside];
        tile.accessibilityLabel=FMAppCaption(app);
        tile.accessibilityTraits=UIAccessibilityTraitButton;
        tile.enabled=![LCOrbitGuestService isCurrentGuest:app];
        [FMGlassContent(glass) addSubview:tile];
        [tiles addObject:tile];
    }
    if(tiles.count) {
        CGFloat y=CGRectGetMaxY(tiles.lastObject.frame)+8;
        UIView *separator=[[UIView alloc] initWithFrame:
                           CGRectMake(12,y,inner,1/UIScreen.mainScreen.scale)];
        separator.backgroundColor=[FMThemeColor(FMColorBorder) colorWithAlphaComponent:.55];
        separator.userInteractionEnabled=NO;
        [FMGlassContent(glass) addSubview:separator];
        [tiles addObject:separator];
    }
    self.appsHeaderTiles=tiles;
}
// The apps pinned as favorites, in the order they were pinned, at most four. Empty when
// every app is pinned: the strip is a shortcut into a longer list, and repeating the whole
// list above the rows would only say the same thing twice.
- (NSArray<NSDictionary *> *)pinnedApps {
    NSArray<NSDictionary *> *apps=[self visibleApps];
    NSMutableArray<NSDictionary *> *pinned=[NSMutableArray array];
    for(NSString *key in [self favorites]) for(NSDictionary *item in apps)
        if(([key isEqualToString:FMAppKey(item)] || [key isEqualToString:item[@"path"]]) && pinned.count<4) {
            [pinned addObject:item];
            break;
        }
    return pinned.count<apps.count?pinned:@[];
}
- (void)buildAppFooter:(UIView *)glass {
    BOOL compact=BoolPref(@"compactMode",NO);
    NSMutableArray<NSArray*> *items=[NSMutableArray array];
    if(compact) {
        [items addObject:@[@"house.fill",NSStringFromSelector(@selector(compactReturnHome)),@"返回首页"]];
        // AVKit's PiP close affordance varies across iOS versions. Give the
        // compact drawer an explicit stop control only while PiP is active.
        if([LCOrbitMultitask isPiPActive])
            [items addObject:@[@"pip.exit",NSStringFromSelector(@selector(closePictureInPicture)),@"关闭画中画"]];
    } else {
        if([LCOrbitMultitask isEnabled]) {
            [items addObject:@[@"house.fill",NSStringFromSelector(@selector(goHome)),@"返回 LC，保留运行任务"]];
            [items addObject:@[@"xmark.circle",NSStringFromSelector(@selector(closeMultitaskGuest)),@"关闭当前任务"]];
            if([LCOrbitMultitask isPiPActive])
                [items addObject:@[@"pip.exit",NSStringFromSelector(@selector(closePictureInPicture)),@"关闭画中画"]];
        }
        if(!FMHostUI()) {
            if(BoolPref(@"showRestart",YES))
                [items addObject:@[@"arrow.clockwise",NSStringFromSelector(@selector(restart)),@"重新启动"]];
            [items addObject:@[@"house.fill",NSStringFromSelector(@selector(goHome)),@"返回 LiveContainer"]];
        }
        [items addObjectsFromArray:@[
            @[@"gearshape.fill",NSStringFromSelector(@selector(openSettings)),@"设置"],
            @[self.left?@"chevron.compact.left":@"chevron.compact.right",NSStringFromSelector(@selector(toggle)),@"收起菜单"]
        ]];
    }
    CGFloat w=glass.bounds.size.width;
    CGFloat height=self.panelFooterHeight;
    UIView *footer=[[UIView alloc] initWithFrame:CGRectMake(compact?3:12,
                       glass.bounds.size.height-height-6-(compact?22:28),w-(compact?6:24),height)];
    footer.backgroundColor=UIColor.clearColor;
    footer.tag=9232; // The drawer pop-in animates its buttons one by one.
    [FMGlassContent(glass) addSubview:footer];
    if(compact) {
        // Keep one continuous drawer shell rather than nesting another
        // pill-shaped control panel inside it.
        UIView *separator=[[UIView alloc] initWithFrame:CGRectMake(13,0,
                                               footer.bounds.size.width-26,.8)];
        separator.backgroundColor=[FMThemeColor(FMColorBorder) colorWithAlphaComponent:.55];
        [footer addSubview:separator];
    }
    CGFloat slot=compact?(height-4)/MAX(1,items.count):footer.bounds.size.width/items.count;
    for(NSUInteger i=0;i<items.count;i++) {
        NSArray *spec=items[i];
        CGRect hit=compact?
            CGRectMake(0,4+i*slot,footer.bounds.size.width,slot):
            CGRectMake(i*slot,0,slot,height);
        UIControl *button=[[UIControl alloc] initWithFrame:hit];
        button.backgroundColor=UIColor.clearColor;
        button.accessibilityLabel=spec[2];
        button.accessibilityTraits=UIAccessibilityTraitButton;
        button.accessibilityHint=@"轻触执行";
        CGFloat tileSize=compact?50:36;
        UIView *tile=[[UIView alloc] initWithFrame:
            CGRectMake((hit.size.width-tileSize)*.5,(hit.size.height-tileSize)*.5,
                       tileSize,tileSize)];
        if(!compact) {
            button.frame=CGRectOffset(tile.frame,hit.origin.x,hit.origin.y);
            tile.frame=button.bounds;
        }
        tile.layer.cornerRadius=tileSize*.26;
        tile.layer.cornerCurve=kCACornerCurveContinuous;
        tile.backgroundColor=compact?[UIColor.whiteColor colorWithAlphaComponent:FMMenuDark()?.10:.18]:FMClearGlassEnabled()?
            [FMThemeColor(FMColorTool) colorWithAlphaComponent:
                 UIAccessibilityIsReduceTransparencyEnabled()?.94:.48]:
            FMThemeColor(FMColorTool);
        tile.userInteractionEnabled=NO;
        tile.layer.borderWidth=.8;
        tile.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:
                                  FMMenuDark()?.55:.28].CGColor;
        // The exact same optical tile size/radius rhythm as the Guest icons.
        tile.layer.shadowColor=UIColor.blackColor.CGColor;
        tile.layer.shadowOpacity=FMMenuDark()?.20:.09;
        tile.layer.shadowRadius=3;
        [button addSubview:tile];
        UIImageSymbolConfiguration *conf=[UIImageSymbolConfiguration
           configurationWithPointSize:compact?23:22 weight:UIImageSymbolWeightSemibold];
        UIImageView *glyph=[[UIImageView alloc] initWithImage:
                                     [UIImage systemImageNamed:spec[0] withConfiguration:conf]];
        glyph.frame=CGRectInset(tile.bounds,compact?12:7,compact?12:7);
        glyph.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        glyph.contentMode=UIViewContentModeScaleAspectFit;
        glyph.tintColor=compact?FMThemeColor(FMColorText):FMClearGlassEnabled()?FMThemeColor(FMColorText):FMAccent();
        glyph.userInteractionEnabled=NO;
        [tile addSubview:glyph];
        [button addTarget:self action:NSSelectorFromString(spec[1])
                    forControlEvents:UIControlEventTouchUpInside];
        [footer addSubview:button];
    }
}
- (void)refreshUI {
    if(self.settingsWindow) [self updateSettingsContent];
    else [self draw];
}
// A task closing changes only the running badges/actions, not the drawer's
// glass, layout, handle, or scroll view. Update those rows in-place instead
// of tearing down the entire overlay (which caused a visible glass flash).
- (void)refreshAppsContent {
    if(!self.isOpen || !self.panel || !self.appsScroll ||
       ![self.page isEqualToString:@"apps"]) return;
    UIScrollView *scroll=self.appsScroll;
    UIStackView *stack=nil;
    for(UIView *view in scroll.subviews)
        if([view isKindOfClass:UIStackView.class]) {stack=(UIStackView *)view;break;}
    if(!stack) { [self draw];return; }
    [self endScrubAnimated:NO]; // its rows are about to be replaced
    [self captureAppsScroll];
    CGFloat saved=self.appsScrollOffset;
    self.appsScrollRestorePending=YES;
    for(UIView *row in [stack.arrangedSubviews copy]) {
        [stack removeArrangedSubview:row];
        [row removeFromSuperview];
    }
    [self appPage:stack];
    if(self.appsHeaderGlass) [self buildAppHeader:self.appsHeaderGlass];
    [scroll layoutIfNeeded];
    CGFloat maxY=MAX(0,scroll.contentSize.height-scroll.bounds.size.height+
                          scroll.adjustedContentInset.bottom);
    [scroll setContentOffset:CGPointMake(0,MIN(MAX(0,saved),maxY)) animated:NO];
    self.appsScrollRestorePending=NO;
}
- (void)requestAppsRefresh {
    // didActivateWindow and forgetWindow may notify during one close. Merge
    // their updates into a single frame, preserving the native glass shell.
    if(self.appsRefreshScheduled) return;
    self.appsRefreshScheduled=YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.appsRefreshScheduled=NO;
        if(self.isOpen && self.panel && self.appsScroll &&
           [LCOrbitMultitask shouldShowFloatingMenu]) [self refreshAppsContent];
        else if(![LCOrbitMultitask shouldShowFloatingMenu]) [self draw];
    });
}
- (void)openSettings {
    [self openSettingsInScene:self.window.windowScene?:[self foregroundScene]];
}
- (void)openSettingsInScene:(UIWindowScene *)scene {
    if(self.settingsWindow || !scene) return;
    if(!self.orbitContext) self.orbitContext=[LCOrbitCore sharedCore].context;
    // The Guest is still running, but its window must not receive any taps
    // while native navigation is open. This is a separate opaque UIWindow.
    [self persistAppsScroll];
    self.page=@"settings";
    self.isOpen=NO;
    [self removePanel];
    [self.orb removeFromSuperview];self.orb=nil;
    self.previousKeyWindow=nil;
    for(UIWindow *candidate in scene.windows) {
        if(candidate.isKeyWindow && candidate!=self.window) {
            self.previousKeyWindow=candidate;
            break;
        }
    }
    [self.orbitContext.overlays setModule:@"FloatingMenu" visible:NO];
    UIWindow *settings=[[UIWindow alloc] initWithWindowScene:scene];
    settings.frame=scene.coordinateSpace.bounds;
    settings.windowLevel=UIWindowLevelNormal+90;
    settings.backgroundColor=FMThemeColor(FMColorBackground);
    settings.overrideUserInterfaceStyle=FMMenuOverride();
    FMSettingsRootController *home=[FMSettingsRootController new];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:home];
    nav.navigationBar.prefersLargeTitles=YES;
    FMApplyNavigationTheme(nav);
    home.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"chevron.left"] style:UIBarButtonItemStylePlain
        target:self action:@selector(closeSettings)];
    home.navigationItem.leftBarButtonItem.accessibilityLabel=@"返回";
    settings.rootViewController=nav;
    self.settingsNavigation=nav;
    self.settingsWindow=settings;
    [settings makeKeyAndVisible];
    self.orbPreviewHost=[[UIView alloc] initWithFrame:settings.bounds];
    self.orbPreviewHost.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.orbPreviewHost.userInteractionEnabled=NO;
    self.orbPreviewHost.accessibilityElementsHidden=YES;
    [settings addSubview:self.orbPreviewHost];
    [self refreshOrbPreview];
    FMLog(@"settings-open",@"navigation-window");
}
- (void)closeSettings {
    if(!self.settingsWindow) return;
    UIWindow *prior=self.previousKeyWindow;
    UIWindow *old=self.settingsWindow;
    UIWindowScene *scene=old.windowScene;
    [self.orbPreviewHost removeFromSuperview];self.orbPreviewHost=nil;self.dimensionsPreview=nil;
    self.settingsWindow=nil;
    self.settingsNavigation=nil;
    self.previousKeyWindow=nil;
    old.hidden=YES;
    old.rootViewController=nil;
    BOOL visible=[LCOrbitMultitask shouldShowFloatingMenu];
    [self.orbitContext.overlays setModule:@"FloatingMenu" visible:visible];
    if(prior && prior!=old && !prior.hidden) [prior makeKeyWindow];
    else {
        // Try to return keyboard status to a normal Guest window.
        for(UIWindow *candidate in scene.windows) {
            if(candidate!=self.window && candidate!=old && !candidate.hidden &&
               candidate.windowLevel<UIWindowLevelAlert) {
                [candidate makeKeyWindow]; break;
            }
        }
    }
    self.page=@"apps";
    self.isOpen=visible;
    self.apps=InstalledApps();
    if(visible) { [self rememberCurrentApp]; [self loadAppsScroll]; }
    FMLog(@"settings-close",FMHostUI()?@"lc-host-foreground":@"guest-foreground");
    [self draw];
}
- (UIView *)orbPreviewWithFrame:(CGRect)frame left:(BOOL)left {
    CGFloat w=frame.size.width,h=frame.size.height;
    UIView *body=[[UIView alloc] initWithFrame:frame];
    body.tag=9211;body.userInteractionEnabled=NO;
    FMAddOrbBackdrop(body,left);
    UIView *glass=[self glass:body.bounds radius:w*.5 strong:NO];
    // The same accent shadow the real bead casts (the outline sets the shadow path).
    body.layer.shadowColor=FMAccent().CGColor;
    body.layer.shadowOpacity=.24;body.layer.shadowRadius=6;
    body.layer.shadowOffset=CGSizeMake(0,1);
    FMApplySideNotch(glass,body.layer,left,YES,YES);
    FMAddOrbCapsule(glass,left);
    [body addSubview:glass];
    [glass addSubview:FMOrbLine(body.bounds)];
    CGFloat alpha=BoolPref([@"override." stringByAppendingString:GuestID()],NO)?
        FloatPref([@"appAlpha." stringByAppendingString:GuestID()],FloatPref(@"idleAlpha",.72)):
        FloatPref(@"idleAlpha",.72);
    body.alpha=Clamp(alpha,.25,1);
    return body;
}
- (void)refreshOrbPreview {
    UIView *host=self.orbPreviewHost;if(!host) return;
    host.hidden=self.dimensionsPreview!=nil;
    if(host.hidden) return;
    if(self.settingsWindow) host.frame=self.settingsWindow.bounds;
    for(UIView *view in [host.subviews copy]) [view removeFromSuperview];
    CGFloat w=self.orbWidth,h=self.orbHeight;
    CGFloat position=Clamp(FloatPref(@"orbY",self.orbY>0?self.orbY:.5),.1,.9);
    CGFloat y=Clamp(host.bounds.size.height*position-h*.5,0,MAX(0,host.bounds.size.height-h));
    BOOL left=BoolPref(@"onLeft",self.left);
    [host addSubview:[self orbPreviewWithFrame:CGRectMake(left?0:host.bounds.size.width-w,y,w,h) left:left]];
}
- (void)updateSettingsContent {
    [self refreshOrbPreview];
    self.settingsWindow.backgroundColor=FMThemeColor(FMColorBackground);
    FMApplyNavigationTheme(self.settingsNavigation);
    // Refresh all loaded pages so Back never reveals the previous palette.
    for(UIViewController *controller in self.settingsNavigation.viewControllers) {
        if(!controller.isViewLoaded) continue;
        controller.view.backgroundColor=FMThemeColor(FMColorBackground);
        if([controller isKindOfClass:FMSettingsSectionController.class])
            [(FMSettingsSectionController*)controller rebuild];
        else if([controller isKindOfClass:FMSettingsRootController.class])
            [(FMSettingsRootController*)controller rebuild];
        else if([controller isKindOfClass:FMDockSettingsController.class])
            [(FMDockSettingsController*)controller rebuild];
        else if([controller isKindOfClass:LCOrbitSharedTweaksViewController.class])
            [(LCOrbitSharedTweaksViewController*)controller
                updateBackground:FMThemeColor(FMColorBackground)
                surface:FMThemeColor(FMColorSurface)
                text:FMThemeColor(FMColorText)
                secondary:FMThemeColor(FMColorSecondary)
                accent:FMAccent()];
    }
}
- (void)populateSettingsCategory:(NSString *)category stack:(UIStackView *)s {
    if([category isEqualToString:@"appearance"]) {
        [self section:@"日间与夜间" sub:FMHostUI()?@"仅调整悬浮菜单，不影响 LC 主界面。":@"仅调整悬浮菜单，不影响 Guest App。" in:s];
        [self appearanceModeControl:s];
        [self spacer:s size:14];
        [self section:@"显示方式" sub:nil in:s];
        [self addRow:FMSettingsNavigationRow(@"侧边栏",@"微珠、展开菜单、透明度与动画",@"sidebar.right",UIColor.systemOrangeColor,self,@selector(openDock)) height:65 to:s];
        [self spacer:s size:16];
        [self diyPage:s];
    } else if([category isEqualToString:@"behavior"]) {
        if(FMHostUI()) {
            [self section:@"多任务" sub:@"开启后切换 App 会保留其他任务；子任务不需要单独启用微珠。" in:s];
            [self settingSwitch:s title:@"开启多任务" key:@"fullscreenMultitask" defaultValue:NO tag:19];
            [self section:@"多任务切换模式" sub:@"系统模式沿用 LC 窗口设置并隐藏微珠；微珠模式全屏切换，需要在 LC 设置中选择虚拟窗口，不会自动修改 LC 设置。" in:s];
            UISegmentedControl *mode=[[UISegmentedControl alloc] initWithItems:@[@"系统（LC）",@"微珠"]];
            mode.selectedSegmentIndex=[LCOrbitMultitask usesSystemMenu]?0:1;
            mode.enabled=[LCOrbitMultitask isEnabled];
            mode.selectedSegmentTintColor=[FMAccent() colorWithAlphaComponent:.25];
            mode.accessibilityLabel=@"多任务切换菜单";
            [mode addTarget:self action:@selector(multitaskModeChanged:) forControlEvents:UIControlEventValueChanged];
            [self addRow:mode height:38 to:s];
            [self spacer:s size:14];
        }
        [self section:@"屏幕与旋转" sub:@"开启后跟随设备自由进入横屏自适应，畅享短视频全屏播放。" in:s];
        [self settingSwitch:s title:@"开启向左横屏自适应" key:@"unlockOrientation" defaultValue:YES tag:22];
        [self spacer:s size:14];
        [self section:@"悬浮控件" sub:nil in:s];
        [self settingSwitch:s title:@"触觉反馈" key:@"haptic" defaultValue:YES tag:1];
        [self spacer:s size:14];
        [self section:@"应用切换" sub:nil in:s];
        [self settingSwitch:s title:@"最近打开的 App 置顶"
                     key:@"recentAppsFirst" defaultValue:NO tag:20];
        [self settingSwitch:s title:@"切换前二次确认" key:@"confirm" defaultValue:YES tag:2];
        [self settingSwitch:s title:@"显示重启按钮" key:@"showRestart" defaultValue:YES tag:3];
    } else if([category isEqualToString:@"apps"]) {
        [self managePage:s];
        [self spacer:s size:20];
        [self perAppPage:s];
    } else {
        [self section:@"分开查看日志" sub:nil in:s];
        [self addRow:[self rowForTitle:@"微珠运行日志" icon:@"doc.text.magnifyingglass" height:54 action:@selector(openMenuLogs)] height:54 to:s];
        [self addRow:[self rowForTitle:@"Tweak 加载日志" icon:@"externaldrive.badge.checkmark" height:54 action:@selector(openTweakLogs)] height:54 to:s];
        UILabel *hint=[self label:@"两类日志分别查看、刷新、导出和清空。Tweak 日志为已加载状态审计，无法回溯插件启动前的系统 NSLog。" size:12 weight:UIFontWeightRegular];
        hint.textColor=FMThemeColor(FMColorSecondary);
        [s addArrangedSubview:hint];
    }
}
- (void)observeAppearanceInScene:(UIWindowScene *)scene {
    if(self.appearanceScene==scene) return;
    if(@available(iOS 17.0,*)) {
        if(self.appearanceScene && self.appearanceRegistration)
            [self.appearanceScene unregisterForTraitChanges:self.appearanceRegistration];
        __weak typeof(self) weakSelf=self;
        self.appearanceRegistration=[scene registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
            withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) {
                [weakSelf queueAppearanceRefresh];
            }];
    }
    self.appearanceScene=scene;
    // A new scene may have the same system style but a different inherited UI.
    self.lastSystemStyle=UIUserInterfaceStyleUnspecified;
    self.lastMenuStyle=UIUserInterfaceStyleUnspecified;
}
- (void)queueAppearanceRefresh {
    if(self.appearanceRefreshPending) return;
    self.appearanceRefreshPending=YES;
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) manager=weakSelf;
        if(!manager) return;
        manager.appearanceRefreshPending=NO;
        [manager refreshSystemAppearance];
    });
}
- (void)refreshSystemAppearance {
    if(!self.window) return;
    FMStyleScene=self.window.windowScene;
    UIUserInterfaceStyle style=FMSystemAppearance();
    UIUserInterfaceStyle renderedStyle=FMMenuAppearance();
    UIUserInterfaceStyle override=FMMenuOverride();
    BOOL changed=style!=self.lastSystemStyle || renderedStyle!=self.lastMenuStyle ||
        self.overlayView.overrideUserInterfaceStyle!=override;
    self.lastSystemStyle=style;
    self.lastMenuStyle=renderedStyle;
    // Never allow the Guest's inherited scene trait to recolor the module.
    // Follow System is also pinned explicitly and refreshed on appearance changes.
    self.overlayView.overrideUserInterfaceStyle=override;
    if(self.settingsWindow) {
        changed=changed || self.settingsWindow.overrideUserInterfaceStyle!=override;
        self.settingsWindow.overrideUserInterfaceStyle=override;
    }
    if(!changed) return;
    if(self.settingsWindow) [self updateSettingsContent];
    else [self draw];
    FMLog(@"system-appearance",[NSString stringWithFormat:@"screen=%ld scene=%ld menu=%ld mode=%ld",
        (long)UIScreen.mainScreen.traitCollection.userInterfaceStyle,
        (long)self.window.windowScene.traitCollection.userInterfaceStyle,
        (long)renderedStyle,(long)[HostDefaults() integerForKey:Pref(@"appearanceMode")]]);
}
- (void)cancelAppearanceCheck {
    self.appearancePollGeneration++;
    self.appearancePollScheduled=NO;
}
- (void)scheduleAppearanceCheck {
    if(self.appearancePollScheduled || !self.window || !self.orbitContext ||
       UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    self.appearancePollScheduled=YES;
    NSUInteger generation=self.appearancePollGeneration;
    UIWindow *expectedWindow=self.window;
    __weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) manager=weakSelf;
        // Old jobs must never revive a new poll loop after disable or Scene replacement.
        if(!manager || manager.appearancePollGeneration!=generation ||
           manager.window!=expectedWindow || !manager.orbitContext) return;
        manager.appearancePollScheduled=NO;
        if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
        [manager refreshSystemAppearance];
        [manager scheduleAppearanceCheck];
    });
}
- (void)detachFromScene {
    [self.orbUpdateTimer invalidate];
    self.orbUpdateTimer=nil;
    self.orbUpdateLine=nil;
    [self invalidatePendingLaunch];
    [self cancelAppearanceCheck];
    if(@available(iOS 17.0,*)) {
        if(self.appearanceScene && self.appearanceRegistration)
            [self.appearanceScene unregisterForTraitChanges:self.appearanceRegistration];
    }
    self.appearanceRegistration=nil;
    self.appearanceScene=nil;
    FMStyleScene=nil;
    UIWindow *settings=self.settingsWindow;
    UIWindow *prior=self.previousKeyWindow;
    BOOL restoreKey=settings.isKeyWindow && prior && !prior.hidden &&
        prior.windowScene==settings.windowScene &&
        settings.windowScene.activationState==UISceneActivationStateForegroundActive;
    [self.orbPreviewHost removeFromSuperview];self.orbPreviewHost=nil;self.dimensionsPreview=nil;
    self.settingsWindow=nil;
    self.settingsNavigation=nil;
    self.settingsScreen=nil;
    self.settingsScroll=nil;
    // The next scene/process may create a new manager instance.
    if(self.appsScroll) [self persistAppsScroll];
    self.appsScroll=nil;
    self.appsScrollRestorePending=NO;
    self.previousKeyWindow=nil;
    settings.hidden=YES;
    settings.rootViewController=nil;
    if(restoreKey) [prior makeKeyWindow];
    [self.orbitContext.overlays unmountModule:@"FloatingMenu"];
    self.overlayView=nil;
    self.window=nil;
    self.orb=nil;
    self.panel=nil;
    self.dismissLayer=nil;
    self.isOpen=NO;
}
- (void)openDIY { [self openSettings]; }
- (void)openPerApp { [self openSettings]; }
- (void)openManage { [self openSettings]; }
- (void)backToSettings { [self openSettings]; }
- (void)backToApps { [self closeSettings]; }
- (void)settingSwitch:(UIStackView*)s title:(NSString*)title key:(NSString*)key defaultValue:(BOOL)def tag:(NSInteger)tag {
    UIView *row=[[UIView alloc] initWithFrame:CGRectMake(0,0,280,51)];
    row.backgroundColor=FMThemeColor(FMColorSurface);
    row.layer.cornerRadius=13;
    UILabel *l=[self label:title size:14 weight:UIFontWeightMedium];
    l.translatesAutoresizingMaskIntoConstraints=NO;
    l.adjustsFontSizeToFitWidth=YES;
    l.minimumScaleFactor=.79;
    [row addSubview:l];
    UISwitch *sw=[UISwitch new]; sw.on=BoolPref(key,def); sw.tag=tag;
    if(tag==19) sw.enabled=[[LCOrbitCore sharedCore] isModuleEnabled:@"FloatingMenu"];
    sw.translatesAutoresizingMaskIntoConstraints=NO;
    sw.onTintColor=FMSwitchGreen();
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [l.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-10],
        [l.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-13],
        [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];
    [self addRow:row height:51 to:s];
}
- (void)settingSlider:(UIStackView*)s title:(NSString*)title key:(NSString*)key min:(float)min max:(float)max def:(float)def tag:(NSInteger)tag {
    UILabel *l=[self label:title size:14 weight:UIFontWeightMedium];
    [s addArrangedSubview:l];
    UISlider *slider=[UISlider new];slider.minimumValue=min;slider.maximumValue=max;
    slider.value=FloatPref(key,def);slider.tag=tag;
    slider.tintColor=FMAccent();
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addRow:slider height:28 to:s];
}
- (void)note:(NSString *)text in:(UIStackView *)stack {
    UILabel *description=[self label:text size:11 weight:UIFontWeightRegular];
    description.textColor=FMThemeColor(FMColorSecondary);
    [stack addArrangedSubview:description];
}
- (void)section:(NSString *)title sub:(NSString *)sub in:(UIStackView *)stack {
    UILabel *heading=[self label:title size:14 weight:UIFontWeightSemibold];
    [stack addArrangedSubview:heading];
    if(sub.length) [self note:sub in:stack];
}
- (void)settingsPage:(UIStackView*)s {
    [self section:@"显示布局" sub:nil in:s];
    [self addRow:FMSettingsNavigationRow(@"侧边栏",@"微珠、展开菜单、透明度与动画",@"sidebar.right",UIColor.systemOrangeColor,self,@selector(openDock)) height:65 to:s];
    [self spacer:s size:8];
    [self section:@"基础交互" sub:nil in:s];
    [self settingSwitch:s title:@"最近打开的 App 置顶"
                 key:@"recentAppsFirst" defaultValue:NO tag:20];
    [self settingSwitch:s title:@"触觉反馈" key:@"haptic" defaultValue:YES tag:1];
    [self settingSwitch:s title:@"切换前二次确认" key:@"confirm" defaultValue:YES tag:2];
    [self spacer:s size:10];
    [self diyPage:s];
    [self spacer:s size:10];
    [self managePage:s];
    [self spacer:s size:10];
    [self perAppPage:s];
    [self spacer:s size:10];
    [self section:@"诊断" sub:nil in:s];
    [self addRow:[self rowForTitle:@"导出诊断日志" icon:@"square.and.arrow.up" height:44 action:@selector(exportLogs)] height:44 to:s];
    [self addRow:[self rowForTitle:@"清空日志" icon:@"trash" height:44 action:@selector(clearLogs)] height:44 to:s];
}
- (void)appearanceModeTapped:(UIControl *)sender {
    NSInteger mode=sender.tag-70;
    if(mode<0 || mode>2) return;
    SetPref(@"appearanceMode",@(mode));
    dispatch_async(dispatch_get_main_queue(), ^{
        UIUserInterfaceStyle style=FMMenuOverride();
        self.overlayView.overrideUserInterfaceStyle=style;
        if(self.settingsWindow) self.settingsWindow.overrideUserInterfaceStyle=style;
        [self draw];
        [self updateSettingsContent];
    });
}
- (void)appearanceModeControl:(UIStackView *)stack {
    UIStackView *row=[UIStackView new];
    row.axis=UILayoutConstraintAxisHorizontal;
    row.distribution=UIStackViewDistributionFillEqually;
    row.spacing=8;
    NSArray *titles=@[@"跟随系统",@"日间模式",@"夜间模式"];
    NSInteger selected=[HostDefaults() integerForKey:Pref(@"appearanceMode")];
    for(NSInteger i=0;i<3;i++) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
        button.tag=70+i;
        [button setTitle:titles[i] forState:UIControlStateNormal];
        button.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        button.layer.cornerRadius=12;
        button.layer.borderWidth=selected==i?1.5:.5;
        button.layer.borderColor=selected==i?FMAccent().CGColor:FMThemeColor(FMColorBorder).CGColor;
        button.backgroundColor=selected==i?[FMAccent() colorWithAlphaComponent:.20]:FMThemeColor(FMColorSurface);
        [button setTitleColor:FMThemeColor(FMColorText) forState:UIControlStateNormal];
        button.accessibilityTraits=UIAccessibilityTraitButton|(selected==i?UIAccessibilityTraitSelected:0);
        [button addTarget:self action:@selector(appearanceModeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:button];
    }
    [self addRow:row height:44 to:stack];
}
- (void)themeColorChanged:(UIColorWell *)well {
    BOOL dark=well.tag==201;
    NSString *hex=FMHex(well.selectedColor);
    if(!hex) return;
    NSArray *before=FMSettingsPalette();
    SetPref(dark?@"accentDark":@"accentLight",hex);
    if(self.settingsWindow) {
        NSArray *after=FMSettingsPalette();
        self.settingsWindow.backgroundColor=FMThemeColor(FMColorBackground);
        FMApplyNavigationTheme(self.settingsNavigation);
        for(UIViewController *controller in self.settingsNavigation.viewControllers)
            if(controller.isViewLoaded) FMRefreshSettingsColors(controller.view,before,after);
        [self refreshOrbPreview];
    } else [self draw];
    FMLog(@"theme-color",[NSString stringWithFormat:@"%@=%@",dark?@"dark":@"light",hex]);
}
- (void)customThemeColorRow:(UIStackView *)stack title:(NSString *)title dark:(BOOL)dark {
    UIView *row=[UIView new];
    row.backgroundColor=FMThemeColor(FMColorSurface);
    row.layer.cornerRadius=13;
    UILabel *label=[self label:title size:14 weight:UIFontWeightMedium];
    label.translatesAutoresizingMaskIntoConstraints=NO;
    [row addSubview:label];
    UIColorWell *well=[UIColorWell new];
    well.translatesAutoresizingMaskIntoConstraints=NO;
    well.title=title;
    well.tag=dark?201:200;
    well.supportsAlpha=NO;
    well.selectedColor=FMAccentFor(dark);
    [well addTarget:self action:@selector(themeColorChanged:)
      forControlEvents:UIControlEventValueChanged];
    [row addSubview:well];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [well.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [well.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [well.widthAnchor constraintEqualToConstant:64],
        [well.heightAnchor constraintEqualToConstant:42],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:well.leadingAnchor constant:-8]
    ]];
    if(dark) self.darkColorWell=well; else self.lightColorWell=well;
    [self addRow:row height:54 to:stack];
}
- (void)diyPage:(UIStackView*)s {
    [self section:@"自定义主题配色"
        sub:@"日间与夜间分别选择颜色，菜单会自动生成配套颜色。" in:s];
    [self customThemeColorRow:s title:@"日间主题色" dark:NO];
    [self customThemeColorRow:s title:@"夜间主题色" dark:YES];
}
- (void)openDock {
    [self.settingsNavigation pushViewController:[FMDockSettingsController new] animated:YES];
}
// Everything the sidebar page edits, back to its default.
- (void)resetDockSettings {
    for(NSDictionary *option in FMOrbStyleOptions()) SetPref(option[@"key"],option[@"default"]);
    for(NSDictionary *option in FMMenuStyleOptions()) SetPref(option[@"key"],option[@"default"]);
    SetPref(@"orbHandleStyle",@0);SetPref(@"orbScale",@(1.0));
    SetPref(@"idleAlpha",@(.72));SetPref(@"idleFade",@YES);
    SetPref(@"compactMode",@NO);SetPref(@"panelScale",@(1.0));
    SetPref(@"popAnimation",@0);SetPref(@"iconFrame",@YES);SetPref(@"glowLine",@YES);
    SetPref(@"glassTint",@(0));SetPref(@"clearGlass",@NO);
}

- (void)pinApp:(UIControl *)button {
    NSDictionary *app=objc_getAssociatedObject(button,@selector(pinApp:));
    NSString *path=FMAppKey(app);
    if(!path.length) return;
    NSMutableArray *pins=[[self favorites] mutableCopy];
    if([pins containsObject:path] || [pins containsObject:app[@"path"]]) {
        [pins removeObject:path];[pins removeObject:app[@"path"]];
    }
    else {
        if(pins.count>=4) {
            [self showMessage:@"常用应用已满" details:@"最多固定 4 个应用，请先取消一个固定项。"];
            return;
        }
        [pins addObject:path];
    }
    SetPref(@"favoritePaths",pins);
    [self refreshUI];
}
- (void)removeFavorite:(UIControl *)button {
    NSString *key=objc_getAssociatedObject(button,@selector(removeFavorite:));
    if(!key.length) return;
    NSMutableArray *pins=[[self favorites] mutableCopy];
    if(![pins containsObject:key]) return;
    [pins removeObject:key];
    SetPref(@"favoritePaths",pins);
    [self refreshUI];
}
- (void)promoteApp:(UIControl *)button {
    NSDictionary *app=objc_getAssociatedObject(button,@selector(promoteApp:));
    NSArray *items=[self visibleApps];
    NSMutableArray *order=[NSMutableArray array];
    for(NSDictionary *item in items) [order addObject:FMAppKey(item)];
    NSUInteger index=[order indexOfObject:FMAppKey(app)];
    if(index!=NSNotFound && index>0) {
        [order exchangeObjectAtIndex:index withObjectAtIndex:index-1];
        SetPref(@"menuOrder",order);
    }
    [self draw];
}
- (void)sortDrag:(UILongPressGestureRecognizer *)gesture {
    if(!self.manageRows.count) return;
    UIView *sourceRow=gesture.view;
    NSDictionary *app=objc_getAssociatedObject(sourceRow,@selector(sortDrag:));
    if(!app || ![sourceRow.superview isKindOfClass:UIStackView.class]) return;
    UIStackView *group=(UIStackView *)sourceRow.superview;
    NSMutableDictionary *state=objc_getAssociatedObject(gesture,@selector(sortDrag:));
    CGPoint finger=[gesture locationInView:group];
    if(gesture.state==UIGestureRecognizerStateBegan) {
        [group layoutIfNeeded];
        NSUInteger original=[group.arrangedSubviews indexOfObjectIdenticalTo:sourceRow];
        if(original==NSNotFound) return;
        UIView *lifted=[sourceRow snapshotViewAfterScreenUpdates:NO];
        if(!lifted) {
            // Detached/transitioning UIKit views can return nil here. Draw
            // the row into an image so the drag still has a lifted surface.
            UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]
                initWithSize:sourceRow.bounds.size];
            UIImage *snapshot=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
                [sourceRow.layer renderInContext:context.CGContext];
            }];
            lifted=[[UIImageView alloc] initWithImage:snapshot];
        }
        lifted.frame=sourceRow.frame;
        lifted.userInteractionEnabled=NO;
        lifted.layer.cornerRadius=13;
        lifted.layer.masksToBounds=NO;
        lifted.layer.shadowColor=UIColor.blackColor.CGColor;
        lifted.layer.shadowOpacity=.20;
        lifted.layer.shadowRadius=11;
        lifted.layer.shadowOffset=CGSizeMake(0,5);
        // Keep the original arranged row in the stack as a real 68pt slot.
        // Only its contents are hidden: moving that slot makes neighbors
        // animate away and leaves a clearly visible destination vacancy.
        for(UIView *child in sourceRow.subviews) child.alpha=0;
        sourceRow.backgroundColor=[FMAccent() colorWithAlphaComponent:.095];
        sourceRow.layer.cornerRadius=12;
        sourceRow.layer.borderWidth=.9;
        sourceRow.layer.borderColor=[FMAccent() colorWithAlphaComponent:.36].CGColor;
        [group addSubview:lifted];
        [group bringSubviewToFront:lifted];
        state=[@{@"group":group,@"lifted":lifted,
                 @"startY":@(finger.y),@"centerY":@(CGRectGetMidY(sourceRow.frame)),
                 @"original":@(original),@"index":@(original)} mutableCopy];
        objc_setAssociatedObject(gesture,@selector(sortDrag:),state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(BoolPref(@"haptic",YES))
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        FMLog(@"menu-reorder-start",FMAppKey(app));
    } else if(gesture.state==UIGestureRecognizerStateChanged && state) {
        UIView *lifted=state[@"lifted"];
        CGFloat y=[state[@"centerY"] doubleValue]+finger.y-[state[@"startY"] doubleValue];
        lifted.center=CGPointMake(CGRectGetMidX(sourceRow.frame),y);
        // Compute insertion against real, untransformed row frames, rather
        // than against the floating snapshot. The vacancy travels live.
        NSUInteger destination=0;
        for(UIView *row in group.arrangedSubviews) {
            if(row==sourceRow) continue;
            if(y>CGRectGetMidY(row.frame)) destination++;
        }
        if(destination!=[state[@"index"] unsignedIntegerValue]) {
            [group layoutIfNeeded];
            [group insertArrangedSubview:sourceRow atIndex:destination];
            state[@"index"]=@(destination);
            [UIView animateWithDuration:.23 delay:0
                options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseInOut
                animations:^{ [group layoutIfNeeded]; }
                completion:nil];
            // A subtle tick signals the slot has moved, not every frame.
            if(BoolPref(@"haptic",YES))
                [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        }
    } else if(gesture.state==UIGestureRecognizerStateEnded ||
              gesture.state==UIGestureRecognizerStateCancelled ||
              gesture.state==UIGestureRecognizerStateFailed) {
        BOOL cancelled=gesture.state!=UIGestureRecognizerStateEnded;
        NSArray *items=[self visibleApps];
        NSUInteger from=[items indexOfObject:app];
        NSUInteger destination=from;
        if(state) {
            NSUInteger index=[state[@"index"] unsignedIntegerValue];
            destination=cancelled?[state[@"original"] unsignedIntegerValue]:index;
            if(cancelled && destination!=index) {
                [group layoutIfNeeded];
                [group insertArrangedSubview:sourceRow atIndex:destination];
                [UIView animateWithDuration:.20 delay:0
                    options:UIViewAnimationOptionBeginFromCurrentState
                    animations:^{ [group layoutIfNeeded]; } completion:nil];
            }
        } else if(!cancelled) {
            // Also support interruption/recovery if a recognizer has no
            // matching Began callback; never leave the app unmovable.
            UIView *surface=self.settingsNavigation.topViewController.view ?: self.panel;
            if(!surface) return;
            CGPoint location=[gesture locationInView:surface];
            NSUInteger insertion=0;
            for(NSUInteger i=0;i<self.manageRows.count;i++) {
                if(i==from) continue;
                UIView *row=self.manageRows[i];
                CGRect rect=[row convertRect:row.bounds toView:surface];
                if(location.y>CGRectGetMidY(rect)) insertion=i+1;
            }
            destination=insertion>from?insertion-1:insertion;
        }
        if(!cancelled && from!=NSNotFound && destination!=NSNotFound &&
           destination<items.count && from!=destination) {
            NSMutableArray *order=[NSMutableArray arrayWithCapacity:items.count];
            for(NSDictionary *item in items) [order addObject:FMAppKey(item)];
            NSString *moving=order[from];
            [order removeObjectAtIndex:from];
            [order insertObject:moving atIndex:destination];
            SetPref(@"menuOrder",order);
            FMLog(@"menu-reordered",@"animated-slot");
        }
        if(state) {
            UIView *lifted=state[@"lifted"];
            objc_setAssociatedObject(gesture,@selector(sortDrag:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [group layoutIfNeeded];
            [UIView animateWithDuration:.22 delay:0
                options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseOut
                animations:^{
                    lifted.frame=sourceRow.frame;
                    lifted.alpha=.93;
                } completion:^(BOOL finished) {
                    [lifted removeFromSuperview];
                    for(UIView *child in sourceRow.subviews) child.alpha=1;
                    sourceRow.backgroundColor=UIColor.clearColor;
                    sourceRow.layer.borderWidth=0;
                    sourceRow.layer.borderColor=nil;
                    sourceRow.layer.cornerRadius=0;
                    [self refreshUI];
                }];
        } else if(!cancelled) [self refreshUI];
    }
}
- (void)managePage:(UIStackView*)stack {
    BOOL hostUI=FMHostUI();
    [self section:@"应用列表" sub:hostUI?
        @"左侧圆圈收藏 · 长按整行排序 · 右侧开关控制离开 LC 自动画中画":
        @"左侧圆圈收藏 · 长按整行排序" in:stack];
    NSArray<NSDictionary*> *apps=[self visibleApps];
    NSArray<NSString *> *pins=[self favorites];
    self.manageRows=[NSMutableArray arrayWithCapacity:apps.count];
    UIStackView *group=[UIStackView new];
    group.axis=UILayoutConstraintAxisVertical;
    group.alignment=UIStackViewAlignmentFill;
    group.distribution=UIStackViewDistributionFill;
    group.spacing=0;
    group.backgroundColor=FMThemeColor(FMColorSurface);
    group.layer.cornerRadius=17;
    // Don't clip a lifted row during the full-row drag gesture.
    group.clipsToBounds=NO;
    [stack addArrangedSubview:group];
    for(NSUInteger i=0;i<apps.count;i++) {
        NSDictionary *app=apps[i];
        BOOL showsAutoPiP=hostUI && ![app[@"builtin"] boolValue];
        UIView *row=[UIView new];
        row.backgroundColor=UIColor.clearColor;
        [row.heightAnchor constraintEqualToConstant:68].active=YES;
        [group addArrangedSubview:row];
        // Selected circular control = favorite. The four-favorite limit and
        // scoped private/shared identity are handled by the existing pinApp:.
        BOOL favored=[pins containsObject:FMAppKey(app)] || [pins containsObject:app[@"path"]];
        UIButton *selection=[UIButton buttonWithType:UIButtonTypeSystem];
        selection.translatesAutoresizingMaskIntoConstraints=NO;
        UIImageSymbolConfiguration *circleStyle=[UIImageSymbolConfiguration
            configurationWithPointSize:17 weight:UIImageSymbolWeightLight];
        [selection setImage:[UIImage systemImageNamed:favored?@"checkmark.circle":@"circle"
                                   withConfiguration:circleStyle] forState:UIControlStateNormal];
        selection.tintColor=favored?FMAccent():FMThemeColor(FMColorSecondary);
        selection.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",
            app[@"title"]?:@"App",favored?@"已收藏，点击取消":@"未收藏，点击收藏"];
        selection.accessibilityTraits=UIAccessibilityTraitButton|
            (favored?UIAccessibilityTraitSelected:0);
        objc_setAssociatedObject(selection,@selector(pinApp:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [selection addTarget:self action:@selector(pinApp:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:selection];
        UIView *icon=[self iconViewForApp:app size:42];
        icon.translatesAutoresizingMaskIntoConstraints=NO;
        icon.userInteractionEnabled=NO;
        [row addSubview:icon];
        UILabel *name=[self label:app[@"title"] size:15 weight:UIFontWeightMedium];
        name.translatesAutoresizingMaskIntoConstraints=NO;
        name.numberOfLines=1;
        name.lineBreakMode=NSLineBreakByTruncatingTail;
        [row addSubview:name];
        [NSLayoutConstraint activateConstraints:@[
            [selection.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:9],
            [selection.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [selection.widthAnchor constraintEqualToConstant:42],
            [selection.heightAnchor constraintEqualToConstant:54],
            [icon.leadingAnchor constraintEqualToAnchor:selection.trailingAnchor constant:5],
            [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:42],
            [icon.heightAnchor constraintEqualToConstant:42],
            [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:11],
            [name.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-16]
        ]];
        if(showsAutoPiP) {
            UISwitch *control=[UISwitch new];
            control.translatesAutoresizingMaskIntoConstraints=NO;
            control.onTintColor=FMSwitchGreen();
            control.on=[LCOrbitMultitask automaticPiPEnabledForGuest:app];
            NSString *title=app[@"title"]?:app[@"path"]?:@"App";
            control.accessibilityLabel=[title stringByAppendingString:@"，离开 LC 自动画中画"];
            [control setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisHorizontal];
            objc_setAssociatedObject(control,@selector(automaticPiPChanged:),app,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [control addTarget:self action:@selector(automaticPiPChanged:)
                forControlEvents:UIControlEventValueChanged];
            [row addSubview:control];
            [NSLayoutConstraint activateConstraints:@[
                [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-15],
                [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
                [name.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-10]
            ]];
        }
        UILongPressGestureRecognizer *drag=[[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(sortDrag:)];
        drag.minimumPressDuration=.35;
        drag.cancelsTouchesInView=YES;
        [row addGestureRecognizer:drag];
        objc_setAssociatedObject(row,@selector(sortDrag:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        row.accessibilityIdentifier=[@"fm.manage.row." stringByAppendingString:FMAppKey(app)];
        if(i+1<apps.count) {
            UIView *divider=[UIView new];
            divider.translatesAutoresizingMaskIntoConstraints=NO;
            divider.backgroundColor=[FMThemeColor(FMColorBorder) colorWithAlphaComponent:.38];
            [row addSubview:divider];
            [NSLayoutConstraint activateConstraints:@[
                [divider.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
                [divider.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
                [divider.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
                [divider.heightAnchor constraintEqualToConstant:.5]
            ]];
        }
        [self.manageRows addObject:row];
    }
    if(!apps.count) {
        UILabel *empty=[self label:@"暂无可管理的应用" size:14 weight:UIFontWeightRegular];
        empty.textColor=FMThemeColor(FMColorSecondary);
        empty.textAlignment=NSTextAlignmentCenter;
        [self addRow:empty height:64 to:group];
    }
    NSArray<NSString *> *missing=[self unavailableFavorites];
    if(missing.count) {
        [self spacer:stack size:12];
        [self section:@"未显示的收藏"
            sub:@"以下收藏未出现在当前应用列表中，仍保留原标识。轻触可取消收藏并释放名额。" in:stack];
        for(NSString *key in missing) {
            UIView *row=[self rowForTitle:key icon:@"star.slash" height:54 action:@selector(removeFavorite:)];
            row.accessibilityLabel=[@"取消收藏 " stringByAppendingString:key];
            objc_setAssociatedObject(row,@selector(removeFavorite:),key,OBJC_ASSOCIATION_COPY_NONATOMIC);
            [self addRow:row height:54 to:stack];
        }
    }
}

- (void)perAppPage:(UIStackView*)s {
    [self section:FMHostUI()?@"LC 主界面独立设置":@"当前 App 独立设置" sub:GuestID() in:s];
    [self settingSwitch:s title:@"启用独立设置" key:[@"override." stringByAppendingString:GuestID()] defaultValue:NO tag:7];
    [self spacer:s size:4];
    [self section:@"外观与位置" sub:nil in:s];
    [self settingSlider:s title:@"当前 App 微珠透明度" key:[@"appAlpha." stringByAppendingString:GuestID()] min:.20 max:1 def:FloatPref(@"idleAlpha",.72) tag:12];
    [self settingSwitch:s title:@"双击展开（游戏防误触）" key:[@"doubleTap." stringByAppendingString:GuestID()] defaultValue:NO tag:8];
    [self spacer:s size:4];
    [self section:@"单任务切换行为" sub:nil in:s];
    [self settingSwitch:s title:@"当前 App 切换前确认" key:AppPref() defaultValue:BoolPref(@"confirm",YES) tag:4];

}
- (void)automaticPiPChanged:(UISwitch *)control {
    NSDictionary *app=objc_getAssociatedObject(control,@selector(automaticPiPChanged:));
    NSError *error=nil;
    if(!app || ![LCOrbitMultitask setAutomaticPiPEnabled:control.isOn forGuest:app error:&error]) {
        control.on=app?[LCOrbitMultitask automaticPiPEnabledForGuest:app]:NO;
        [self showMessage:@"设置未保存" details:error.localizedDescription?:@"无法设置此 App 的自动画中画。"];
    }
}
- (void)multitaskModeChanged:(UISegmentedControl *)control {
    NSError *error=nil;
    BOOL bead=control.selectedSegmentIndex==1;
    if(![LCOrbitMultitask setUseSystemMenu:!bead error:&error]) {
        control.selectedSegmentIndex=[LCOrbitMultitask usesSystemMenu]?0:1;
        [self showMessage:@"无法切换多任务菜单" details:error.localizedDescription?:@"当前 LC 不支持此功能。"];
    } else {
        FMLog(@"multitask-mode",bead?@"bead-fullscreen":@"lc-system");
        [self refreshUI];
    }
}
- (void)switchChanged:(UISwitch*)sw {
    if(sw.tag==19) {
        NSError *error=nil;
        if(![LCOrbitMultitask setEnabled:sw.isOn error:&error]) {
            sw.on=[LCOrbitMultitask isEnabled];
            [self showMessage:@"无法调整多任务" details:error.localizedDescription];
        }
        [self refreshUI];return;
    }
    NSString *key=nil;
    switch(sw.tag) {
        case 1:key=@"haptic";break;
        case 2:key=@"confirm";break;
        case 3:key=@"showRestart";break;
        case 7:key=[@"override." stringByAppendingString:GuestID()];break;
        case 8:key=[@"doubleTap." stringByAppendingString:GuestID()];break;
        case 20:key=@"recentAppsFirst";break;
        case 22:key=@"unlockOrientation";break;
        case 4:key=AppPref();break;
        default:return;
    }
    SetPref(key,@(sw.isOn));
    if(sw.tag==20) {
        if(sw.isOn) { self.appsScrollOffset=0; [self rememberCurrentApp]; }
        FMLog(@"recent-apps-first",sw.isOn?@"on":@"off");
    }
    if(sw.tag==3||sw.tag==7||sw.tag==8) [self draw];
}
// The per-app bead opacity slider.
- (void)sliderChanged:(UISlider*)slider {
    if(slider.tag!=12) return;
    SetPref([@"appAlpha." stringByAppendingString:GuestID()],@(slider.value));
    [self refreshOrbPreview];
    CGFloat alpha=BoolPref([@"override." stringByAppendingString:GuestID()],NO)?
        FloatPref([@"appAlpha." stringByAppendingString:GuestID()],FloatPref(@"idleAlpha",.72)):
        FloatPref(@"idleAlpha",.72);
    self.orb.alpha=alpha;
}
- (void)openMenuLogs {
    if(!self.settingsNavigation) return;
    [self.settingsNavigation pushViewController:[[LCOrbitLogViewer alloc] initWithTweakAudit:NO] animated:YES];
}
- (void)openTweakLogs {
    if(!self.settingsNavigation) return;
    [self.settingsNavigation pushViewController:[[LCOrbitLogViewer alloc] initWithTweakAudit:YES] animated:YES];
}
- (void)exportLogs {
    FMLog(@"diagnostics-export",@"user-requested");
    NSData *content=[LCOrbitLog dataForKind:@"runtime"];
    NSString *out=[NSTemporaryDirectory() stringByAppendingPathComponent:@"LCOrbit-Runtime.json"];
    if(![content writeToFile:out atomically:YES]) {
        [self showMessage:@"导出失败" details:@"无法准备诊断文件"];
        return;
    }
    UIViewController *presenter=self.settingsNavigation.topViewController ?: self.window.rootViewController;
    if(presenter.presentedViewController) return;
    UIActivityViewController *share=[[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:out]] applicationActivities:nil];
    UIPopoverPresentationController *popover=share.popoverPresentationController;
    if(popover) {
        popover.sourceView=presenter.view;
        popover.sourceRect=CGRectMake(CGRectGetMidX(presenter.view.bounds), 80, 1, 1);
    }
    [presenter presentViewController:share animated:YES completion:nil];
}
- (void)clearLogs {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清空诊断日志？"
        message:@"只会清除悬浮菜单日志，不影响 App 或设置。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [LCOrbitLog clearKind:@"runtime"];
    }]];
    UIViewController *presenter=self.settingsNavigation.topViewController ?: self.window.rootViewController;
    if(!presenter.presentedViewController)
        [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)appendResetStyleRow:(UIStackView *)stack {
    [self appendResetRow:stack title:@"恢复默认设置" action:@selector(resetStyle)];
}
- (void)appendResetRow:(UIStackView *)stack title:(NSString *)title action:(SEL)action {
    UIView *row=[UIView new];
    row.backgroundColor=FMThemeColor(FMColorSurface);
    row.layer.cornerRadius=16;
    UIControl *button=[UIControl new];
    button.translatesAutoresizingMaskIntoConstraints=NO;
    [row addSubview:button];
    
    UIView *badge=[UIView new];
    badge.translatesAutoresizingMaskIntoConstraints=NO;
    badge.layer.cornerRadius=8;
    badge.layer.masksToBounds=YES;
    badge.backgroundColor=[UIColor colorWithRed:255/255.0 green:149/255.0 blue:0/255.0 alpha:1.0];
    [button addSubview:badge];
    
    UIImageView *symbol=[[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:@"arrow.counterclockwise"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    symbol.translatesAutoresizingMaskIntoConstraints=NO;
    symbol.tintColor=UIColor.whiteColor;
    symbol.contentMode=UIViewContentModeScaleAspectFit;
    [badge addSubview:symbol];
    
    UILabel *label=[self label:title size:16 weight:UIFontWeightMedium];
    label.translatesAutoresizingMaskIntoConstraints=NO;
    [button addSubview:label];
    
    [NSLayoutConstraint activateConstraints:@[
        [button.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [button.topAnchor constraintEqualToAnchor:row.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [badge.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:14],
        [badge.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:32],
        [badge.heightAnchor constraintEqualToConstant:32],
        [symbol.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [symbol.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [symbol.widthAnchor constraintEqualToConstant:19],
        [symbol.heightAnchor constraintEqualToConstant:19],
        [label.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:13],
        [label.centerYAnchor constraintEqualToAnchor:button.centerYAnchor]
    ]];
    button.accessibilityLabel=title;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addRow:row height:65 to:stack];
}
- (void)resetStyle {
    [self resetDockSettings];
    SetPref(@"showRestart",@YES);SetPref(@"haptic",@YES);
    SetPref(@"recentAppsFirst",@NO);
    SetPref(@"appearanceMode",@(0));
    SetPref(@"unlockOrientation",@YES);
    for(NSString *key in @[@"accentLight",@"accentDark",@"theme",@"preferDarkIcons",@"orbWidth"]) {
        [HostDefaults() removeObjectForKey:Pref(key)];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIUserInterfaceStyle skin=FMMenuOverride();
        self.overlayView.overrideUserInterfaceStyle=skin;
        if(self.settingsWindow) self.settingsWindow.overrideUserInterfaceStyle=skin;
        [self refreshUI];
    });
}
- (void)invalidatePendingLaunch {
    self.launchGeneration++;
    self.launchPending=NO;
}
- (void)launchApp:(NSDictionary *)app {
    UIWindowScene *scene=self.settingsWindow.windowScene?:self.window.windowScene;
    LCOrbitContext *context=self.orbitContext;
    if(self.launchPending || !context || !scene ||
       ![[LCOrbitCore sharedCore] isModuleEnabled:@"FloatingMenu"] ||
       scene.activationState!=UISceneActivationStateForegroundActive ||
       UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    // Reserve before sharing (and before publishing events that may reenter).
    // A mode change must cancel this request rather than choose a new backend.
    NSUInteger generation=++self.launchGeneration;
    self.launchPending=YES;
    BOOL multitask=[LCOrbitMultitask isEnabled],systemMenu=[LCOrbitMultitask usesSystemMenu];
    self.launchMultitaskMode=multitask;
    self.launchSystemMenuMode=systemMenu;
    BOOL hostUI=FMHostUI();
    NSString *guestID=[GuestID() copy]?:@"";
    NSDictionary *target=[app copy];
    // Persist before launch: classic switching may destroy this Guest process.
    [self persistAppsScroll];
    FMLog(@"switch-request",FMAppKey(target));
    [context.events publish:@"orbit.guest.switchRequested"
        payload:@{@"target":FMAppKey(target),@"guestID":guestID}];
    __weak typeof(self) weakSelf=self;
    FMSyncSharedTweaks(^{
        typeof(self) manager=weakSelf;
        if(!manager || manager.launchGeneration!=generation || !manager.launchPending) return;
        UIWindowScene *currentScene=manager.settingsWindow.windowScene?:manager.window.windowScene;
        if(manager.orbitContext!=context || currentScene!=scene ||
           scene.activationState!=UISceneActivationStateForegroundActive ||
           UIApplication.sharedApplication.applicationState!=UIApplicationStateActive ||
           ![[LCOrbitCore sharedCore] isModuleEnabled:@"FloatingMenu"] ||
           [LCOrbitMultitask isEnabled]!=multitask || [LCOrbitMultitask usesSystemMenu]!=systemMenu ||
           FMHostUI()!=hostUI || ![(GuestID()?:@"") isEqualToString:guestID]) {
            [manager invalidatePendingLaunch];
            FMLog(@"switch-cancelled",@"launch-context-changed");
            return;
        }
        NSError *error=nil;
        BOOL accepted=[LCOrbitGuestService launchGuest:target error:&error];
        if(manager.launchGeneration!=generation) return;
        manager.launchPending=NO;
        if(!accepted) {
            FMLog(@"switch-rejected",error.localizedDescription);
            [manager showMessage:@"暂不可切换" details:error.localizedDescription];
            return;
        }
        FMRememberOpenedApp(target);
        FMLog(@"switch-accepted",multitask?@"host-multitask":@"classic");
        manager.isOpen=NO;[manager draw];
    });
}
- (void)showMultitaskMenuExpanded:(BOOL)expanded {
    if(![LCOrbitMultitask isEnabled]) return;
    [self installIfPossible];
    if(!self.window || self.settingsWindow) return;
    if([LCOrbitMultitask usesSystemMenu]) { [self draw];return; }
    self.apps=InstalledApps();self.page=@"apps";
    [self rememberCurrentApp];
    if(expanded && !self.isOpen) {
        [self loadAppsScroll];
        self.isOpen=YES;
    }
    if(self.isOpen && self.appsScroll && self.panel) [self requestAppsRefresh];
    else [self draw];
}
- (void)launchPath:(NSString *)path uuid:(NSString *)uuid {
    [self persistAppsScroll];
    FMLog(@"switch-request",[path isEqualToString:@"ui"]?@"return-home":@"new-guest");
    if(![path isEqualToString:@"ui"] &&
       ![LCOrbitGuestService isEligibleGuestPath:path uuid:uuid]) {
        FMLog(@"switch-rejected",@"guest-ineligible");
        [self showMessage:@"不可安全切换" details:@"目标 App 不存在、已锁定、需要 JIT，或补丁需要在 LC 中重新签名。请先返回 LC 启动。"];
        return;
    }
    [self.orbitContext.events publish:@"orbit.guest.switchRequested"
                          payload:@{@"target":path,@"guestID":GuestID()}];
    NSError *error=nil;
    // The service revalidates eligibility before invoking LC's launcher.
    if(![LCOrbitGuestService launchGuestPath:path uuid:uuid error:&error]) {
        FMLog(@"switch-rejected",error.domain?:@"unknown");
        NSString *title=error.code==LCOrbitGuestErrorIneligible?@"不可安全切换":@"切换失败";
        [self showMessage:title details:error.localizedDescription?:@"启动失败"];
        return;
    }
    if(![path isEqualToString:@"ui"]) for(NSDictionary *app in self.apps) {
        if([app[@"path"] isEqualToString:path] && [app[@"uuid"] isEqualToString:uuid]) {
            FMRememberOpenedApp(app);break;
        }
    }
    FMLog(@"switch-accepted",@"LCOrbitGuestService");
}
- (void)showMessage:(NSString *)title details:(NSString *)detail {
    FMLog(@"ui-warning",title);
    UIViewController *presenter=self.settingsNavigation.topViewController ?: self.window.rootViewController;
    if(!presenter.presentedViewController) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    }
}
- (void)confirmTitle:(NSString*)title action:(void(^)(void))action {
    BOOL independent=BoolPref([@"override." stringByAppendingString:GuestID()],NO);
    BOOL confirm=independent?BoolPref(AppPref(),BoolPref(@"confirm",YES)):BoolPref(@"confirm",YES);
    if(!confirm) {action();return;}
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title
        message:([LCOrbitMultitask isEnabled] && ![title containsString:@"SideStore"])?
            @"将打开或切回目标任务，其他任务继续保留。":@"经典单任务切换会结束当前 App 的内存状态；请先保存进度。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){action();}]];
    if(!self.window.rootViewController.presentedViewController)
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)openBuiltinSideStore {
    [self persistAppsScroll];
    NSError *error=nil;
    if(![LCOrbitGuestService launchBuiltInSideStoreWithError:&error]) {
        FMLog(@"sidestore-failed",error.domain?:@"unknown");
        NSString *title=error.code==LCOrbitGuestErrorSideStoreMissing?@"SideStore 不可用":@"切换失败";
        [self showMessage:title details:error.localizedDescription?:@"SideStore 启动失败"];
        return;
    }
    FMLog(@"sidestore-launch",@"one-shot builtinSideStore selected token");
}
- (void)compactReturnHome {
    // Compact mode has one explicit Home action. Never treat it as a
    // collapse-only control or ask for the standard-mode confirmation.
    [self persistAppsScroll];
    FMLog(@"compact-home",FMHostUI()?@"host":@"guest");
    if([LCOrbitMultitask isEnabled]) {
        [LCOrbitMultitask showHome];
        self.isOpen=NO;
        [self draw];
        return;
    }
    if(FMHostUI()) {
        // The host already displays LC's home; dismiss the drawer.
        if(self.isOpen) [self toggle];
        return;
    }
    [self launchPath:@"ui" uuid:nil];
}
- (void)goHome {
    if([LCOrbitMultitask isEnabled]) {
        [LCOrbitMultitask showHome];self.isOpen=NO;[self draw];return;
    }
    if(FMHostUI()) { [self toggle]; return; }
    [self confirmTitle:@"返回 LiveContainer？" action:^{[self launchPath:@"ui" uuid:nil];}];
}
- (void)closeApp:(NSDictionary *)app sender:(UIControl *)sender collapse:(BOOL)collapse {
    NSDictionary *target=[app copy];
    if(!target || ![LCOrbitMultitask isRunningGuest:target]) {
        FMLog(@"task-close-rejected",@"not-running-or-stale");
        [self showMessage:@"任务未运行" details:@"应用已退出或运行状态已变化，没有关闭其他任务。"];
        return;
    }
    [self persistAppsScroll];
    NSError *error=nil;
    if(![LCOrbitMultitask closeGuest:target error:&error]) {
        FMLog(@"task-close-rejected",error.localizedDescription?:@"unknown");
        [self showMessage:@"关闭任务失败" details:error.localizedDescription?:@"请稍后重试。"];
        return;
    }
    sender.enabled=NO;
    FMLog(@"task-close-requested",FMAppKey(target));
    if(collapse) { self.isOpen=NO;[self draw]; }
}
- (void)closeTaskFromButton:(UIControl *)sender {
    NSDictionary *app=objc_getAssociatedObject(sender,@selector(closeTaskFromButton:));
    [self closeApp:app sender:sender collapse:NO];
}
- (void)closePictureInPicture {
    NSError *error=nil;
    if(![LCOrbitMultitask stopPiPIfActive:&error]) {
        FMLog(@"pip-close-rejected",error.localizedDescription?:@"not-active");
        [self showMessage:@"关闭画中画失败" details:error.localizedDescription?:@"画中画可能已经结束。"];
        return;
    }
    FMLog(@"pip-close-requested",nil);
    self.isOpen=NO;
    [self draw];
}
- (void)closeMultitaskGuest {
    for(NSDictionary *app in self.apps)
        if([LCOrbitMultitask isCurrentGuest:app]) {
            [self closeApp:app sender:nil collapse:YES];return;
        }
    [self showMessage:@"没有当前任务" details:@"先从微珠打开或切回一个 App。"];
}
- (void)restart {
    if(FMHostUI()) return;
    for(NSDictionary *app in self.apps) {
        if([LCOrbitGuestService isCurrentGuest:app]) {
            NSDictionary *target=app;
            [self confirmTitle:@"重新启动当前 App？" action:^{
                [self launchApp:target];
            }];
            return;
        }
    }
}
- (void)switchFromRow:(UIControl *)sender {
    NSDictionary *app=objc_getAssociatedObject(sender,@selector(switchFromRow:));
    if(!app || [LCOrbitGuestService isCurrentGuest:app]) return;
    if(![app[@"builtin"] boolValue] && ![app[@"launchable"] boolValue]) {
        [self showMessage:@"暂不可切换" details:app[@"status"] ?: @"请从 LC 启动。"];
        return;
    }
    if([app[@"builtin"] boolValue]) {
        [self confirmTitle:@"切换到 SideStore？" action:^{ [self openBuiltinSideStore]; }];
        return;
    }
    [self confirmTitle:[NSString stringWithFormat:@"切换到 %@？",app[@"title"]] action:^{
        [self launchApp:app];
    }];
}
@end

// Inset-grouped iOS settings home, separate from the in-Guest switcher.
@implementation FMSettingsRootController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"悬浮菜单";
    self.view.backgroundColor=FMThemeColor(FMColorBackground);
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.backgroundColor=UIColor.clearColor;
    scroll.alwaysBounceVertical=YES;
    scroll.showsVerticalScrollIndicator=YES;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    self.contentScroll=scroll;
    __weak typeof(self) weakSelf=self;
    self.updateReleaseObserver=[NSNotificationCenter.defaultCenter addObserverForName:FMUpdateReleaseAvailable
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weakSelf tryAutomaticUpdatePrompt];
        }];
    self.updateActivationObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weakSelf tryAutomaticUpdatePrompt];
        }];
    [self rebuild];
}
- (UIControl *)navigationRow:(NSString *)name subtitle:(NSString *)subtitle
                     symbol:(NSString *)symbol badgeColor:(UIColor *)badgeColor action:(SEL)action {
    UIControl *row=FMSettingsNavigationRow(name,subtitle,symbol,badgeColor,self,action);
    if(action==@selector(checkForUpdates)) self.updateStatusLabel=(UILabel *)[row viewWithTag:9235];
    return row;
}
- (void)openRepository {
    NSURL *url=[NSURL URLWithString:FMRepositoryURL];
    if(url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
- (void)dealloc {
    if(self.updateReleaseObserver) [NSNotificationCenter.defaultCenter removeObserver:self.updateReleaseObserver];
    if(self.updateActivationObserver) [NSNotificationCenter.defaultCenter removeObserver:self.updateActivationObserver];
}
- (BOOL)isSettingsRootVisible {
    return self.isViewLoaded && self.view.window && !self.view.window.hidden &&
        self.navigationController.topViewController==self && !self.isBeingDismissed &&
        !self.navigationController.isBeingDismissed &&
        UIApplication.sharedApplication.applicationState==UIApplicationStateActive &&
        (!self.view.window.windowScene ||
         self.view.window.windowScene.activationState==UISceneActivationStateForegroundActive);
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self tryAutomaticUpdatePrompt];
}
- (void)presentUpdateResult:(NSString *)title message:(NSString *)message showRepository:(BOOL)showRepository {
    if(![self isSettingsRootVisible] || self.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    if(showRepository) [alert addAction:[UIAlertAction actionWithTitle:@"查看 GitHub"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self openRepository];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)afterUpdatePrompt:(UIAlertController *)prompt perform:(dispatch_block_t)completion {
    if(prompt.presentingViewController) {
        id<UIViewControllerTransitionCoordinator> transition=prompt.transitionCoordinator;
        if(prompt.isBeingDismissed && transition) {
            [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                completion();
            }];
        } else [prompt dismissViewControllerAnimated:YES completion:completion];
    } else completion();
}
- (void)downloadUpdateRelease:(NSDictionary *)candidate prompt:(UIAlertController *)prompt {
    if(self.checkingUpdate || !FMHostUI() || ![self isSettingsRootVisible]) return;
    NSDictionary *release=[LCOrbitUpdateRelease validatedRelease:candidate error:nil];
    if(!release || ![LCOrbitUpdateRelease isNewerRelease:release thanVersion:FM_MENU_VERSION]) return;
    self.checkingUpdate=YES;
    self.updateStatusLabel.text=@"下载并校验插件中…";
    NSMutableURLRequest *download=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:release[@"downloadURL"]]];
    download.timeoutInterval=40;
    __weak typeof(self) weakSelf=self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:download completionHandler:^(NSData *binary,NSURLResponse *response,NSError *error) {
        NSError *installError=nil;
        BOOL success=NO;
        if(!error && [(NSHTTPURLResponse *)response statusCode]==200 && binary.length>0 && FMHostUI())
            success=[LCOrbitPluginUpdater installDownloadedPlugin:binary expectedSHA256:release[@"sha256"] error:&installError];
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) owner=weakSelf;
            if(!owner) return;
            owner.checkingUpdate=NO;
            owner.updateStatusLabel.text=@"检查微珠最新发布版";
            [owner afterUpdatePrompt:prompt perform:^{
                [weakSelf presentUpdateResult:success?@"插件已下载并替换":@"更新未完成"
                    message:success?@"已校验并替换旧插件。请前往 LC 原生 Tweaks 页面重新签名插件，然后重启 LC 和相关 Guest。共享及专属插件需单独更新。":
                    (installError.localizedDescription?:error.localizedDescription?:@"下载或替换失败，请检查网络与插件目录。")
                    showRepository:!success];
            }];
        });
    }] resume];
}
- (void)offerUpdateRelease:(NSDictionary *)release automatic:(BOOL)automatic {
    if(!FMHostUI() || ![self isSettingsRootVisible] || self.presentedViewController || self.checkingUpdate) return;
    NSString *version=release[@"version"];
    if(automatic) {
        if(!self.automaticallyOfferedVersions) self.automaticallyOfferedVersions=[NSMutableSet set];
        if([self.automaticallyOfferedVersions containsObject:version]) return;
        [self.automaticallyOfferedVersions addObject:version];
    }
    NSString *message=[NSString stringWithFormat:@"%@\n\n下载后将校验新插件并原子替换旧版本。校验或替换失败时保留旧插件。安装完成后，请在 LC 原生 Tweaks 页面重新签名并重启相关应用。",release[@"notes"]];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"发现微珠新版本 v%@",version]
        message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf=self;
    __weak UIAlertController *weakAlert=alert;
    __block BOOL handled=NO;
    [alert addAction:[UIAlertAction actionWithTitle:@"跳过此版本" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if(handled) return;handled=YES;
        typeof(self) owner=weakSelf;
        if(!owner || !FMHostUI()) return;
        SetPref(@"skippedUpdateVersion",version);
        NSError *saveError=[LCOrbitStorage lastError];
        if(saveError || ![[HostDefaults() objectForKey:Pref(@"skippedUpdateVersion")] isEqual:version])
            [owner afterUpdatePrompt:weakAlert perform:^{
                [weakSelf presentUpdateResult:@"跳过未保存" message:@"无法保存跳过设置，请检查 LCOrbit 配置目录后重试。下次进入设置仍可能提示此版本。" showRepository:NO];
            }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"下载更新" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if(handled) return;handled=YES;
        [weakSelf downloadUpdateRelease:release prompt:weakAlert];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tryAutomaticUpdatePrompt {
    if(!FMHostUI() || ![self isSettingsRootVisible] || self.presentedViewController || self.checkingUpdate) return;
    NSDictionary *release=[LCOrbitUpdateRelease validatedRelease:
        [NSUserDefaults.standardUserDefaults objectForKey:FMUpdateCacheRelease] error:nil];
    if(release) {
        id skipped=[HostDefaults() objectForKey:Pref(@"skippedUpdateVersion")];
        if([LCOrbitUpdateRelease shouldOfferRelease:release installedVersion:FM_MENU_VERSION
            skippedVersion:[skipped isKindOfClass:NSString.class]?skipped:nil])
            [self offerUpdateRelease:release automatic:YES];
        return;
    }
    if(self.requestedAutomaticUpdate) return;
    self.requestedAutomaticUpdate=YES;
    self.checkingUpdate=YES;
    __weak typeof(self) weakSelf=self;
    FMFetchUpdateRelease(15,^(NSDictionary *fetched,NSError *error,NSUInteger sequence) {
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) owner=weakSelf;
            // Cache even if Settings was closed; only a currently visible
            // root may offer it. Keep the checking guard during notification.
            if(fetched) FMCacheUpdateRelease(fetched,sequence);
            owner.checkingUpdate=NO;
            [owner tryAutomaticUpdatePrompt];
        });
    });
}
- (void)checkForUpdates {
    if(self.checkingUpdate) return;
    self.checkingUpdate=YES;
    self.updateStatusLabel.text=@"正在检查最新发布版…";
    __weak typeof(self) weakSelf=self;
    FMFetchUpdateRelease(15,^(NSDictionary *release,NSError *error,NSUInteger sequence) {
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) owner=weakSelf;
            NSDictionary *accepted=release?FMCacheUpdateRelease(release,sequence):nil;
            owner.checkingUpdate=NO;
            owner.updateStatusLabel.text=@"检查微珠最新发布版";
            if(!owner || ![owner isSettingsRootVisible]) return;
            if(!accepted) {
                [owner presentUpdateResult:@"检查更新失败" message:error.localizedDescription?:@"无法获取 GitHub 最新发布信息。" showRepository:YES];
            } else if(![LCOrbitUpdateRelease isNewerRelease:accepted thanVersion:FM_MENU_VERSION]) {
                [owner presentUpdateResult:@"已是最新版本" message:[NSString stringWithFormat:@"当前 v%@，最新 v%@。",FM_MENU_VERSION,accepted[@"version"]] showRepository:NO];
            } else if(!FMHostUI()) {
                [owner presentUpdateResult:@"发现新版本" message:@"请返回 LC 主界面，在微珠设置中心安装更新。" showRepository:YES];
            } else [owner offerUpdateRelease:accepted automatic:NO];
        });
    });
}
- (void)openApps {
    FMSettingsSectionController *detail=[[FMSettingsSectionController alloc] initWithSection:@"apps"];
    [self.navigationController pushViewController:detail animated:YES];
}
- (void)openGitHub {
    if(!FMHostUI()) return;
    FMSettingsSectionController *detail=[[FMSettingsSectionController alloc] initWithSection:@"github"];
    [self.navigationController pushViewController:detail animated:YES];
}
- (void)openDiagnostics {
    FMSettingsSectionController *detail=[[FMSettingsSectionController alloc] initWithSection:@"diagnostics"];
    [self.navigationController pushViewController:detail animated:YES];
}
- (void)openSharedTweaks {
    if(!FMHostUI()) return;
    LCOrbitSharedTweaksViewController *manager=
        [[LCOrbitSharedTweaksViewController alloc]
            initWithBackground:FMThemeColor(FMColorBackground)
            surface:FMThemeColor(FMColorSurface)
            text:FMThemeColor(FMColorText)
            secondary:FMThemeColor(FMColorSecondary)
            accent:FMAccent()];
    [self.navigationController pushViewController:manager animated:YES];
}
- (void)rebuild {
    if(!self.isViewLoaded || !self.contentScroll) return;
    self.view.backgroundColor=FMThemeColor(FMColorBackground);
    UIScrollView *scroll=self.contentScroll;
    CGFloat oldOffset=scroll.contentOffset.y;
    for(UIView *view in [scroll.subviews copy])
        if([view isKindOfClass:UIStackView.class]) [view removeFromSuperview];
    UIStackView *stack=[UIStackView new];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.alignment=UIStackViewAlignmentFill;
    stack.spacing=12;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-36],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36]
    ]];
    FMManager *manager=[FMManager shared];
    // Display/Appearance and Interaction are inline on the root settings
    // page. Only the two less frequently used management sections navigate.
    [manager populateSettingsCategory:@"appearance" stack:stack];
    UIView *gap=[UIView new];[gap.heightAnchor constraintEqualToConstant:12].active=YES;
    [stack addArrangedSubview:gap];
    [manager populateSettingsCategory:@"behavior" stack:stack];
    UIView *secondGap=[UIView new];
    [secondGap.heightAnchor constraintEqualToConstant:12].active=YES;
    [stack addArrangedSubview:secondGap];
    UILabel *section=[UILabel new];
    section.text=@"管理与支持";
    section.textColor=FMThemeColor(FMColorSecondary);
    section.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [stack addArrangedSubview:section];
    UIControl *apps=[self navigationRow:@"应用管理" subtitle:FMHostUI()?@"收藏、排序、自动画中画与独立设置":@"收藏、排序与独立设置"
                               symbol:@"square.stack.3d.up"
                           badgeColor:[UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:1.0]
                               action:@selector(openApps)];
    [apps.heightAnchor constraintEqualToConstant:65].active=YES;
    [stack addArrangedSubview:apps];
    if(FMHostUI()) {
        UIControl *shared=[self navigationRow:@"插件管理中心" subtitle:@"按 App 分配、启停和批量共享"
                                   symbol:@"square.stack.3d.up.fill"
                               badgeColor:[UIColor colorWithRed:88/255.0 green:86/255.0 blue:214/255.0 alpha:1.0]
                                   action:@selector(openSharedTweaks)];
        [shared.heightAnchor constraintEqualToConstant:65].active=YES;
        [stack addArrangedSubview:shared];
    }
    UIControl *logs=[self navigationRow:@"诊断与日志" subtitle:@"查看、导出和清除日志"
                               symbol:@"waveform.path.ecg"
                           badgeColor:[UIColor colorWithRed:175/255.0 green:82/255.0 blue:222/255.0 alpha:1.0]
                               action:@selector(openDiagnostics)];
    [logs.heightAnchor constraintEqualToConstant:65].active=YES;
    [stack addArrangedSubview:logs];
    UIView *space=[UIView new];[space.heightAnchor constraintEqualToConstant:18].active=YES;
    [stack addArrangedSubview:space];
    [manager appendResetStyleRow:stack];
    // Keep About/Updates at the very bottom, below Reset as requested.
    UIView *aboutGap=[UIView new];
    [aboutGap.heightAnchor constraintEqualToConstant:20].active=YES;
    [stack addArrangedSubview:aboutGap];
    UILabel *aboutTitle=[UILabel new];
    aboutTitle.text=@"版本与更新";
    aboutTitle.textColor=FMThemeColor(FMColorSecondary);
    aboutTitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [stack addArrangedSubview:aboutTitle];
    NSString *version=[NSString stringWithFormat:@"v%@ · %@",FM_MENU_VERSION,FMCommitSummary()];
    UIControl *versionRow=[self navigationRow:@"当前版本" subtitle:version
        symbol:@"number.circle"
        badgeColor:[UIColor colorWithRed:142/255.0 green:142/255.0 blue:147/255.0 alpha:1.0]
        action:NULL];
    [versionRow.heightAnchor constraintEqualToConstant:65].active=YES;
    [stack addArrangedSubview:versionRow];
    UIControl *checkRow=[self navigationRow:@"检测更新"
        subtitle:self.checkingUpdate?@"正在检查最新发布版…":@"检查微珠最新发布版"
        symbol:@"arrow.clockwise.circle"
        badgeColor:[UIColor colorWithRed:52/255.0 green:199/255.0 blue:89/255.0 alpha:1.0]
        action:@selector(checkForUpdates)];
    [checkRow.heightAnchor constraintEqualToConstant:65].active=YES;
    [stack addArrangedSubview:checkRow];
    if(FMHostUI()) {
        UIControl *access=[self navigationRow:@"GitHub 访问" subtitle:@"账号、Token 与连接验证"
            symbol:@"key.fill"
            badgeColor:[UIColor colorWithRed:88/255.0 green:86/255.0 blue:214/255.0 alpha:1.0]
            action:@selector(openGitHub)];
        [access.heightAnchor constraintEqualToConstant:65].active=YES;
        [stack addArrangedSubview:access];
    }
    UIControl *repository=[self navigationRow:@"GitHub 仓库"
        subtitle:@"github.com/dompling/LC-SS-widget-export"
        symbol:@"link"
        badgeColor:[UIColor colorWithRed:0/255.0 green:122/255.0 blue:255/255.0 alpha:1.0]
        action:@selector(openRepository)];
    [repository.heightAnchor constraintEqualToConstant:65].active=YES;
    [stack addArrangedSubview:repository];
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.contentScroll!=scroll || !scroll.window) return;
        [scroll layoutIfNeeded];
        CGFloat maxY=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
        [scroll setContentOffset:CGPointMake(0,MIN(oldOffset,maxY)) animated:NO];
    });
}
@end

@implementation FMSettingsSectionController
- (instancetype)initWithSection:(NSString *)key {
    if((self=[super initWithNibName:nil bundle:nil])) _sectionKey=[key copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    NSDictionary *titles=@{@"appearance":@"显示与外观",@"behavior":@"交互与切换",
                           @"apps":@"应用管理",@"diagnostics":@"诊断与日志",@"github":@"GitHub 访问"};
    self.title=titles[self.sectionKey]?:@"设置";
    self.view.backgroundColor=FMThemeColor(FMColorBackground);
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.backgroundColor=UIColor.clearColor;
    scroll.alwaysBounceVertical=YES;
    scroll.showsVerticalScrollIndicator=YES;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    self.contentScroll=scroll;
    [self rebuild];
}
- (BOOL)isGitHubPageVisible {
    return FMHostUI() && [self.sectionKey isEqualToString:@"github"] && self.isViewLoaded &&
        self.view.window && self.navigationController.topViewController==self &&
        !self.isBeingDismissed && !self.navigationController.isBeingDismissed;
}
- (void)invalidateGitHubVerification {
    self.githubGeneration++;
    self.checkingGitHub=NO;
    self.githubResult=nil;
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if([self.sectionKey isEqualToString:@"github"] &&
       (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed ||
        self.navigationController.topViewController!=self)) [self invalidateGitHubVerification];
}
- (void)showGitHubMessage:(NSString *)message {
    if(![self isGitHubPageVisible] || self.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"GitHub 访问"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)populateGitHub:(UIStackView *)stack {
    if(!FMHostUI()) return;
    FMManager *manager=[FMManager shared];
    NSError *accountError=nil,*tokenError=nil;
    NSString *account=[LCOrbitGitHub accountWithError:&accountError];
    BOOL hasToken=[LCOrbitGitHub hasTokenWithError:&tokenError];
    [manager section:@"访问配置" sub:@"账号可选，用于核对 Token 对应的用户。凭据仅保存在 LC 宿主钥匙串中。" in:stack];
    UILabel *accountLabel=[manager label:[@"账号：" stringByAppendingString:account.length?account:@"未配置"]
        size:14 weight:UIFontWeightRegular];
    [stack addArrangedSubview:accountLabel];
    UILabel *tokenLabel=[manager label:hasToken?@"Token：已保存":@"Token：未配置"
        size:14 weight:UIFontWeightRegular];
    [stack addArrangedSubview:tokenLabel];
    if(accountError || tokenError) {
        UILabel *failure=[manager label:@"无法读取钥匙串配置，请重新配置或清除后重试。"
            size:13 weight:UIFontWeightRegular];
        failure.textColor=FMThemeColor(FMColorSecondary);
        [stack addArrangedSubview:failure];
    }
    NSArray *titles=@[@"编辑账号与 Token",self.checkingGitHub?@"正在验证连接…":@"验证连接",@"清除凭据"];
    NSArray *icons=@[@"pencil",@"checkmark.shield",@"trash"];
    NSArray *actions=@[NSStringFromSelector(@selector(editGitHubCredentials)),
        NSStringFromSelector(@selector(verifyGitHubConnection)),NSStringFromSelector(@selector(clearGitHubCredentials))];
    for(NSUInteger i=0;i<titles.count;i++) {
        UIControl *row=(UIControl *)[manager rowForTitle:titles[i] icon:icons[i] height:54 action:NULL];
        [row addTarget:self action:NSSelectorFromString(actions[i]) forControlEvents:UIControlEventTouchUpInside];
        row.accessibilityLabel=titles[i];row.accessibilityTraits=UIAccessibilityTraitButton;
        if(i==1) row.enabled=!self.checkingGitHub;
        [manager addRow:row height:54 to:stack];
    }
    if(self.githubResult.length) {
        UILabel *result=[manager label:self.githubResult size:13 weight:UIFontWeightRegular];
        result.textColor=FMThemeColor(FMColorSecondary);
        [stack addArrangedSubview:result];
    }
}
- (void)editGitHubCredentials {
    if(![self isGitHubPageVisible] || self.presentedViewController) return;
    NSError *error=nil;
    NSString *account=[LCOrbitGitHub accountWithError:&error];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"GitHub 访问配置"
        message:@"账号可以留空。Token 留空会保留已保存的 Token。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder=@"GitHub 账号（可选）";field.text=account?:@"";
        field.autocapitalizationType=UITextAutocapitalizationTypeNone;
        field.autocorrectionType=UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder=@"Token（留空保留原值）";field.secureTextEntry=YES;
        field.autocapitalizationType=UITextAutocapitalizationTypeNone;
        field.autocorrectionType=UITextAutocorrectionTypeNo;
        field.spellCheckingType=UITextSpellCheckingTypeNo;
        field.textContentType=UITextContentTypePassword;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) owner=weakSelf;UIAlertController *editor=weakAlert;
        if(![owner isGitHubPageVisible] || !editor) return;
        NSError *saveError=nil;
        BOOL saved=[LCOrbitGitHub saveAccount:editor.textFields[0].text?:@""
            token:editor.textFields[1].text?:@"" error:&saveError];
        editor.textFields[1].text=@"";
        if(saved) { [owner invalidateGitHubVerification];[owner rebuild]; }
        else {
            owner.githubResult=saveError.localizedDescription?:@"保存失败，原配置仍保留。请检查钥匙串权限后重试。";
            [owner rebuild];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)clearGitHubCredentials {
    if(![self isGitHubPageVisible] || self.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清除 GitHub 凭据？"
        message:@"将删除已保存的账号与 Token，之后检查更新会使用匿名访问。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        typeof(self) owner=weakSelf;
        if(![owner isGitHubPageVisible]) return;
        NSError *error=nil;
        if([LCOrbitGitHub clearCredentialsWithError:&error]) {
            [owner invalidateGitHubVerification];[owner rebuild];
        } else {
            owner.githubResult=error.localizedDescription?:@"清除失败，原配置仍保留。请检查钥匙串权限后重试。";
            [owner rebuild];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)verifyGitHubConnection {
    if(![self isGitHubPageVisible] || self.checkingGitHub || self.presentedViewController) return;
    NSError *error=nil;
    NSString *account=[LCOrbitGitHub accountWithError:&error];
    if(error) { [self showGitHubMessage:error.localizedDescription];return; }
    BOOL hasToken=[LCOrbitGitHub hasTokenWithError:&error];
    if(error || !hasToken) {
        [self showGitHubMessage:error.localizedDescription?:@"请先配置 Token，再验证连接。"];
        return;
    }
    NSMutableURLRequest *request=[LCOrbitGitHub requestForURL:[NSURL URLWithString:@"https://api.github.com/user"]
        timeout:15 error:&error];
    if(!request) { [self showGitHubMessage:error.localizedDescription?:@"无法读取 GitHub 配置，请重新设置后重试。"];return; }
    self.checkingGitHub=YES;self.githubResult=nil;
    NSUInteger generation=++self.githubGeneration;
    [self rebuild];
    __weak typeof(self) weakSelf=self;
    [LCOrbitGitHub performRequest:request completion:^(NSData *data,NSHTTPURLResponse *response,NSError *failure) {
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) owner=weakSelf;
            if(!owner || owner.githubGeneration!=generation) return;
            owner.checkingGitHub=NO;
            if(![owner isGitHubPageVisible]) return;
            NSString *message=nil;
            if(failure) message=@"连接 GitHub 失败，请检查网络后重试。";
            else if(response.statusCode!=200) message=[LCOrbitGitHub messageForStatusCode:response.statusCode];
            else {
                id json=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
                id login=[json isKindOfClass:NSDictionary.class]?json[@"login"]:nil;
                if(![login isKindOfClass:NSString.class] || ![login length] || [login length]>100)
                    message=@"GitHub 返回的账号信息不完整，请稍后重试。";
                else if(account.length && [account caseInsensitiveCompare:login]!=NSOrderedSame)
                    message=@"Token 对应的账号与已配置账号不一致，请检查账号或 Token。";
                else message=[NSString stringWithFormat:@"连接成功，当前账号：%@",login];
            }
            owner.githubResult=message;[owner rebuild];
            // Editing or clearing while verification finishes must not
            // interrupt that alert; the current result remains on the page.
            if(!owner.presentedViewController) [owner showGitHubMessage:message];
        });
    }];
}
- (void)rebuild {
    if(!self.isViewLoaded || !self.contentScroll) return;
    self.view.backgroundColor=FMThemeColor(FMColorBackground);
    UIScrollView *scroll=self.contentScroll;
    CGFloat offset=scroll.contentOffset.y;
    for(UIView *child in [scroll.subviews copy])
        if([child isKindOfClass:UIStackView.class]) [child removeFromSuperview];
    UIStackView *stack=[UIStackView new];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.alignment=UIStackViewAlignmentFill;
    stack.spacing=12;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-32],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36]
    ]];
    if([self.sectionKey isEqualToString:@"github"]) [self populateGitHub:stack];
    else [[FMManager shared] populateSettingsCategory:self.sectionKey stack:stack];
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.contentScroll!=scroll || !scroll.window) return;
        [scroll layoutIfNeeded];
        CGFloat maxY=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
        [scroll setContentOffset:CGPointMake(0,MIN(offset,maxY)) animated:NO];
    });
}
@end

// ---------------------------------------------------------------------------
// The sidebar settings page, after the wloc dock's: a preview card stays pinned
// on top and the options below it come in groups, one open at a time.

typedef NS_ENUM(NSInteger, FMDockGroup) {
    FMDockGroupPosition,FMDockGroupHandle,FMDockGroupOpacity,FMDockGroupTray,FMDockGroupCount
};
// When a row shows inside its open group.
typedef NS_ENUM(NSInteger, FMDockWhen) {
    FMDockWhenAlways,FMDockWhenCapsule,FMDockWhenFade,FMDockWhenCompact,FMDockWhenList
};

@interface FMDockSlider : UISlider
@property(nonatomic,copy) NSDictionary *option;
@property(nonatomic,weak) UILabel *valueLabel;
@end
@implementation FMDockSlider
@end
@interface FMDockSwitch : UISwitch
@property(nonatomic,copy) NSString *key;
@end
@implementation FMDockSwitch
@end
@interface FMDockSegments : UISegmentedControl
@property(nonatomic,copy) NSString *key;
@end
@implementation FMDockSegments
@end

// The settings this page adds to the two option tables, in the same form.
static NSArray<NSDictionary *> *FMDockExtraOptions(void) {
    return @[
        @{@"key":@"orbScale",@"title":@"微珠缩放",@"min":@.7,@"max":@1.9,@"default":@1,@"unit":@"%",@"step":@.05},
        @{@"key":@"idleAlpha",@"title":@"平时的透明度",@"min":@.25,@"max":@1,@"default":@.72,@"unit":@"%",@"step":@.05},
        @{@"key":@"panelScale",@"title":@"弹出菜单缩放",@"min":@.5,@"max":@1.2,@"default":@1,@"unit":@"%",@"step":@.05},
        @{@"key":@"glassTint",@"title":@"玻璃主题着色增强",@"min":@0,@"max":@.15,@"default":@0,@"unit":@"%",@"step":@.01}
    ];
}
// One setting by key, optionally under another title.
static NSDictionary *FMDockOption(NSString *key,NSString *title) {
    NSArray<NSArray<NSDictionary *> *> *tables=@[FMOrbStyleOptions(),FMMenuStyleOptions(),FMDockExtraOptions()];
    for(NSArray<NSDictionary *> *table in tables) for(NSDictionary *option in table) if([option[@"key"] isEqualToString:key]) {
        if(!title) return option;
        NSMutableDictionary *renamed=[option mutableCopy];
        renamed[@"title"]=title;
        return renamed;
    }
    return nil;
}
static CGFloat FMDockStoredValue(NSDictionary *option) {
    // The bead size may still come from the old width setting; show what is in use.
    if([option[@"key"] isEqualToString:@"orbScale"]) return FMOrbScale();
    CGFloat fallback=[option[@"default"] doubleValue],value=FloatPref(option[@"key"],fallback);
    return Clamp(isfinite(value)?value:fallback,[option[@"min"] doubleValue],[option[@"max"] doubleValue]);
}
// "22 pt", "83%", "5 秒" (two decimals when the step is finer than a second).
static NSString *FMDockValueText(NSDictionary *option,CGFloat value) {
    NSString *unit=option[@"unit"];
    if([unit isEqualToString:@"%"]) return [NSString stringWithFormat:@"%ld%%",lround(value*100)];
    if([unit isEqualToString:@"秒"])
        return [option[@"step"] doubleValue]<1?[NSString stringWithFormat:@"%.2f 秒",value]:[NSString stringWithFormat:@"%ld 秒",lround(value)];
    return [NSString stringWithFormat:@"%ld pt",lround(value)];
}
static UILabel *FMDockLabel(NSString *text,CGFloat size,UIColor *color) {
    UILabel *label=[UILabel new];
    label.text=text;
    label.font=[UIFont systemFontOfSize:size weight:UIFontWeightRegular];
    label.textColor=color;
    label.numberOfLines=0;
    return label;
}
static CGFloat FMDockCardRadius(void) {
    if(@available(iOS 26.0,*)) return 26;
    return 14;
}
// One row of a group: the content inset like a list row, a hairline above it and at
// least minHeight tall. A row is only ever in the stack while it is on show (closing a
// group takes it out), so its own height can be stated outright.
static UIView *FMDockRow(UIView *content,CGFloat padding,BOOL separator,CGFloat minHeight) {
    UIView *row=[UIView new];
    content.translatesAutoresizingMaskIntoConstraints=NO;
    [row addSubview:content];
    // The content decides the height; the minimum wins for a short one.
    NSLayoutConstraint *natural=[row.heightAnchor constraintEqualToAnchor:content.heightAnchor constant:2*padding];
    natural.priority=250;
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [content.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [content.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [content.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:padding],
        [content.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-padding],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:minHeight],
        natural
    ]];
    if(separator) {
        UIView *line=[UIView new];
        line.translatesAutoresizingMaskIntoConstraints=NO;
        line.backgroundColor=[FMThemeColor(FMColorBorder) colorWithAlphaComponent:.38];
        line.userInteractionEnabled=NO;
        [row addSubview:line];
        [NSLayoutConstraint activateConstraints:@[
            [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
            [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
            [line.topAnchor constraintEqualToAnchor:row.topAnchor],
            [line.heightAnchor constraintEqualToConstant:1/UIScreen.mainScreen.scale]
        ]];
    }
    return row;
}
// A group's rounded container: the same glass the drawer is made of, so the page has the
// material rather than a painted copy of it. The rows sit above the glass instead of inside
// its content view, because their height is what gives the card its own, and a view the
// effect positions by itself cannot carry that.
static UIView *FMDockCard(UIStackView *rows) {
    UIView *card=[[FMManager shared] glass:CGRectMake(0,0,320,120) radius:FMDockCardRadius() strong:YES];
    card.translatesAutoresizingMaskIntoConstraints=NO;
    card.layer.cornerCurve=kCACornerCurveContinuous;
    rows.translatesAutoresizingMaskIntoConstraints=NO;
    [card addSubview:rows];
    [NSLayoutConstraint activateConstraints:@[
        [rows.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [rows.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [rows.topAnchor constraintEqualToAnchor:card.topAnchor],
        [rows.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
    return card;
}

// The card pinned at the top of the page: the drawer and its bead as the settings
// would draw them, on the dock's own pastel gradient. It is built like the real
// thing (glass shell clipped to the same morph outline, same contents), moves with
// the same springs and pops its contents in the way the setting says. Tapping it
// opens and closes it.
@interface FMDockPreviewView : UIView
@property(nonatomic,weak) NSLayoutConstraint *heightConstraint;
@property(nonatomic,assign) CGFloat maxHeight;
@property(nonatomic,copy) void (^onToggle)(BOOL open);
@property(nonatomic,readonly) BOOL isOpen;
- (void)reload;
- (void)setOpen:(BOOL)open animated:(BOOL)animated;
- (void)replay;
@end
@implementation FMDockPreviewView {
    UIView *_scene,*_drawer,*_glass,*_content,*_bead,*_edge;
    NSArray<NSDictionary *> *_popItems;
    NSArray<UIView *> *_popDividers;
    FMNotchParams _beadParams,_dropletParams,_drawerParams;
    NSArray<NSDictionary *> *_favorites;
    BOOL _dirty,_placed,_left,_compact,_open,_revealed,_started,_faded,_rebuildScheduled;
    CGFloat _pw,_ph,_actual,_fit,_closedHeight,_openHeight,_beadW,_beadH,_shadow,_builtWidth,_listTop;
    CGFloat _idleAlpha,_fadedAlpha;
    CGFloat _progress,_velocity,_omega,_zeta;
    CFTimeInterval _tick,_elapsed,_builtAt;
    CADisplayLink *_link;
    NSTimer *_fadeTimer;
}
+ (Class)layerClass { return CAGradientLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame])) return nil;
    CAGradientLayer *gradient=(CAGradientLayer *)self.layer;
    gradient.colors=@[(id)RGBA(.74,.86,.78,1).CGColor,(id)RGBA(.62,.78,.92,1).CGColor];
    gradient.startPoint=CGPointMake(0,0);
    gradient.endPoint=CGPointMake(1,1);
    gradient.cornerRadius=22;
    gradient.cornerCurve=kCACornerCurveContinuous;
    self.clipsToBounds=YES;
    self.isAccessibilityElement=YES;
    self.accessibilityLabel=@"侧边栏预览";
    self.accessibilityHint=@"轻点展开或收起";
    self.accessibilityTraits=UIAccessibilityTraitButton;
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    return self;
}
- (BOOL)isOpen { return _open; }
- (void)setMaxHeight:(CGFloat)maxHeight {
    _maxHeight=maxHeight;
    [self reload];
}
- (void)dealloc {
    [_link invalidate];
    [_fadeTimer invalidate];
}
- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if(newWindow) return;
    [self stopLink];
    [_fadeTimer invalidate];
    _fadeTimer=nil;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if(!self.window) return;
    // A spring stopped by leaving the window must not leave the card half open.
    if(!_link && fabs(_progress-(_open?1:0))>.001 && _glass) {
        _velocity=0;
        [self applyProgress:_open?1:0];
    }
    [self scheduleFade];
}
// The drawer's size from the current settings, exactly as the real drawer lays out
// three apps, and how tall the card is closed and open.
- (void)measure {
    FMBeginPreferenceSnapshot();
    FMManager *manager=[FMManager shared];
    _left=BoolPref(@"onLeft",manager.left);
    _compact=BoolPref(@"compactMode",NO);
    _actual=Clamp(FloatPref(@"panelScale",1.0),.50,1.20);
    CGFloat shoulder=FMMenuStyleValue(@"menuExtension")*(_compact?22./28:1);
    CGFloat rowHeight=_compact?63:MAX(56,48/MAX(.50,_actual));
    CGFloat footer=_compact?76:44;
    _pw=_compact?76:240;
    _favorites=_compact?@[]:[manager pinnedApps];
    _listTop=_compact?shoulder+8:(_favorites.count?64+shoulder:shoulder+6);
    _ph=_compact?20+3*65+footer+12+2*shoulder:_listTop+(footer+6+shoulder)+3*(rowHeight+4);
    _closedHeight=MAX([manager orbHeight]+100,190);
    // A short window cannot spare that much: the card gives way before the options do.
    if(_maxHeight>0) _closedHeight=MIN(_closedHeight,MAX(_maxHeight,[manager orbHeight]+24));
    CGFloat opened=MIN(_ph*_actual+24,420);
    if(_maxHeight>0) opened=MIN(opened,MAX(_maxHeight,_closedHeight));
    _openHeight=opened;
    // Read once here: every frame of a spring needs them.
    _idleAlpha=Clamp(FloatPref(@"idleAlpha",.72),.25,1);
    _fadedAlpha=FMOrbStyleValue(@"fadedOpacity");
    FMEndPreferenceSnapshot();
}
- (void)syncHeight {
    CGFloat height=_closedHeight+(_openHeight-_closedHeight)*Clamp(_progress,-.03,1.1);
    NSLayoutConstraint *constraint=self.heightConstraint;
    if(constraint && fabs(constraint.constant-height)>.01) constraint.constant=height;
}
// Settings changed: measure again now (the card's height follows) and redraw at the
// next layout, however many changes arrive before it.
- (void)reload {
    [self measure];
    [self syncHeight];
    _dirty=YES;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=CGRectGetWidth(self.bounds);
    if(width<1) return;
    // A drag moves a slider many times a second: the picture is rebuilt at most about twenty
    // times a second, and the last value always gets its turn.
    BOOL due=CACurrentMediaTime()-_builtAt>=.05;
    BOOL rebuild=!_scene || fabs(width-_builtWidth)>.5 || (_dirty && due);
    // Nothing in the card may ride on an animation that happens to be running around it
    // (the page's groups unfolding lays this view out too).
    [UIView performWithoutAnimation:^{
        if(rebuild) {
            if(self->_pw<=0) [self measure];
            self->_dirty=NO;
            self->_builtWidth=width;
            [self build];
        } else if(self->_dirty) [self rebuildSoon];
        [self placeScene];
    }];
}
- (void)rebuildSoon {
    if(_rebuildScheduled) return;
    _rebuildScheduled=YES;
    __weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.05*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        typeof(self) strongSelf=weakSelf;
        if(!strongSelf) return;
        strongSelf->_rebuildScheduled=NO;
        [strongSelf setNeedsLayout];
    });
}
- (UIView *)iconForSlot:(NSUInteger)slot size:(CGFloat)size apps:(NSArray<NSDictionary *> *)apps {
    if(slot<apps.count) return [[FMManager shared] iconViewForApp:apps[slot] size:size];
    UIView *box=[[UIView alloc] initWithFrame:CGRectMake(0,0,size,size)];
    box.layer.cornerRadius=size*.22;
    box.clipsToBounds=YES;
    box.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:.50];
    UIImageView *glyph=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"app.fill"]];
    glyph.tintColor=FMAccent();
    glyph.contentMode=UIViewContentModeScaleAspectFit;
    glyph.frame=CGRectInset(box.bounds,size*.26,size*.26);
    [box addSubview:glyph];
    return box;
}
// A footer button as the drawer draws it, without the action.
- (UIView *)footerTile:(NSString *)symbol compact:(BOOL)compact size:(CGFloat)size {
    BOOL dark=FMMenuDark();
    UIView *tile=[[UIView alloc] initWithFrame:CGRectMake(0,0,size,size)];
    tile.layer.cornerRadius=size*.26;
    tile.layer.cornerCurve=kCACornerCurveContinuous;
    tile.backgroundColor=compact?[UIColor.whiteColor colorWithAlphaComponent:dark?.10:.18]:FMClearGlassEnabled()?
        [FMThemeColor(FMColorTool) colorWithAlphaComponent:UIAccessibilityIsReduceTransparencyEnabled()?.94:.48]:
        FMThemeColor(FMColorTool);
    tile.layer.borderWidth=.8;
    tile.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:dark?.55:.28].CGColor;
    tile.layer.shadowColor=UIColor.blackColor.CGColor;
    tile.layer.shadowOpacity=dark?.20:.09;
    tile.layer.shadowRadius=3;
    UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration
        configurationWithPointSize:compact?23:22 weight:UIImageSymbolWeightSemibold];
    UIImageView *glyph=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]];
    glyph.frame=CGRectInset(tile.bounds,compact?12:7,compact?12:7);
    glyph.contentMode=UIViewContentModeScaleAspectFit;
    glyph.tintColor=compact?FMThemeColor(FMColorText):FMClearGlassEnabled()?FMThemeColor(FMColorText):FMAccent();
    [tile addSubview:glyph];
    return tile;
}
// Three apps (a strip of favorites on top in the list layout), the footer buttons and
// the dividers, at the positions buildPanel and its helpers give them.
- (void)buildContents {
    FMManager *manager=[FMManager shared];
    NSArray<NSDictionary *> *apps=[manager orderedAppsForMenu];
    _content=[[UIView alloc] initWithFrame:_glass.bounds];
    [FMGlassContent(_glass) addSubview:_content];
    NSMutableArray<UIView *> *items=[NSMutableArray array],*dividers=[NSMutableArray array];
    CGFloat pw=_pw,ph=_ph,hairline=1/UIScreen.mainScreen.scale;
    CGFloat shoulder=FMMenuStyleValue(@"menuExtension")*(_compact?22./28:1);
    UIColor *rule=[FMThemeColor(FMColorBorder) colorWithAlphaComponent:.55];
    BOOL dark=FMMenuDark();
    if(_compact) {
        CGFloat top=_listTop,size=FMMenuStyleValue(@"menuCompactIconSize"),width=pw-6;
        for(NSUInteger index=0;index<3;index++) {
            UIView *row=[[UIView alloc] initWithFrame:CGRectMake(3,top+index*66,width,63)];
            if(BoolPref(@"iconFrame",YES)) {
                UIView *backing=[[UIView alloc] initWithFrame:CGRectMake((width-54)*.5,(63-54)*.5,54,54)];
                backing.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:FMClearGlassEnabled()?.64:.74];
                backing.layer.cornerRadius=14;
                backing.layer.borderWidth=.5;
                backing.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:dark?.26:.40].CGColor;
                [row addSubview:backing];
            }
            UIView *icon=[self iconForSlot:index size:size apps:apps];
            icon.center=CGPointMake(width*.5,63*.5);
            icon.layer.borderWidth=.55;
            icon.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:dark?.54:.36].CGColor;
            [row addSubview:icon];
            [_content addSubview:row];
            [items addObject:row];
        }
        UIView *bar=[[UIView alloc] initWithFrame:CGRectMake(3,ph-76-6-22,width,76)];
        [_content addSubview:bar];
        UIView *divider=[[UIView alloc] initWithFrame:CGRectMake(13,0,width-26,.8)];
        divider.backgroundColor=rule;
        [bar addSubview:divider];
        [dividers addObject:divider];
        UIView *home=[self footerTile:@"house.fill" compact:YES size:50];
        home.center=CGPointMake(width*.5,4+(76-4)*.5);
        [bar addSubview:home];
        [items addObject:home];
    } else {
        CGFloat inner=pw-24,gap=4,cell=(inner-gap*3)/4;
        NSUInteger pins=_favorites.count;
        CGFloat strip=12+(inner-(cell*pins+gap*(pins?pins-1:0)))*.5;
        for(NSUInteger index=0;index<pins;index++) {
            UIView *tile=[[UIView alloc] initWithFrame:CGRectMake(strip+index*(cell+gap),36,cell,40)];
            UIView *icon=[self iconForSlot:index size:32 apps:_favorites];
            icon.frame=CGRectMake((cell-32)*.5,4,32,32);
            [tile addSubview:icon];
            [_content addSubview:tile];
            [items addObject:tile];
        }
        if(pins) {
            UIView *divider=[[UIView alloc] initWithFrame:CGRectMake(12,84,inner,hairline)];
            divider.backgroundColor=rule;
            [_content addSubview:divider];
            [dividers addObject:divider];
        }
        CGFloat top=_listTop,rowHeight=MAX(56,48/MAX(.50,_actual)),size=FMMenuStyleValue(@"menuListIconSize");
        for(NSUInteger index=0;index<3;index++) {
            UIView *row=[[UIView alloc] initWithFrame:CGRectMake(12,top+index*(rowHeight+4),inner,rowHeight)];
            row.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:
                FMHostUI()?(FMClearGlassEnabled()?.79:.88):FMReadableRowAlpha()];
            row.layer.cornerRadius=17;
            UIView *icon=[self iconForSlot:index size:size apps:apps];
            icon.frame=CGRectMake(12,(rowHeight-size)*.5,size,size);
            [row addSubview:icon];
            NSString *name=index<apps.count?FMAppCaption(apps[index]):[NSString stringWithFormat:@"应用 %lu",(unsigned long)index+1];
            UILabel *title=[manager label:name size:13 weight:UIFontWeightSemibold];
            title.numberOfLines=1;
            title.lineBreakMode=NSLineBreakByTruncatingTail;
            title.frame=CGRectMake(12+size+8,0,inner-12-size-8-26,rowHeight);
            [row addSubview:title];
            UIImageView *arrow=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
            arrow.tintColor=FMThemeColor(FMColorText);
            arrow.contentMode=UIViewContentModeScaleAspectFit;
            arrow.frame=CGRectMake(inner-4-18,(rowHeight-18)*.5,18,18);
            [row addSubview:arrow];
            [_content addSubview:row];
            [items addObject:row];
        }
        UIView *bar=[[UIView alloc] initWithFrame:CGRectMake(12,ph-44-6-28,inner,44)];
        [_content addSubview:bar];
        NSArray<NSString *> *glyphs=@[@"house.fill",@"gearshape.fill",_left?@"chevron.compact.left":@"chevron.compact.right"];
        CGFloat slot=inner/glyphs.count;
        for(NSUInteger index=0;index<glyphs.count;index++) {
            UIView *tile=[self footerTile:glyphs[index] compact:NO size:36];
            tile.frame=CGRectMake(index*slot+(slot-36)*.5,(44-36)*.5,36,36);
            [bar addSubview:tile];
            [items addObject:tile];
        }
    }
    // The pop-in order: lowest row first, and within a row the one nearest the wall.
    NSMutableArray<NSDictionary *> *entries=[NSMutableArray array];
    CGFloat wall=_left?0:pw;
    for(UIView *view in items) {
        CGRect frame=[view convertRect:view.bounds toView:_content];
        [entries addObject:@{@"view":view,@"row":@(lround(CGRectGetMidY(frame)/8)),
                             @"gap":@(fabs(CGRectGetMidX(frame)-wall))}];
    }
    _popItems=entries;
    _popDividers=dividers;
}
// The whole picture again: the drawer as a real glass shell, then the docked bead over
// it, both at real size inside a scene that is scaled to fit the card.
- (void)build {
    FMBeginPreferenceSnapshot();
    FMManager *manager=[FMManager shared];
    [_fadeTimer invalidate];
    _fadeTimer=nil;
    [_scene removeFromSuperview];
    _scene=[UIView new];
    _scene.userInteractionEnabled=NO;
    [self addSubview:_scene];
    _fit=Clamp(MIN((_openHeight-24)/MAX(1,_ph*_actual),(CGRectGetWidth(self.bounds)-16)/MAX(1,_pw*_actual)),.3,1);
    _drawer=[[UIView alloc] initWithFrame:CGRectMake(0,0,_pw,_ph)];
    _shadow=FMMenuDark()?.30:.18;
    _drawer.layer.shadowColor=UIColor.blackColor.CGColor;
    _drawer.layer.shadowRadius=18;
    _drawer.layer.shadowOffset=CGSizeMake(0,3);
    FMAddOrbBackdrop(_drawer,_left);
    _edge=[_drawer viewWithTag:9204];
    _glass=[manager glass:_drawer.bounds radius:_compact?MIN(25,_pw*.33):29 strong:YES];
    FMApplySideNotch(_glass,_drawer.layer,_left,_compact,NO);
    for(CALayer *layer in _glass.layer.sublayers)
        if([layer isKindOfClass:CAShapeLayer.class]) layer.name=@"fm.panel.rim";
    [_drawer addSubview:_glass];
    [_scene addSubview:_drawer];
    [self buildContents];
    _beadW=[manager orbWidth];
    _beadH=[manager orbHeight];
    _bead=[manager orbPreviewWithFrame:CGRectMake(0,0,_beadW,_beadH) left:_left];
    [_scene addSubview:_bead];
    CGFloat shift=0;
    _placed=FMPlaceHandles(FMOrbHandleMetrics(YES),FMOrbHandleMetrics(NO),FMOrbHandleIsCapsule(),1/_actual,_pw,_ph,
                           _ph*.5,&_beadParams,&_dropletParams,&shift);
    _drawerParams=FMDrawerNotchParams(_pw,_ph,_compact);
    _faded=NO;
    // A rebuild mid-way keeps what is on show; it must not pop the contents in again.
    _revealed=_started=_progress>=.5;
    [self applyProgress:_progress];
    [self scheduleFade];
    _builtAt=CACurrentMediaTime();
    FMEndPreferenceSnapshot();
}
- (void)placeScene {
    if(!_scene) return;
    CGFloat width=CGRectGetWidth(self.bounds),height=CGRectGetHeight(self.bounds);
    CGFloat sceneWidth=width/_fit,sceneHeight=height/_fit;
    _scene.transform=CGAffineTransformIdentity;
    _scene.bounds=CGRectMake(0,0,sceneWidth,sceneHeight);
    _scene.center=CGPointMake(width*.5,height*.5);
    _scene.transform=CGAffineTransformMakeScale(_fit,_fit);
    // Past fully open the drawer stretches toward the screen about its wall.
    CGFloat stretch=Clamp(MAX(_progress,0)-1,0,.08),visible=_pw*_actual;
    _drawer.transform=CGAffineTransformMakeScale(_actual*(1+stretch),_actual);
    CGFloat rest=_left?visible*.5:sceneWidth-visible*.5;
    _drawer.center=CGPointMake(rest+(_left?1:-1)*stretch*visible*.5,sceneHeight*.5);
    _bead.frame=CGRectMake(_left?0:sceneWidth-_beadW,(sceneHeight-_beadH)*.5,_beadW,_beadH);
}
- (CGFloat)restAlpha { return _faded?_fadedAlpha:_idleAlpha; }
// One frame at progress 0 (the docked bead) to 1 (the open drawer), as the real drawer's
// applyMorphProgress: draws it.
- (void)applyProgress:(CGFloat)progress {
    _progress=progress;
    [self syncHeight];
    if(!_glass) return;
    CGFloat raw=MAX(progress,0),t=MIN(raw,1);
    __attribute__((objc_precise_lifetime)) UIBezierPath *outline=_placed?
        FMDrawerMorphPath(_glass.bounds,_beadParams,_dropletParams,_drawerParams,_left,_compact,t):
        FMSideNotchPath(_glass.bounds,_left,_compact,NO);
    CAShapeLayer *clip=(CAShapeLayer *)_glass.layer.mask;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if([clip isKindOfClass:CAShapeLayer.class]) clip.path=outline.CGPath;
    for(CALayer *layer in _glass.layer.sublayers)
        if([layer.name isEqualToString:@"fm.panel.rim"] && [layer isKindOfClass:CAShapeLayer.class])
            ((CAShapeLayer *)layer).path=outline.CGPath;
    _drawer.layer.shadowPath=outline.CGPath;
    _drawer.layer.shadowOpacity=_shadow*FMSmooth(t/.5);
    [CATransaction commit];
    BOOL reveal=_revealed?t>=.42:t>=.5,flipped=reveal!=_revealed,still=UIAccessibilityIsReduceMotionEnabled();
    _revealed=reveal;
    if(reveal) _started=YES;
    if(flipped) {
        // With the pop-in off, or no motion wanted, the contents leave with the shell instead of waiting for it to shrink around them.
        if(!reveal && (FMPopMode()==2 || still)) _started=NO;
        if(!still) FMPopItems(_popItems,_popDividers,_left,reveal);
    }
    // Closed, nothing of the contents may remain, whatever became of their animations.
    if(raw<=.001) _started=NO;
    _content.alpha=_started?1:0;
    _edge.alpha=FMSmooth((t-.1)/.5);
    // At rest the bead is all there is: a shell clipped to its outline would show through
    // when the bead fades. Without room for the morph the two cross-fade instead.
    _drawer.hidden=raw<=.001;
    _drawer.alpha=_placed?1:FMSmooth(t);
    _bead.alpha=[self restAlpha]*(1-FMSmooth(t/.3));
    [self setNeedsLayout];
}
- (void)stopLink {
    [_link invalidate];
    _link=nil;
}
- (void)setOpen:(BOOL)open animated:(BOOL)animated {
    [self wake];
    _open=open;
    CGFloat target=open?1:0;
    if(!animated || UIAccessibilityIsReduceMotionEnabled() || !self.window) {
        [self stopLink];
        _velocity=0;
        [self applyProgress:target];
        if(!open) [self scheduleFade];
        return;
    }
    [_bead.layer removeAnimationForKey:@"opacity"];
    // The dock's springs: opening bounces, closing is firmer so it does not hang around.
    _omega=2*M_PI/(open?.46:.40);
    _zeta=open?.68:.82;
    _tick=0;
    _elapsed=0;
    if(_link) return;
    _link=[CADisplayLink displayLinkWithTarget:self selector:@selector(springFrame:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)springFrame:(CADisplayLink *)link {
    CFTimeInterval dt=_tick>0?MIN(link.timestamp-_tick,1/20.):1/60.;
    _tick=link.timestamp;
    _elapsed+=dt;
    CGFloat target=_open?1:0,x=_progress,v=_velocity;
    FMSpringStep(&x,&v,target,_omega,_zeta,dt);
    _velocity=v;
    BOOL arrived=(fabs(x-target)<.004 && fabs(v)<.15) || _elapsed>1.2;
    [self applyProgress:arrived?target:x];
    if(!arrived) return;
    _velocity=0;
    [self stopLink];
    if(!_open) [self scheduleFade];
}
- (void)tapped {
    BOOL open=!_open;
    [self setOpen:open animated:YES];
    if(self.onToggle) self.onToggle(open);
}
// Closes without ceremony, then opens with the animation: to show what a setting does.
- (void)replay {
    [self setOpen:NO animated:NO];
    [self setOpen:YES animated:YES];
    if(self.onToggle) self.onToggle(YES);
}
// Left alone the bead fades after the set time to the set opacity, and a touch brings it
// back, like the real one.
- (void)scheduleFade {
    [_fadeTimer invalidate];
    _fadeTimer=nil;
    if(!BoolPref(@"idleFade",YES) || _open || !self.window) return;
    __weak typeof(self) weakSelf=self;
    _fadeTimer=[NSTimer scheduledTimerWithTimeInterval:FMOrbStyleValue(@"fadeDelay") repeats:NO block:^(NSTimer *timer) {
        [weakSelf fade];
    }];
}
- (void)fade {
    if(_open || _link || _faded) return;
    _faded=YES;
    [UIView animateWithDuration:.45 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionAllowUserInteraction
        animations:^{ self->_bead.alpha=[self restAlpha]; } completion:nil];
}
- (void)wake {
    [_fadeTimer invalidate];
    _fadeTimer=nil;
    if(!_faded) return;
    _faded=NO;
    CGFloat t=Clamp(_progress,0,1);
    [UIView animateWithDuration:.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionAllowUserInteraction
        animations:^{ self->_bead.alpha=[self restAlpha]*(1-FMSmooth(t/.3)); } completion:nil];
}
@end

@interface FMDockSettingsController ()
@property(nonatomic,strong) FMDockPreviewView *preview;
@property(nonatomic,strong) UISegmentedControl *stateControl;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) NSLayoutConstraint *previewHeight;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *bodyRows;
@property(nonatomic,strong) NSMutableArray<UIStackView *> *groupStacks;
@property(nonatomic,strong) NSMutableArray<UIImageView *> *chevrons;
@property(nonatomic,strong) NSMutableArray<UIControl *> *headers;
@property(nonatomic,strong) UILabel *handleNote;
@property(nonatomic,weak) CAGradientLayer *backdrop;
@property(nonatomic,assign) NSInteger openGroup;
@end

@implementation FMDockSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"侧边栏";
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor=FMThemeColor(FMColorBackground);
    self.bodyRows=[NSMutableArray array];
    self.groupStacks=[NSMutableArray array];
    self.chevrons=[NSMutableArray array];
    self.headers=[NSMutableArray array];
    // The handle group is open to begin with, with the preview docked.
    self.openGroup=FMDockGroupHandle;
    FMDockPreviewView *preview=[FMDockPreviewView new];
    preview.translatesAutoresizingMaskIntoConstraints=NO;
    self.previewHeight=[preview.heightAnchor constraintEqualToConstant:190];
    preview.heightConstraint=self.previewHeight;
    __weak typeof(self) weakSelf=self;
    preview.onToggle=^(BOOL open) {
        weakSelf.stateControl.selectedSegmentIndex=open?1:0;
    };
    UISegmentedControl *state=[[UISegmentedControl alloc] initWithItems:@[@"收起",@"展开"]];
    state.translatesAutoresizingMaskIntoConstraints=NO;
    state.selectedSegmentIndex=0;
    state.accessibilityLabel=@"预览状态";
    [state addTarget:self action:@selector(previewStateChanged:) forControlEvents:UIControlEventValueChanged];
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.alwaysBounceVertical=YES;
    scroll.backgroundColor=UIColor.clearColor;
    [self.view addSubview:scroll];
    [self.view addSubview:preview];
    [self.view addSubview:state];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [preview.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [preview.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [preview.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        self.previewHeight,
        [state.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:10],
        [state.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor],
        [state.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:state.bottomAnchor constant:6],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    self.preview=preview;
    self.stateControl=state;
    self.scroll=scroll;
    [self rebuild];
}
// The card may take about half of the room, so the options stay in reach on a small phone.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self applyBackdrop];
    BOOL wide=CGRectGetWidth(self.view.bounds)>CGRectGetHeight(self.view.bounds);
    CGFloat cap=Clamp(self.view.safeAreaLayoutGuide.layoutFrame.size.height*(wide?.45:.55),120,420);
    if(fabs(self.preview.maxHeight-cap)>.5) self.preview.maxHeight=cap;
}
// Glass has to have something behind it, and a page painted one flat colour gives it
// nothing: a gentle wash of the theme is enough for the cards to read as the material
// rather than as a drawing of it.
- (void)applyBackdrop {
    CAGradientLayer *wash=self.backdrop;
    if(!wash) {
        wash=[CAGradientLayer layer];
        [self.view.layer insertSublayer:wash atIndex:0];
        self.backdrop=wash;
    }
    UIColor *base=FMThemeColor(FMColorBackground);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    wash.frame=self.view.bounds;
    wash.colors=@[(id)FMMix(base,FMAccent(),.10).CGColor,(id)base.CGColor,
                  (id)FMMix(base,FMThemeColor(FMColorGlass),.07).CGColor];
    wash.locations=@[@0,@.55,@1];
    wash.startPoint=CGPointMake(0,0);
    wash.endPoint=CGPointMake(1,1);
    [CATransaction commit];
}
// The page shows the bead itself, so the one floating over the settings steps aside.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    FMManager *manager=[FMManager shared];
    manager.dimensionsPreview=self.preview;
    manager.orbPreviewHost.hidden=YES;
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    FMManager *manager=[FMManager shared];
    if(manager.dimensionsPreview!=self.preview) return;
    manager.dimensionsPreview=nil;
    manager.orbPreviewHost.hidden=NO;
    [manager refreshOrbPreview];
}
- (void)rebuild {
    if(!self.isViewLoaded) return;
    self.view.backgroundColor=FMThemeColor(FMColorBackground);
    [self applyBackdrop];
    UIScrollView *scroll=self.scroll;
    CGFloat offset=scroll.contentOffset.y;
    [self.stack removeFromSuperview];
    [self.bodyRows removeAllObjects];
    [self.groupStacks removeAllObjects];
    [self.chevrons removeAllObjects];
    [self.headers removeAllObjects];
    UIStackView *stack=[UIStackView new];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.spacing=20;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-32],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];
    self.stack=stack;
    FMBeginPreferenceSnapshot();
    for(NSInteger group=0;group<FMDockGroupCount;group++) [self addGroup:(FMDockGroup)group];
    [self addResetCard];
    FMEndPreferenceSnapshot();
    [self applyVisibilityAnimated:NO];
    [self.preview reload];
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.scroll!=scroll || !scroll.window) return;
        [scroll layoutIfNeeded];
        CGFloat maxY=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
        [scroll setContentOffset:CGPointMake(0,MIN(offset,maxY)) animated:NO];
    });
}

// ---- rows
- (UIControl *)headerForGroup:(FMDockGroup)group {
    NSArray<NSString *> *titles=@[@"位置",@"把手",@"透明度",@"托盘"];
    NSArray<NSString *> *symbols=@[@"arrow.left.and.right",@"capsule.portrait",@"circle.lefthalf.filled",@"square.grid.2x2"];
    UIControl *row=[UIControl new];
    row.tag=group;
    UIImageSymbolConfiguration *regular=[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    UIImageSymbolConfiguration *small=[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[group] withConfiguration:regular]];
    icon.tintColor=FMThemeColor(FMColorText);
    icon.contentMode=UIViewContentModeScaleAspectFit;
    UILabel *title=FMDockLabel(titles[group],17,FMThemeColor(FMColorText));
    UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:small]];
    chevron.tintColor=FMThemeColor(FMColorSecondary);
    for(UIView *view in @[icon,title,chevron]) {
        view.translatesAutoresizingMaskIntoConstraints=NO;
        view.userInteractionEnabled=NO;
        [row addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:52],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:26],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [title.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],
        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];
    row.accessibilityLabel=titles[group];
    row.accessibilityTraits=UIAccessibilityTraitButton;
    [row addTarget:self action:@selector(headerTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.chevrons addObject:chevron];
    [self.headers addObject:row];
    return row;
}
- (UIView *)sliderRow:(NSDictionary *)option {
    UILabel *title=FMDockLabel(option[@"title"],17,FMThemeColor(FMColorText));
    UILabel *value=FMDockLabel(nil,17,FMThemeColor(FMColorSecondary));
    value.font=[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular];
    value.textAlignment=NSTextAlignmentRight;
    [value setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [value setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *line=[[UIStackView alloc] initWithArrangedSubviews:@[title,value]];
    line.axis=UILayoutConstraintAxisHorizontal;
    line.spacing=12;
    FMDockSlider *slider=[FMDockSlider new];
    slider.option=option;
    slider.valueLabel=value;
    slider.minimumValue=[option[@"min"] floatValue];
    slider.maximumValue=[option[@"max"] floatValue];
    CGFloat current=FMDockStoredValue(option);
    slider.value=current;
    slider.tintColor=FMAccent();
    value.text=FMDockValueText(option,current);
    slider.accessibilityLabel=option[@"title"];
    slider.accessibilityValue=value.text;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *column=[[UIStackView alloc] initWithArrangedSubviews:@[line,slider]];
    column.axis=UILayoutConstraintAxisVertical;
    column.spacing=6;
    return FMDockRow(column,11,YES,0);
}
- (UIView *)switchRow:(NSString *)title key:(NSString *)key defaultValue:(BOOL)defaultValue {
    UILabel *label=FMDockLabel(title,17,FMThemeColor(FMColorText));
    FMDockSwitch *toggle=[FMDockSwitch new];
    toggle.key=key;
    toggle.on=BoolPref(key,defaultValue);
    toggle.onTintColor=FMSwitchGreen();
    toggle.accessibilityLabel=title;
    [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *line=[[UIStackView alloc] initWithArrangedSubviews:@[label,toggle]];
    line.axis=UILayoutConstraintAxisHorizontal;
    line.alignment=UIStackViewAlignmentCenter;
    line.spacing=12;
    return FMDockRow(line,10,YES,52);
}
// A segmented choice under an optional title; the stored number is the chosen index.
- (UIView *)segmentRow:(NSString *)title items:(NSArray<NSString *> *)items key:(NSString *)key selected:(NSInteger)selected {
    FMDockSegments *control=[[FMDockSegments alloc] initWithItems:items];
    control.key=key;
    control.selectedSegmentIndex=selected;
    control.accessibilityLabel=title?:key;
    [control addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    if(!title) return FMDockRow(control,10,YES,52);
    UIStackView *column=[[UIStackView alloc] initWithArrangedSubviews:@[FMDockLabel(title,17,FMThemeColor(FMColorText)),control]];
    column.axis=UILayoutConstraintAxisVertical;
    column.spacing=8;
    return FMDockRow(column,10,YES,52);
}
// Rows are recorded in the order they are written and go into their group's stack only
// while that group is open (see applyVisibilityAnimated:).
- (void)add:(UIView *)row to:(UIStackView *)rows group:(FMDockGroup)group when:(FMDockWhen)when {
    [self.bodyRows addObject:@{@"view":row,@"stack":rows,@"group":@(group),@"when":@(when)}];
}
- (void)addNote:(NSString *)text to:(UIStackView *)rows group:(FMDockGroup)group {
    [self add:FMDockRow(FMDockLabel(text,13,FMThemeColor(FMColorSecondary)),10,YES,0) to:rows group:group when:FMDockWhenAlways];
}
- (void)addSlider:(NSDictionary *)option to:(UIStackView *)rows group:(FMDockGroup)group when:(FMDockWhen)when {
    [self add:[self sliderRow:option] to:rows group:group when:when];
}

// ---- groups
- (void)addGroup:(FMDockGroup)group {
    UIStackView *rows=[UIStackView new];
    rows.axis=UILayoutConstraintAxisVertical;
    [rows addArrangedSubview:[self headerForGroup:group]];
    [self.groupStacks addObject:rows];
    switch(group) {
        case FMDockGroupPosition: [self addPositionRows:rows]; break;
        case FMDockGroupHandle: [self addHandleRows:rows]; break;
        case FMDockGroupOpacity: [self addOpacityRows:rows]; break;
        default: [self addTrayRows:rows]; break;
    }
    [self.stack addArrangedSubview:FMDockCard(rows)];
}
// The bead has no place to set here: it is dragged on the screen itself.
- (void)addPositionRows:(UIStackView *)rows {
    FMDockGroup group=FMDockGroupPosition;
    [self addSlider:FMDockOption(@"orbSnapDuration",nil) to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"orbSnapDamping",nil) to:rows group:group when:FMDockWhenAlways];
    [self addNote:@"微珠的位置不在这里调：在屏幕上直接把它拖到想放的地方，松手会吸到最近的一边。上面两项管松手吸边时的快慢和回弹。" to:rows group:group];
}
- (void)addHandleRows:(UIStackView *)rows {
    FMDockGroup group=FMDockGroupHandle;
    [self add:[self segmentRow:nil items:@[@"胶囊",@"水滴"] key:@"orbHandleStyle" selected:FMOrbHandleIsCapsule()?0:1]
           to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"orbHandleReach",nil) to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"orbHandleLength",nil) to:rows group:group when:FMDockWhenAlways];
    // Only the capsule has a corner setting.
    [self addSlider:FMDockOption(@"orbCapsuleCorner",nil) to:rows group:group when:FMDockWhenCapsule];
    [self addSlider:FMDockOption(@"orbSoftness",nil) to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"orbScale",nil) to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"orbGlowLength",nil) to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"orbGlowBrightness",nil) to:rows group:group when:FMDockWhenAlways];
    [self add:[self switchRow:@"发光光条" key:@"glowLine" defaultValue:YES] to:rows group:group when:FMDockWhenAlways];
    UILabel *note=FMDockLabel(nil,13,FMThemeColor(FMColorSecondary));
    self.handleNote=note;
    [self applyHandleNote];
    [self add:FMDockRow(note,10,YES,0) to:rows group:group when:FMDockWhenAlways];
}
- (void)applyHandleNote {
    NSString *shape=FMOrbHandleIsCapsule()?
        @"圆角越小，顶边越平越方，调到最大接近正半圆；柔和度决定拉出时它和屏幕边缘之间那截水滴颈的长短。":
        @"柔和度越大，微珠和屏幕边缘连得越平缓。";
    self.handleNote.text=[shape stringByAppendingString:
        @"\n发光光条是中间那条线的另一种画法：更粗、顶亮底深、带一圈光晕；关掉就回到原来那条细线。有新版本时两种都会变红呼吸。"];
}
- (void)addOpacityRows:(UIStackView *)rows {
    FMDockGroup group=FMDockGroupOpacity;
    [self addSlider:FMDockOption(@"idleAlpha",nil) to:rows group:group when:FMDockWhenAlways];
    [self add:[self switchRow:@"停手后自动淡化" key:@"idleFade" defaultValue:YES] to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"fadeDelay",nil) to:rows group:group when:FMDockWhenFade];
    [self addSlider:FMDockOption(@"fadedOpacity",nil) to:rows group:group when:FMDockWhenFade];
    [self addNote:@"停手一阵后，收起的微珠会慢慢淡到很淡，不挡视线；手一碰就亮回来。" to:rows group:group];
}
- (void)addTrayRows:(UIStackView *)rows {
    FMDockGroup group=FMDockGroupTray;
    [self add:[self switchRow:@"精简模式（单列图标）" key:@"compactMode" defaultValue:NO] to:rows group:group when:FMDockWhenAlways];
    [self add:[self switchRow:@"图标玻璃底座" key:@"iconFrame" defaultValue:YES] to:rows group:group when:FMDockWhenCompact];
    [self addSlider:FMDockOption(@"panelScale",nil) to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"menuExtension",nil) to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"menuCornerRadius",nil) to:rows group:group when:FMDockWhenAlways];
    [self addSlider:FMDockOption(@"menuCurveSoftness",nil) to:rows group:group when:FMDockWhenAlways];
    // The two layouts each keep their own icon size; only the one in use shows.
    [self addSlider:FMDockOption(@"menuCompactIconSize",@"图标大小") to:rows group:group when:FMDockWhenCompact];
    [self addSlider:FMDockOption(@"menuListIconSize",@"图标大小") to:rows group:group when:FMDockWhenList];
    [self add:[self segmentRow:@"弹出动画" items:@[@"逐个",@"一起",@"关"] key:@"popAnimation" selected:FMPopMode()]
           to:rows group:group when:FMDockWhenAlways];
    if(@available(iOS 26.0,*)) {
        [self add:[self segmentRow:@"材质" items:@[@"标准玻璃",@"透明玻璃"] key:@"clearGlass" selected:BoolPref(@"clearGlass",NO)?1:0]
               to:rows group:group when:FMDockWhenAlways];
    }
    [self addSlider:FMDockOption(@"glassTint",nil) to:rows group:group when:FMDockWhenAlways];
    [self addNote:@"展开后，长按某个 App 再上下滑，一块玻璃镜片会跟着手指走，松手切换，拖出菜单外松手则取消。App 很多时，把手指推到列表上下边缘，列表会自己滚动。" to:rows group:group];
}
- (void)addResetCard {
    UIControl *button=[UIControl new];
    UILabel *label=FMDockLabel(@"恢复默认",17,UIColor.systemRedColor);
    label.translatesAutoresizingMaskIntoConstraints=NO;
    label.userInteractionEnabled=NO;
    [button addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [button.heightAnchor constraintEqualToConstant:52],
        [label.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:20],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:button.trailingAnchor constant:-20],
        [label.centerYAnchor constraintEqualToAnchor:button.centerYAnchor]
    ]];
    button.accessibilityLabel=@"恢复默认";
    button.accessibilityTraits=UIAccessibilityTraitButton;
    [button addTarget:self action:@selector(confirmReset) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *rows=[UIStackView new];
    rows.axis=UILayoutConstraintAxisVertical;
    [rows addArrangedSubview:button];
    [self.stack addArrangedSubview:FMDockCard(rows)];
}

// ---- what shows
- (BOOL)whenHolds:(FMDockWhen)when {
    switch(when) {
        case FMDockWhenCapsule: return FMOrbHandleIsCapsule();
        case FMDockWhenFade: return BoolPref(@"idleFade",YES);
        case FMDockWhenCompact: return BoolPref(@"compactMode",NO);
        case FMDockWhenList: return !BoolPref(@"compactMode",NO);
        default: return YES;
    }
}
// Puts the rows of the open group that apply into their card, takes every other row out,
// and turns the chevrons. Rows are added and removed rather than hidden: hiding the same
// arranged subview twice leaves a stack view holding it at no height for good.
- (void)applyVisibilityAnimated:(BOOL)animated {
    void (^apply)(void)=^{
        FMBeginPreferenceSnapshot();
        for(UIStackView *rows in self.groupStacks)
            while(rows.arrangedSubviews.count>1) [rows.arrangedSubviews.lastObject removeFromSuperview];
        for(NSDictionary *entry in self.bodyRows) {
            if([entry[@"group"] integerValue]!=self.openGroup) continue;
            if(![self whenHolds:(FMDockWhen)[entry[@"when"] integerValue]]) continue;
            UIStackView *rows=entry[@"stack"];
            UIView *row=entry[@"view"];
            row.alpha=1;
            [rows addArrangedSubview:row];
        }
        FMEndPreferenceSnapshot();
        for(NSUInteger index=0;index<self.chevrons.count;index++) {
            BOOL open=(NSInteger)index==self.openGroup;
            self.chevrons[index].transform=open?CGAffineTransformMakeRotation(M_PI_2):CGAffineTransformIdentity;
            self.headers[index].accessibilityValue=open?@"已展开":@"已收起";
        }
        if(animated) [self.view layoutIfNeeded];
    };
    if(!animated) {
        apply();
        return;
    }
    [UIView animateWithDuration:.32 delay:0 usingSpringWithDamping:.9 initialSpringVelocity:0
        options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
        animations:apply completion:nil];
}

// ---- actions
// Opening a group shows the state it is about: the tray group the open drawer, the rest the docked bead.
- (void)headerTapped:(UIControl *)header {
    NSInteger group=header.tag;
    BOOL opening=self.openGroup!=group;
    self.openGroup=opening?group:-1;
    [self applyVisibilityAnimated:YES];
    if(!opening) return;
    BOOL wantsOpen=group==FMDockGroupTray;
    [self.preview setOpen:wantsOpen animated:YES];
    self.stateControl.selectedSegmentIndex=wantsOpen?1:0;
}
- (void)previewStateChanged:(UISegmentedControl *)control {
    [self.preview setOpen:control.selectedSegmentIndex==1 animated:YES];
}
- (void)sliderChanged:(FMDockSlider *)slider {
    NSDictionary *option=slider.option;
    CGFloat step=[option[@"step"] doubleValue],value=slider.value;
    if(step>0) value=round(value/step)*step;
    value=Clamp(value,[option[@"min"] doubleValue],[option[@"max"] doubleValue]);
    slider.value=value;
    slider.valueLabel.text=FMDockValueText(option,value);
    slider.accessibilityValue=slider.valueLabel.text;
    SetPref(option[@"key"],@(value));
    [self.preview reload];
}
- (void)switchChanged:(FMDockSwitch *)toggle {
    SetPref(toggle.key,@(toggle.isOn));
    if([toggle.key isEqualToString:@"compactMode"]) FMLog(@"display-mode",toggle.isOn?@"icons":@"list");
    // The fade settings and the icon size follow these switches.
    [self applyVisibilityAnimated:YES];
    [self.preview reload];
}
- (void)segmentChanged:(FMDockSegments *)control {
    SetPref(control.key,@(control.selectedSegmentIndex));
    if([control.key isEqualToString:@"orbHandleStyle"]) {
        [self applyHandleNote];
        [self applyVisibilityAnimated:YES];
    }
    [self.preview reload];
    // Show what the pop-in setting does.
    if([control.key isEqualToString:@"popAnimation"]) {
        [self.preview replay];
        self.stateControl.selectedSegmentIndex=1;
    }
}
- (void)confirmReset {
    if(self.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"恢复侧边栏的默认设置？"
        message:@"微珠、展开菜单、透明度和弹出动画都会回到默认，主题配色和其他设置不受影响。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[FMManager shared] resetDockSettings];
        [weakSelf rebuild];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

// The old standalone entrypoint is now one Orbit module. Core owns lifecycle notifications.
@interface LCFloatingMenuModule : NSObject <LCOrbitModule>
@property(nonatomic,strong) id launchFailureObserver;
@property(nonatomic,strong) id taskMenuObserver;
@property(nonatomic,strong) id configurationObserver;
@property(nonatomic,strong) id configurationFailureObserver;
@end
@implementation LCFloatingMenuModule
- (NSString *)moduleIdentifier { return @"FloatingMenu"; }
- (void)orbitDidStartWithContext:(LCOrbitContext *)context {
    [[FMManager shared] invalidatePendingLaunch];
    [FMManager shared].orbitContext=context;
    BOOL hostUI=FMHostUI();
    if(hostUI) {
        if([LCOrbitMultitask isEnabled]) {
            NSError *error=nil;
            if(![LCOrbitMultitask setEnabled:YES error:&error]) {
                [LCOrbitMultitask setEnabled:NO error:nil];
                FMLog(@"multitask-unavailable",error.localizedDescription);
            }
        }
        __weak FMManager *manager=[FMManager shared];
        self.launchFailureObserver=[NSNotificationCenter.defaultCenter addObserverForName:LCOrbitMultitaskLaunchFailedNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                NSError *error=note.userInfo[@"error"];
                FMLog(@"multitask-launch-failed",error.localizedDescription);
                [manager showMessage:@"多任务启动失败" details:error.localizedDescription?:@"请从 LC 检查应用。"];
            }];
        self.taskMenuObserver=[NSNotificationCenter.defaultCenter addObserverForName:LCOrbitMultitaskMenuRequestedNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                [manager showMultitaskMenuExpanded:[note.userInfo[@"expanded"] boolValue]];
            }];
        self.configurationObserver=[NSNotificationCenter.defaultCenter addObserverForName:LCOrbitMultitaskConfigurationChangedNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                if(manager.launchPending &&
                   (manager.launchMultitaskMode!=[LCOrbitMultitask isEnabled] ||
                    manager.launchSystemMenuMode!=[LCOrbitMultitask usesSystemMenu] ||
                    ![[LCOrbitCore sharedCore] isModuleEnabled:@"FloatingMenu"]))
                    [manager invalidatePendingLaunch];
                if(manager.isOpen && !manager.settingsWindow &&
                   [LCOrbitMultitask shouldShowFloatingMenu]) [manager requestAppsRefresh];
                else [manager refreshUI];
            }];
        self.configurationFailureObserver=[NSNotificationCenter.defaultCenter addObserverForName:@"LCOrbitConfigurationWriteFailed"
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                NSError *error=note.userInfo[@"error"];
                FMLog(@"configuration-save-failed",error.localizedDescription);
                [manager showMessage:@"配置未保存" details:error.localizedDescription?:@"请检查 LCOrbit/config.json。"];
            }];
        FMSyncSharedTweaks(nil);
    }
    FMLog(@"dylib-loaded",hostUI?@"orbit-module context=lc-host":@"orbit-module");
    if(hostUI) FMLog(@"host-ready",@"JSON configuration and logs in Documents/LCOrbit");
    // Let the rest of TweakLoader complete before auditing loaded images.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{
        [LCOrbitTweakAudit captureSnapshot];
    });
    [[FMManager shared] installIfPossible];
    [[FMManager shared] checkOrbUpdateIfNeeded];
}
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event scene:(UIWindowScene *)scene {
    FMManager *manager=[FMManager shared];
    if([event isEqualToString:UIApplicationDidEnterBackgroundNotification] ||
       [event isEqualToString:UIApplicationWillResignActiveNotification] ||
       [event isEqualToString:UISceneWillDeactivateNotification]) {
        if(!scene || scene==manager.window.windowScene || scene==manager.settingsWindow.windowScene) {
            [manager invalidatePendingLaunch];
            if(manager.appsScroll) [manager persistAppsScroll];
            [manager cancelAppearanceCheck];
        }
        return;
    }
    if([event isEqualToString:UISceneDidDisconnectNotification]) {
        if(scene && (scene==manager.window.windowScene || scene==manager.settingsWindow.windowScene))
            [manager detachFromScene];
        return;
    }
    if([event isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) return;
    if(FMHostUI() && ([event isEqualToString:UIApplicationDidBecomeActiveNotification] ||
                    [event isEqualToString:@"orbit.retry"])) {
        NSError *error=nil;
        if(![LCOrbitStorage reloadWithError:&error]) FMLog(@"configuration-invalid",error.localizedDescription);
        if([LCOrbitMultitask isEnabled]) {
            NSError *hooksError=nil;
            if(![LCOrbitMultitask installHooksWithError:&hooksError]) FMLog(@"multitask-unavailable",hooksError.localizedDescription);
        }
        [LCOrbitMultitask refreshPresentation];
        [manager refreshUI];
        FMSyncSharedTweaks(nil);
    }
    [manager installIfPossible];
}
- (void)orbitWillStop {
    if(self.configurationFailureObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.configurationFailureObserver];
        self.configurationFailureObserver=nil;
    }
    if(self.configurationObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.configurationObserver];
        self.configurationObserver=nil;
    }
    if(self.taskMenuObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.taskMenuObserver];
        self.taskMenuObserver=nil;
    }
    if(self.launchFailureObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.launchFailureObserver];
        self.launchFailureObserver=nil;
    }
    FMManager *manager=[FMManager shared];
    if(FMHostUI()) {
        // Core has already persisted module=off. Restore native presentation
        // without erasing the user's saved multitask/menu preferences.
        [LCOrbitMultitask refreshPresentation];
        [LCOrbitMultitask forgetWindow:nil];
    }
    [manager detachFromScene];
    manager.orbitContext=nil;
}
@end
void LCFloatingMenuRegisterWithOrbit(LCOrbitCore *core) {
    FMInstallOrientationHooks();
    [core registerModule:[LCFloatingMenuModule new]];
    [LCOrbitHostSettings installWithOpenSettings:^(UIWindowScene *scene) { [[FMManager shared] openSettingsInScene:scene]; }];
}
