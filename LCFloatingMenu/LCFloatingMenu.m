// LCFloatingMenu 1.0 | LC+SS Guest overlay and opt-in LC host UI overlay
// UIKit UI is rendered in the current Guest or developer-enabled LC host UI.
// The host can opt into LC's existing LiveProcess multitasking backend.
#import <UIKit/UIKit.h>
#import "../LCOrbit/Core/LCOrbitCore.h"
#import "../LCOrbit/Core/LCOrbitHost.h"
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
#define FM_MENU_VERSION @"1.0.9"
#ifndef FM_BUILD_COMMIT
#define FM_BUILD_COMMIT @"unknown"
#endif
static NSString *const FMRepositoryURL=@"https://github.com/dompling/LC-SS-widget-export";
static NSString *const FMUpdateAPI=@"https://api.github.com/repos/dompling/LC-SS-widget-export/releases/tags/fm-latest";
static NSString *const FMUpdateCacheVersion=@"LCFloatingMenu.updateIndicator.latestVersion";
static NSString *const FMUpdateCacheTime=@"LCFloatingMenu.updateIndicator.lastAttempt";
static NSString *const FMUpdateCacheSuccess=@"LCFloatingMenu.updateIndicator.lastSuccess";
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
static LCOrbitPreferences *HostDefaults(void) { return [LCOrbitStorage preferences]; }
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

// Resolve from the overlay's scene, before considering UIScreen. Screen traits
// can lag the scene or stay Light even when the scene has switched to Dark.
static __weak UIWindowScene *FMStyleScene;
static UIUserInterfaceStyle FMLastResolvedSystemStyle=UIUserInterfaceStyleLight;
static BOOL FMValidStyle(UIUserInterfaceStyle style) {
    return style==UIUserInterfaceStyleLight || style==UIUserInterfaceStyleDark;
}
static UIUserInterfaceStyle FMSystemAppearance(void) {
    UIUserInterfaceStyle style=FMStyleScene.traitCollection.userInterfaceStyle;
    if(!FMValidStyle(style)) {
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if(![scene isKindOfClass:UIWindowScene.class] ||
               scene.activationState!=UISceneActivationStateForegroundActive) continue;
            style=((UIWindowScene *)scene).traitCollection.userInterfaceStyle;
            if(FMValidStyle(style)) break;
        }
    }
    if(!FMValidStyle(style))
        style=UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    // Retain the last resolved style during transient Unspecified traits.
    if(FMValidStyle(style)) FMLastResolvedSystemStyle=style;
    return FMLastResolvedSystemStyle;
}
static UIUserInterfaceStyle FMMenuOverride(void) {
    NSInteger mode=[HostDefaults() integerForKey:Pref(@"appearanceMode")];
    return mode==1?UIUserInterfaceStyleLight:
           mode==2?UIUserInterfaceStyleDark:UIUserInterfaceStyleUnspecified;
}
static UIUserInterfaceStyle FMMenuAppearance(void) {
    NSInteger mode=[HostDefaults() integerForKey:Pref(@"appearanceMode")];
    return mode==1?UIUserInterfaceStyleLight:mode==2?UIUserInterfaceStyleDark:FMSystemAppearance();
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
static CGFloat FMOrbScale(void) {
    return Clamp(FloatPref(@"orbScale",Clamp(FloatPref(@"orbWidth",12)/12.,.70,1.90)),.70,1.90);
}
// A mirrored, gently concave inner shoulder joins the side edge to the drawer.
// The glass and its shadow use exactly the same path.
static UIBezierPath *FMSideNotchPath(CGRect bounds, BOOL dockLeft, BOOL compact, BOOL collapsed) {
    CGFloat w=CGRectGetWidth(bounds),h=CGRectGetHeight(bounds);
    CGFloat r=MIN(compact?22:28,MIN(w*.65,h*.17));
    UIBezierPath *path=[UIBezierPath bezierPath];
    if(collapsed) {
        // One continuous reverse curve at each end keeps a narrow tab from
        // reading as a rounded rectangle. The flares remain visible at all scales.
        CGFloat flare=MIN(w*1.3,h*.32);
        [path moveToPoint:CGPointMake(w,0)];
        [path addCurveToPoint:CGPointMake(0,flare)
                controlPoint1:CGPointMake(w,flare*.65)
                controlPoint2:CGPointMake(0,flare*.35)];
        [path addLineToPoint:CGPointMake(0,h-flare)];
        [path addCurveToPoint:CGPointMake(w,h)
                controlPoint1:CGPointMake(0,h-flare*.35)
                controlPoint2:CGPointMake(w,h-flare*.65)];
    } else {
        // The screen edge is straight; two reverse curves join it to the body.
        [path moveToPoint:CGPointMake(w,0)];
        [path addCurveToPoint:CGPointMake(w-r,r)
                controlPoint1:CGPointMake(w,r*.72)
                controlPoint2:CGPointMake(w,r)];
        CGFloat inner=MIN(r,w-r);
        [path addLineToPoint:CGPointMake(inner,r)];
        [path addCurveToPoint:CGPointMake(0,r*2)
                controlPoint1:CGPointMake(0,r)
                controlPoint2:CGPointMake(0,r*1.45)];
        [path addLineToPoint:CGPointMake(0,h-r*2)];
        [path addCurveToPoint:CGPointMake(inner,h-r)
                controlPoint1:CGPointMake(0,h-r*1.45)
                controlPoint2:CGPointMake(0,h-r)];
        [path addLineToPoint:CGPointMake(w-r,h-r)];
        [path addCurveToPoint:CGPointMake(w,h)
                controlPoint1:CGPointMake(w,h-r)
                controlPoint2:CGPointMake(w,h-r*.72)];
    }
    [path closePath];
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
    rim.strokeColor=[UIColor.whiteColor colorWithAlphaComponent:
        collapsed?(FMMenuDark()?.65:.80):(FMMenuDark()?.32:.58)].CGColor;
    rim.lineWidth=collapsed?.9:.75;
    [glass.layer addSublayer:rim];
}
// One compatible, four-segment path at every phase. The free-floating
// outline is a *symmetric stadium*: its rounded top and bottom reach the
// same midpoint whether docking to the left or to the right. The side
// shoulders are grown only after the bead has snapped to the destination.
// Matching control points prevent CAPath's trapezoid/flip interpolation.
static UIBezierPath *FMOrbDragPath(CGRect bounds,BOOL left,CGFloat opened) {
    CGFloat w=CGRectGetWidth(bounds),h=CGRectGetHeight(bounds);
    CGFloat r=MIN(w*.5,h*.5);
    CGFloat flare=MIN(w*1.3,h*.32);
    CGFloat dock=1-Clamp(opened,0,1); // 0: neutral capsule; 1: docked shoulders
    CGFloat capsuleTopControl=r-r*4/3.; // cubic upper semicircle reaches y=0
    CGFloat capsuleBottomControl=h-r+r*4/3.;
    CGFloat topY=r*(1-dock);
    CGFloat innerTop=r*(1-dock)+flare*dock;
    CGFloat bottomY=(h-r)*(1-dock)+h*dock;
    UIBezierPath *path=[UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(w,topY)];
    [path addCurveToPoint:CGPointMake(0,innerTop)
            controlPoint1:CGPointMake(w,capsuleTopControl*(1-dock)+flare*.65*dock)
            controlPoint2:CGPointMake(0,capsuleTopControl*(1-dock)+flare*.35*dock)];
    [path addLineToPoint:CGPointMake(0,h-innerTop)];
    [path addCurveToPoint:CGPointMake(w,bottomY)
            controlPoint1:CGPointMake(0,capsuleBottomControl*(1-dock)+(h-flare*.35)*dock)
            controlPoint2:CGPointMake(w,capsuleBottomControl*(1-dock)+(h-flare*.65)*dock)];
    [path closePath];
    if(left) {
        CGAffineTransform mirror=CGAffineTransformMake(-1,0,0,1,w,0);
        [path applyTransform:mirror];
    }
    return path;
}
static void FMAnimateOrbPath(CALayer *layer,NSString *key,CGPathRef destination,BOOL animated) {
    if(!layer) return;
    if(animated && !UIAccessibilityIsReduceMotionEnabled()) {
        CGPathRef current=nil;
        if([key isEqualToString:@"shadowPath"])
            current=((CALayer *)layer.presentationLayer).shadowPath ?: layer.shadowPath;
        else
            current=((CAShapeLayer *)layer.presentationLayer).path ?: ((CAShapeLayer *)layer).path;
        if(current) {
            CABasicAnimation *morph=[CABasicAnimation animationWithKeyPath:key];
            morph.fromValue=(__bridge id)current;
            morph.toValue=(__bridge id)destination;
            morph.duration=.26;
            morph.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [layer addAnimation:morph forKey:@"fm.orb.shoulders"];
        }
    } else [layer removeAnimationForKey:@"fm.orb.shoulders"];
    if([key isEqualToString:@"shadowPath"]) layer.shadowPath=destination;
    else ((CAShapeLayer *)layer).path=destination;
}
static void FMAnimateOrbShoulders(UIButton *button,BOOL left,CGFloat opened,BOOL animated) {
    UIView *glass=[button viewWithTag:9202];
    CAShapeLayer *mask=(CAShapeLayer *)glass.layer.mask;
    if(![mask isKindOfClass:CAShapeLayer.class]) return;
    CAShapeLayer *rim=nil;
    for(CALayer *layer in glass.layer.sublayers)
        if([layer.name isEqualToString:@"fm.orb.rim"] && [layer isKindOfClass:CAShapeLayer.class]) {
            rim=(CAShapeLayer *)layer;break;
        }
    // Own the Bezier wrapper until all layers retain the CGPath. A borrowed
    // CGPathRef from a temporary UIBezierPath can be freed mid-animation.
    UIBezierPath *outline=FMOrbDragPath(glass.bounds,left,opened);
    CGPathRef destination=outline.CGPath;
    FMAnimateOrbPath(mask,@"path",destination,animated);
    FMAnimateOrbPath(rim,@"path",destination,animated);
    FMAnimateOrbPath(button.layer,@"shadowPath",destination,animated);
}
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

@interface UIViewController (FMOrientationUnlock)
- (UIInterfaceOrientationMask)fm_supportedInterfaceOrientations;
- (UIInterfaceOrientationMask)fm___supportedInterfaceOrientations;
- (UIInterfaceOrientationMask)fm__supportedInterfaceOrientations;
- (BOOL)fm_shouldAutorotate;
- (BOOL)fm_shouldAutorotateToInterfaceOrientation:(NSInteger)orientation;
@end

@implementation UIViewController (FMOrientationUnlock)
- (UIInterfaceOrientationMask)fm_supportedInterfaceOrientations {
    UIInterfaceOrientationMask mask = [self fm_supportedInterfaceOrientations];
    if(BoolPref(@"unlockOrientation", YES)) {
        mask |= (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscapeRight);
        mask &= ~UIInterfaceOrientationMaskLandscapeLeft;
        mask &= ~UIInterfaceOrientationMaskPortraitUpsideDown;
    }
    return mask;
}
- (UIInterfaceOrientationMask)fm___supportedInterfaceOrientations {
    if(BoolPref(@"unlockOrientation", YES)) {
        return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscapeRight);
    }
    return [self fm___supportedInterfaceOrientations];
}
- (UIInterfaceOrientationMask)fm__supportedInterfaceOrientations {
    if(BoolPref(@"unlockOrientation", YES)) {
        return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscapeRight);
    }
    return [self fm__supportedInterfaceOrientations];
}
- (BOOL)fm_shouldAutorotate {
    if(BoolPref(@"unlockOrientation", YES)) {
        return YES;
    }
    return [self fm_shouldAutorotate];
}
- (BOOL)fm_shouldAutorotateToInterfaceOrientation:(NSInteger)orientation {
    if(BoolPref(@"unlockOrientation", YES)) {
        if(orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationLandscapeRight) {
            return YES;
        }
        return NO;
    }
    return [self fm_shouldAutorotateToInterfaceOrientation:orientation];
}
@end

static void FMInstallOrientationHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        FMSwizzle(UIViewController.class, @selector(supportedInterfaceOrientations), @selector(fm_supportedInterfaceOrientations));
        SEL dunder = NSSelectorFromString(@"__supportedInterfaceOrientations");
        if(class_getInstanceMethod(UIViewController.class, dunder)) {
            FMSwizzle(UIViewController.class, dunder, @selector(fm___supportedInterfaceOrientations));
        }
        SEL single = NSSelectorFromString(@"_supportedInterfaceOrientations");
        if(class_getInstanceMethod(UIViewController.class, single)) {
            FMSwizzle(UIViewController.class, single, @selector(fm__supportedInterfaceOrientations));
        }
        FMSwizzle(UIViewController.class, @selector(shouldAutorotate), @selector(fm_shouldAutorotate));
        SEL shouldTo = NSSelectorFromString(@"shouldAutorotateToInterfaceOrientation:");
        if(class_getInstanceMethod(UIViewController.class, shouldTo)) {
            FMSwizzle(UIViewController.class, shouldTo, @selector(fm_shouldAutorotateToInterfaceOrientation:));
        }
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

@interface FMSettingsRootController : UIViewController
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,weak) UILabel *updateStatusLabel;
@property(nonatomic,assign) BOOL checkingUpdate;
- (void)rebuild;
@end
@interface FMSettingsSectionController : UIViewController
@property(nonatomic,copy) NSString *sectionKey;
@property(nonatomic,strong) UIScrollView *contentScroll;
- (instancetype)initWithSection:(NSString *)key;
- (void)rebuild;
@end

static id FMOrientationObserver=nil;
static id FMLayoutChangeObserver=nil;

@interface FMManager : NSObject <UIScrollViewDelegate>
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
@implementation FMManager
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
    [self refreshLayoutForOrientation];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.12*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self refreshLayoutForOrientation];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self refreshLayoutForOrientation];
    });
}
- (void)refreshLayoutForOrientation {
    if(!self.window) return;
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
- (CGFloat)orbWidth { return 16*FMOrbScale(); }
- (CGFloat)orbHeight { return 72*FMOrbScale(); }
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
    material.frame=surface.bounds;
    material.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    material.userInteractionEnabled=YES;
    [surface addSubview:material];
    // LC's colorful app cards and translucent TabView show through the
    // native drawer. Give only the host drawer a light readability backing.
    if(strong && FMHostUI()) {
        UIView *backing=[[UIView alloc] initWithFrame:material.contentView.bounds];
        backing.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        backing.backgroundColor=[FMThemeColor(FMColorSurface) colorWithAlphaComponent:
            clear?.42:.26];
        backing.userInteractionEnabled=NO;
        [material.contentView addSubview:backing];
    }
    if(!nativeGlass) {
        // Only older iOS receives the limited compatibility approximation.
        UIView *scrim=[[UIView alloc] initWithFrame:surface.bounds];
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
        line.backgroundColor=FMClearGlassEnabled()?FMThemeColor(FMColorText):FMAccent();
        line.layer.shadowOpacity=0;
        line.layer.shadowRadius=0;
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
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:FMUpdateAPI]];
    req.timeoutInterval=12;
    [req setValue:@"LCFloatingMenu/1.0 (background update indicator)" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    __weak typeof(self) weakSelf=self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        BOOL valid=NO;
        NSString *version=nil;
        if(!error && [(NSHTTPURLResponse *)response statusCode]==200 && data.length) {
            NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if([json isKindOfClass:NSDictionary.class]) {
                NSString *body=json[@"body"];
                for(NSString *line in [body isKindOfClass:NSString.class]?[body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]:@[]) {
                    if([line hasPrefix:@"FM_VERSION="]) version=[line substringFromIndex:11];
                }
                for(id item in json[@"assets"]) {
                    if([item isKindOfClass:NSDictionary.class] && [item[@"name"] isEqualToString:@"LCFloatingMenu.dylib"]) {
                        valid=FMVersionCompare(version?:@"",FM_MENU_VERSION)!=NSNotFound;
                        break;
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            FMManager *owner=weakSelf;
            if(!owner) return;
            owner.orbUpdateChecking=NO;
            if(!valid) return; // network failure never clears a known update
            [defaults setObject:version forKey:FMUpdateCacheVersion];
            [defaults setDouble:NSDate.date.timeIntervalSince1970 forKey:FMUpdateCacheSuccess];
            BOOL available=FMVersionCompare(version,FM_MENU_VERSION)==NSOrderedDescending;
            if(owner.orbUpdateAvailable!=available) {
                owner.orbUpdateAvailable=available;
                [owner applyOrbUpdateIndicator];
            }
        });
    }] resume];
}
- (void)scheduleOrbFade {
    [self.orbFadeTimer invalidate];
    if(!BoolPref(@"idleFade",YES) || self.orbUpdateAvailable) return;
    if(self.isOpen || !self.orb) return;
    __weak typeof(self) weakSelf=self;
    self.orbFadeTimer=[NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
        [weakSelf fadeOrb];
    }];
}
- (void)cancelOrbFade {
    [self.orbFadeTimer invalidate];
    self.orbFadeTimer=nil;
}
- (void)fadeOrb {
    if(self.isOpen || !self.orb || self.orbFaded || self.orbUpdateAvailable) return;
    self.orbFaded=YES;
    [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionAllowUserInteraction animations:^{
        self.orb.alpha=0.22;
    } completion:nil];
}
- (void)wakeOrb {
    if(!self.orb || self.isOpen) return;
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
    [self cancelOrbFade];
    [self.orb removeFromSuperview]; self.orb=nil;
    CGRect f=[self orbFrame];
    FMHitButton *button=[FMHitButton buttonWithType:UIButtonTypeCustom];
    button.docksLeft=self.left;
    button.frame=f;
    button.layer.shadowColor=FMAccent().CGColor;
    button.layer.shadowOpacity=.24;button.layer.shadowRadius=6;
    button.layer.shadowOffset=CGSizeMake(0,1);
    UIView *bead=[self glass:button.bounds radius:f.size.width*.5 strong:NO];
    FMApplySideNotch(bead,button.layer,self.left,YES,YES);
    for(CALayer *layer in bead.layer.sublayers)
        if([layer isKindOfClass:CAShapeLayer.class]) layer.name=@"fm.orb.rim";
    bead.userInteractionEnabled=NO;
    bead.tag=9202;
    [button addSubview:bead];
    UIView *line=[[UIView alloc] initWithFrame:CGRectMake(0,0,4*FMOrbScale(),
        MIN(26*FMOrbScale(),f.size.height*.55))];
    line.center=CGPointMake(f.size.width*.5,f.size.height*.5);
    line.backgroundColor=FMClearGlassEnabled()?FMThemeColor(FMColorText):FMAccent();
    line.layer.cornerRadius=line.bounds.size.width*.5;
    line.layer.cornerCurve=kCACornerCurveCircular;
    line.userInteractionEnabled=NO;
    [FMGlassContent(bead) addSubview:line];
    line.accessibilityIdentifier=@"fm.orb.update-indicator";
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
    if(g.state==UIGestureRecognizerStateBegan || g.state==UIGestureRecognizerStateChanged) {
        [self cancelOrbFade];
        self.orbFaded=NO;
        self.orb.alpha=self.orbNormalAlpha?:0.72;
        CGFloat w=self.window.bounds.size.width,h=self.window.bounds.size.height;
        CGFloat orbW=self.orbWidth,orbH=self.orbHeight;
        UIEdgeInsets safe=self.window.safeAreaInsets;
        CGFloat minX=orbW*.5,maxX=MAX(minX,w-orbW*.5);
        CGFloat minY=MAX(60,safe.top+6)+orbH/2;
        CGFloat maxY=MAX(minY,h-MAX(36,safe.bottom+8)-orbH/2);
        self.orb.center=CGPointMake(Clamp(p.x,minX,maxX),Clamp(p.y,minY,maxY));
        if(g.state==UIGestureRecognizerStateBegan)
            FMAnimateOrbShoulders(self.orb,self.left,1,YES);
        if(g.state==UIGestureRecognizerStateChanged) self.orb.alpha=1;
    } else if(g.state==UIGestureRecognizerStateEnded) {
        self.left=self.orb.center.x<self.window.bounds.size.width*.5;
        ((FMHitButton *)self.orb).docksLeft=self.left;
        self.orbY=Clamp(self.orb.center.y/self.window.bounds.size.height,.1,.9);
        SetPref(@"onLeft",@(self.left));SetPref(@"orbY",@(self.orbY));
        if(UIAccessibilityIsReduceMotionEnabled()) {
            self.orb.frame=[self orbFrame];
            [self draw];
            [self scheduleOrbFade];
        } else {
            UIButton *dragged=self.orb;
            [UIView animateWithDuration:.34 delay:0 usingSpringWithDamping:.78
                initialSpringVelocity:.25 options:UIViewAnimationOptionBeginFromCurrentState
                animations:^{dragged.frame=[self orbFrame];}
                completion:^(BOOL finished){
                    if(!finished || self.orb!=dragged) return;
                    // The neutral capsule is mirror-invariant. Once the
                    // snap finishes, grow the destination-side shoulders.
                    FMAnimateOrbShoulders(dragged,self.left,0,YES);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.25*NSEC_PER_SEC),
                        dispatch_get_main_queue(),^{
                            if(self.orb==dragged) {
                                [self draw];
                                [self scheduleOrbFade];
                            }
                        });
                }];
            [self scheduleOrbFade];
        }
    } else if(g.state==UIGestureRecognizerStateCancelled || g.state==UIGestureRecognizerStateFailed) {
        [self draw];
        [self scheduleOrbFade];
    }
}
- (void)toggle {
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
    FMLog(self.isOpen?@"menu-open":@"menu-close",nil);
    [self.orbitContext.events publish:@"orbit.floatingMenu.visibility"
                          payload:@{@"open":@(self.isOpen),@"guestID":GuestID()}];
    if(BoolPref(@"haptic",YES)) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    }
    if(!opening) {
        self.orbFaded=NO;
        self.orb.alpha=self.orbNormalAlpha?:0.72;
        [self scheduleOrbFade];
    }
    if(opening) {
        [self draw];
        if(self.panel && self.orb && !UIAccessibilityIsReduceMotionEnabled()) {
            UIView *drawer=self.panel;
            UIButton *bead=self.orb;
            CGPoint destination=drawer.center;
            NSUInteger generation=++self.morphGeneration;
            CGFloat travel=CGRectGetWidth(drawer.frame)+
                (self.left?self.window.safeAreaInsets.left:self.window.safeAreaInsets.right)+1;
            drawer.center=CGPointMake(destination.x+(self.left?-travel:travel),destination.y);
            drawer.userInteractionEnabled=NO;
            bead.alpha=0;
            self.dismissLayer.alpha=0;
            [UIView animateWithDuration:.36 delay:0 usingSpringWithDamping:.86
                initialSpringVelocity:.3 options:UIViewAnimationOptionBeginFromCurrentState
                animations:^{
                    drawer.center=destination;
                    self.dismissLayer.alpha=1;
                } completion:^(BOOL done) {
                    if(self.panel==drawer && generation==self.morphGeneration) {
                        drawer.userInteractionEnabled=YES;
                    }
                }];
        }
    } else if(self.panel && self.orb && !UIAccessibilityIsReduceMotionEnabled()) {
        UIView *drawer=self.panel;
        CGFloat travel=CGRectGetWidth(drawer.bounds)*drawer.transform.a+1;
        CGPoint destination=CGPointMake(self.left?-travel*.5:self.window.bounds.size.width+travel*.5,
                                       drawer.center.y);
        NSUInteger generation=++self.morphGeneration;
        drawer.userInteractionEnabled=NO;
        self.dismissLayer.userInteractionEnabled=NO;
        [UIView animateWithDuration:.24 delay:0 options:
            UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseInOut
            animations:^{
                drawer.center=destination;
                self.dismissLayer.alpha=0;
            } completion:^(BOOL done) {
                if(generation==self.morphGeneration && self.panel==drawer) [self draw];
            }];
    } else [self draw];
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
    UIView *icon=[self iconViewForApp:app size:36];
    icon.frame=CGRectMake(12,(height-36)*.5,36,36);icon.userInteractionEnabled=NO;
    [row addSubview:icon];
    UILabel *title=[self label:FMAppCaption(app) size:13 weight:UIFontWeightSemibold];
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
    arrow.hidden=running;
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
    CGFloat shoulder=compact?22:28;
    // Compact drawer is 76pt before scaling; only the icon column scrolls.
    // Keep the 63pt logical row hit region even when users choose 50% visual scale.
    UIEdgeInsets safe=self.window.safeAreaInsets;
    CGFloat usableWidth=bounds.size.width-safe.left-safe.right;
    CGFloat pw=MIN(small?(compact?76:240):346,usableWidth-24);
    if(pw<=0) return;
    // A real side drawer: apps and actions share one continuous vertical
    // capsule. Heights depend on the number of visible guests and footer keys.
    NSUInteger appCount=[self visibleApps].count;
    // Compact drawer has exactly one footer control: LC home.
    NSUInteger compactActions=1;
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
        self.panelShowsHeader=small && !compact && !tight;
        footerHeight=compact?(tight?MAX(50,44/actualScale)+4:10+compactActions*63+3):
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
        [shadow addGestureRecognizer:settingsHold];
        shadow.accessibilityHint=@"长按打开微珠菜单设置";
    }
    BOOL night=FMMenuDark();
    UIColor *shadowTint=small?FMAccent():UIColor.blackColor;
    shadow.layer.shadowColor=shadowTint.CGColor;
    shadow.layer.shadowOpacity=small?(night?.52:.24):.18;
    shadow.layer.shadowRadius=small?18:22;
    shadow.layer.shadowOffset=CGSizeMake(0,3);
    // Both layouts share the same inward-curved side-notch silhouette.
    CGFloat radius=small?(compact?MIN(25,pw*.33):29):32;
    UIView *glass=[self glass:shadow.bounds radius:radius strong:YES];
    if(small) {
        FMApplySideNotch(glass,shadow.layer,self.left,compact,NO);
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
            // around the app icon so compact/single-task tiles feel lighter.
            if(FMHostUI()) {
                UIView *backing=[UIView new];
                backing.translatesAutoresizingMaskIntoConstraints=NO;
                backing.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:
                    FMClearGlassEnabled()?.64:.74];
                backing.layer.cornerRadius=14;
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
            UIView *icon=[self iconViewForApp:app size:46];
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
                [icon.widthAnchor constraintEqualToConstant:46],
                [icon.heightAnchor constraintEqualToConstant:46]
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
    NSArray *apps=[self visibleApps];
    NSMutableArray *pinned=[NSMutableArray array];
    for(NSString *path in [self favorites]) for(NSDictionary *item in apps)
        if(([path isEqualToString:FMAppKey(item)] || [path isEqualToString:item[@"path"]]) && pinned.count<4) { [pinned addObject:item]; break; }
    if(!pinned.count) for(NSDictionary *item in apps) {
        if(pinned.count==4) break;
        [pinned addObject:item];
    }
    CGFloat gap=4,cell=(inner-gap*3)/4;
    for(NSUInteger i=0;i<pinned.count;i++) {
        NSDictionary *app=pinned[i];
        BOOL compact=BoolPref(@"compactMode",NO);
        UIControl *tile=[[UIControl alloc] initWithFrame:
            CGRectMake(12+i*(cell+gap),(compact?5:8)+(compact?22:28),cell,compact?48:40)];
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
- (void)buildAppFooter:(UIView *)glass {
    BOOL compact=BoolPref(@"compactMode",NO);
    NSMutableArray<NSArray*> *items=[NSMutableArray array];
    if(compact) {
        // Compact mode exposes only the return-home control in its footer.
        // Per-running-app close badges in the icon list are unaffected.
        [items addObject:@[@"house.fill",NSStringFromSelector(@selector(compactReturnHome)),@"返回首页"]];
    } else {
        if([LCOrbitMultitask isEnabled]) {
            [items addObject:@[@"house.fill",NSStringFromSelector(@selector(goHome)),@"返回 LC，保留运行任务"]];
            [items addObject:@[@"xmark.circle",NSStringFromSelector(@selector(closeMultitaskGuest)),@"关闭当前任务"]];
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
    [FMGlassContent(glass) addSubview:footer];
    if(compact) {
        // Keep one continuous drawer shell rather than nesting another
        // pill-shaped control panel inside it.
        UIView *separator=[[UIView alloc] initWithFrame:CGRectMake(13,0,
                                               footer.bounds.size.width-26,.8)];
        separator.backgroundColor=[FMThemeColor(FMColorBorder) colorWithAlphaComponent:.55];
        [footer addSubview:separator];
    }
    CGFloat slot=compact?height-4:footer.bounds.size.width/items.count;
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
        tile.layer.cornerRadius=tileSize*.24;
        tile.backgroundColor=FMClearGlassEnabled()?
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
        glyph.tintColor=FMClearGlassEnabled()?FMThemeColor(FMColorText):FMAccent();
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
        initWithTitle:@"完成" style:UIBarButtonItemStyleDone
        target:self action:@selector(closeSettings)];
    settings.rootViewController=nav;
    self.settingsNavigation=nav;
    self.settingsWindow=settings;
    [settings makeKeyAndVisible];
    FMLog(@"settings-open",@"navigation-window");
}
- (void)closeSettings {
    if(!self.settingsWindow) return;
    UIWindow *prior=self.previousKeyWindow;
    UIWindow *old=self.settingsWindow;
    UIWindowScene *scene=old.windowScene;
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
- (void)updateSettingsContent {
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
        [self settingSwitch:s title:@"精简模式（单列图标）" key:@"compactMode" defaultValue:NO tag:16];
        [self settingScaleControl:s];
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
        [self section:@"屏幕与旋转" sub:@"开启后跟随设备自由进入向左横屏，并锁定禁止向右横屏，完美契合短视频与单向应用。" in:s];
        [self settingSwitch:s title:@"开启向左横屏自适应" key:@"unlockOrientation" defaultValue:YES tag:22];
        [self spacer:s size:14];
        [self section:@"悬浮控件" sub:nil in:s];
        [self settingSwitch:s title:@"触觉反馈" key:@"haptic" defaultValue:YES tag:1];
        [self settingSwitch:s title:@"自动淡化" key:@"idleFade" defaultValue:YES tag:21];
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
    // Unspecified lets UIKit inherit subsequent scene changes in System mode.
    self.overlayView.overrideUserInterfaceStyle=override;
    if(self.settingsWindow) {
        changed=changed || self.settingsWindow.overrideUserInterfaceStyle!=override;
        self.settingsWindow.overrideUserInterfaceStyle=override;
    }
    if(!changed) return;
    if(self.settingsWindow) [self updateSettingsContent];
    else [self draw];
    FMLog(@"system-appearance",[NSString stringWithFormat:@"scene=%@ menu=%@ mode=%ld",
        style==UIUserInterfaceStyleDark?@"dark":@"light",
        renderedStyle==UIUserInterfaceStyleDark?@"dark":@"light",
        (long)[HostDefaults() integerForKey:Pref(@"appearanceMode")]]);
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
    [slider addTarget:self action:@selector(sliderFinished:)
        forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [self addRow:slider height:28 to:s];
}
- (void)orbScaleControl:(UIStackView *)stack {
    UIStackView *heading=[UIStackView new];
    heading.axis=UILayoutConstraintAxisHorizontal;
    UILabel *name=[self label:@"微珠缩放" size:14 weight:UIFontWeightMedium];
    UILabel *percent=[self label:[NSString stringWithFormat:@"%.0f%%",100*FMOrbScale()]
        size:13 weight:UIFontWeightSemibold];
    percent.textColor=FMThemeColor(FMColorSecondary);
    percent.textAlignment=NSTextAlignmentRight;
    [heading addArrangedSubview:name];
    [heading addArrangedSubview:percent];
    [percent.widthAnchor constraintEqualToConstant:65].active=YES;
    [self addRow:heading height:29 to:stack];
    UISlider *slider=[UISlider new];
    slider.minimumValue=.70; slider.maximumValue=1.90;
    slider.value=FMOrbScale();slider.tag=11;slider.tintColor=FMAccent();
    slider.accessibilityLabel=@"微珠缩放";
    objc_setAssociatedObject(slider,@selector(sliderChanged:),percent,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sliderFinished:)
        forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [self addRow:slider height:34 to:stack];
}
- (void)settingScaleControl:(UIStackView *)stack {
    UIStackView *heading=[UIStackView new];
    heading.axis=UILayoutConstraintAxisHorizontal;
    heading.distribution=UIStackViewDistributionFill;
    UILabel *name=[self label:@"弹出菜单缩放" size:14 weight:UIFontWeightMedium];
    UILabel *percent=[self label:
        [NSString stringWithFormat:@"%.0f%%",100*Clamp(FloatPref(@"panelScale",1.0),.50,1.20)]
        size:13 weight:UIFontWeightSemibold];
    percent.textColor=FMThemeColor(FMColorSecondary);
    percent.textAlignment=NSTextAlignmentRight;
    [heading addArrangedSubview:name];
    [heading addArrangedSubview:percent];
    [percent.widthAnchor constraintEqualToConstant:65].active=YES;
    [self addRow:heading height:29 to:stack];
    UISlider *slider=[UISlider new];
    slider.minimumValue=.50;slider.maximumValue=1.20;
    slider.value=Clamp(FloatPref(@"panelScale",1.0),.50,1.20);
    slider.tag=14;slider.tintColor=FMAccent();
    slider.accessibilityLabel=@"弹出菜单缩放";
    objc_setAssociatedObject(slider,@selector(sliderChanged:),percent,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addRow:slider height:34 to:stack];
}
- (void)section:(NSString *)title sub:(NSString *)sub in:(UIStackView *)stack {
    UILabel *heading=[self label:title size:14 weight:UIFontWeightSemibold];
    [stack addArrangedSubview:heading];
    if(sub.length) {
        UILabel *description=[self label:sub size:11 weight:UIFontWeightRegular];
        description.textColor=FMThemeColor(FMColorSecondary);
        [stack addArrangedSubview:description];
    }
}
- (void)settingsPage:(UIStackView*)s {
    [self section:@"显示布局" sub:nil in:s];
    [self settingSwitch:s title:@"精简模式 · 只显示 App 图标" key:@"compactMode" defaultValue:NO tag:16];
    [self settingScaleControl:s];
    [self spacer:s size:8];
    [self section:@"基础交互" sub:nil in:s];
    [self settingSwitch:s title:@"最近打开的 App 置顶"
                 key:@"recentAppsFirst" defaultValue:NO tag:20];
    [self settingSwitch:s title:@"触觉反馈" key:@"haptic" defaultValue:YES tag:1];
    [self settingSwitch:s title:@"自动淡化" key:@"idleFade" defaultValue:YES tag:21];
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
    SetPref(dark?@"accentDark":@"accentLight",hex);
    // Native UIColorWell retains the picker while the user chooses colors.
    // Refresh the settings surface only after it is dismissed.
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
    [self spacer:s size:12];
    [self section:@"玻璃与微珠" sub:nil in:s];
    [self settingSwitch:s title:@"全菜单透明玻璃（Clear）" key:@"clearGlass" defaultValue:NO tag:18];
    [self settingSlider:s title:@"收起透明度" key:@"idleAlpha" min:.20 max:1 def:.72 tag:10];
    [self orbScaleControl:s];
    [self settingSlider:s title:@"玻璃主题着色增强" key:@"glassTint" min:0 max:.15 def:0 tag:13];
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
        case 16:key=@"compactMode";break;
        case 20:key=@"recentAppsFirst";break;
        case 22:key=@"unlockOrientation";break;
        case 21: {
            key=@"idleFade";
            if(!sw.isOn) {
                [self cancelOrbFade];
                self.orbFaded=NO;
                self.orb.alpha=self.orbNormalAlpha?:0.72;
            } else {
                [self scheduleOrbFade];
            }
            break;
        }
        case 18:key=@"clearGlass";break;
        case 4:key=AppPref();break;
        default:return;
    }
    SetPref(key,@(sw.isOn));
    if(sw.tag==20) {
        if(sw.isOn) { self.appsScrollOffset=0; [self rememberCurrentApp]; }
        FMLog(@"recent-apps-first",sw.isOn?@"on":@"off");
    }
    if(sw.tag==3||sw.tag==7||sw.tag==8||sw.tag==18) [self draw];
    if(sw.tag==16) FMLog(@"display-mode",sw.on?@"icons":@"list");
}
- (void)sliderChanged:(UISlider*)slider {
    NSString *key=slider.tag==14?@"panelScale":slider.tag==10?@"idleAlpha":
        slider.tag==11?@"orbScale":
        slider.tag==13?@"glassTint":
        slider.tag==12?[@"appAlpha." stringByAppendingString:GuestID()]:nil;
    if(!key) return;
    SetPref(key,@(slider.value));
    if(slider.tag==14 || slider.tag==11) {
        UILabel *value=objc_getAssociatedObject(slider,@selector(sliderChanged:));
        value.text=[NSString stringWithFormat:@"%.0f%%",round(slider.value*100)];
        slider.accessibilityValue=value.text;
    }
    if(slider.tag==10 || slider.tag==12) {
        CGFloat alpha=BoolPref([@"override." stringByAppendingString:GuestID()],NO)?
            FloatPref([@"appAlpha." stringByAppendingString:GuestID()],FloatPref(@"idleAlpha",.72)):
            FloatPref(@"idleAlpha",.72);
        self.orb.alpha=alpha;
    }
}
- (void)sliderFinished:(UISlider*)slider {
    if(slider.tag==11||slider.tag==13) [self draw];
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
    
    UILabel *label=[self label:@"恢复默认设置" size:16 weight:UIFontWeightMedium];
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
    button.accessibilityLabel=@"恢复默认设置";
    [button addTarget:self action:@selector(resetStyle) forControlEvents:UIControlEventTouchUpInside];
    [self addRow:row height:65 to:stack];
}
- (void)resetStyle {
    SetPref(@"idleAlpha",@(.72));SetPref(@"orbScale",@(1.0));
    SetPref(@"showRestart",@YES);SetPref(@"haptic",@YES);
    SetPref(@"recentAppsFirst",@NO);
    SetPref(@"glassTint",@(0));SetPref(@"clearGlass",@NO);
    SetPref(@"appearanceMode",@(0));
    SetPref(@"unlockOrientation",@YES);
    for(NSString *key in @[@"accentLight",@"accentDark",@"theme",@"preferDarkIcons",@"orbWidth"]) {
        [HostDefaults() removeObjectForKey:Pref(key)];
    }
    SetPref(@"compactMode",@NO);SetPref(@"panelScale",@(1.0));
    
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
    [self rebuild];
}
- (UIControl *)navigationRow:(NSString *)name subtitle:(NSString *)subtitle
                     symbol:(NSString *)symbol badgeColor:(UIColor *)badgeColor action:(SEL)action {
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
    if(action) [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    else {arrow.hidden=YES;row.userInteractionEnabled=NO;}
    if(action==@selector(checkForUpdates)) self.updateStatusLabel=detail;
    row.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",name,subtitle];
    row.accessibilityTraits=action?UIAccessibilityTraitButton:UIAccessibilityTraitStaticText;
    return row;
}
- (void)openRepository {
    NSURL *url=[NSURL URLWithString:FMRepositoryURL];
    if(url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
- (void)presentUpdateResult:(NSString *)title message:(NSString *)message showRepository:(BOOL)showRepository {
    if(!self.view.window) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    if(showRepository) [alert addAction:[UIAlertAction actionWithTitle:@"查看 GitHub"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self openRepository];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)checkForUpdates {
    if(self.checkingUpdate) return;
    self.checkingUpdate=YES;
    self.updateStatusLabel.text=@"正在检查最新发布版…";
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:FMUpdateAPI]];
    request.timeoutInterval=15;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"LCFloatingMenu/1.0" forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf=self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) owner=weakSelf;
            if(!owner) return;
            owner.checkingUpdate=NO;
            owner.updateStatusLabel.text=@"检查微珠最新发布版";
            if(error || [(NSHTTPURLResponse *)response statusCode]!=200) {
                [owner presentUpdateResult:@"检查更新失败" message:error.localizedDescription?:@"无法获取 GitHub 最新发布信息。" showRepository:YES];return;
            }
            NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if(![json isKindOfClass:NSDictionary.class]) return;
            NSString *body=json[@"body"];
            NSString *version=nil,*commit=nil;
            if([body isKindOfClass:NSString.class]) for(NSString *line in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                if([line hasPrefix:@"FM_VERSION="]) version=[line substringFromIndex:11];
                if([line hasPrefix:@"FM_COMMIT="]) commit=[line substringFromIndex:10];
            }
            NSDictionary *asset=nil;
            for(id item in json[@"assets"]) if([item isKindOfClass:NSDictionary.class] &&
                [item[@"name"] isEqualToString:@"LCFloatingMenu.dylib"]) {asset=item;break;}
            NSString *digest=asset[@"digest"],*link=asset[@"browser_download_url"];
            if(commit.length!=40 || !version.length || ![link hasPrefix:@"https://github.com/dompling/LC-SS-widget-export/releases/download/"] ||
               ![digest isKindOfClass:NSString.class] || digest.length!=71) {
                [owner presentUpdateResult:@"发布信息不完整" message:@"缺少版本、下载地址或 SHA-256 校验值，已取消更新。" showRepository:YES];return;
            }
            if([version compare:FM_MENU_VERSION options:NSNumericSearch]!=NSOrderedDescending) {
                [owner presentUpdateResult:@"已是最新版本" message:[NSString stringWithFormat:@"当前 v%@，最新 v%@。",FM_MENU_VERSION,version] showRepository:NO];return;
            }
            if(!FMHostUI()) {
                [owner presentUpdateResult:@"发现新版本" message:@"请返回 LC 主界面，在微珠设置中心安装更新。" showRepository:YES];return;
            }
            UIAlertController *confirm=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"升级微珠至 v%@？",version]
                message:@"将下载并校验官方 dylib，备份旧版后替换 LC 私有插件。更新后仍需在 LC 原生 Tweaks 页面重新签名，并重启相关应用。不会自动替换共享或专属插件副本。"
                preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"下载并安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                if(owner.checkingUpdate) return;
                owner.checkingUpdate=YES;
                owner.updateStatusLabel.text=@"下载并校验插件中…";
                NSMutableURLRequest *download=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:link]];
                download.timeoutInterval=40;
                [[[NSURLSession sharedSession] dataTaskWithRequest:download completionHandler:^(NSData *binary,NSURLResponse *resp,NSError *err) {
                    NSError *installError=nil;
                    BOOL success=NO;
                    if(!err && [(NSHTTPURLResponse *)resp statusCode]==200 && binary.length>0)
                        success=[LCOrbitPluginUpdater installDownloadedPlugin:binary expectedSHA256:digest error:&installError];
                    dispatch_async(dispatch_get_main_queue(),^{
                        owner.checkingUpdate=NO;
                        owner.updateStatusLabel.text=@"检查微珠最新发布版";
                        [owner presentUpdateResult:success?@"插件已下载并替换":@"更新未完成"
                            message:success?@"已备份旧插件并安装新版本。请前往 LC 原生 Tweaks 页面重新签名插件，然后重启 LC 和相关 Guest。共享及专属插件需单独更新。":
                            (installError.localizedDescription?:err.localizedDescription?:@"下载或替换失败，请检查网络与插件目录。")
                            showRepository:!success];
                    });
                }] resume];
            }]];
            if(owner.view.window) [owner presentViewController:confirm animated:YES completion:nil];
        });
    }] resume];
}
- (void)openApps {
    FMSettingsSectionController *detail=[[FMSettingsSectionController alloc] initWithSection:@"apps"];
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
        UIControl *shared=[self navigationRow:@"插件管理中心" subtitle:@"按 App 分配、启停、备份和批量共享"
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
                           @"apps":@"应用管理",@"diagnostics":@"诊断与日志"};
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
    [[FMManager shared] populateSettingsCategory:self.sectionKey stack:stack];
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.contentScroll!=scroll || !scroll.window) return;
        [scroll layoutIfNeeded];
        CGFloat maxY=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
        [scroll setContentOffset:CGPointMake(0,MIN(offset,maxY)) animated:NO];
    });
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
