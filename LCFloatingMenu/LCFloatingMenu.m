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
#define FM_MENU_VERSION @"1.0.0"
#ifndef FM_BUILD_COMMIT
#define FM_BUILD_COMMIT @"unknown"
#endif
static NSString *const FMRepositoryURL=@"https://github.com/dompling/LC-SS-widget-export";
static NSString *const FMReleasesURL=@"https://github.com/dompling/LC-SS-widget-export/releases";
static NSString *const FMUpdateAPI=@"https://api.github.com/repos/dompling/LC-SS-widget-export/releases/latest";
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
static CGFloat FMOrbScale(void) {
    return Clamp(FloatPref(@"orbScale",Clamp(FloatPref(@"orbWidth",12)/12.,.70,1.90)),.70,1.90);
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

@interface FMHitButton : UIButton @end
@implementation FMHitButton
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds,-14,-10),p);
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

@interface FMManager : NSObject <UIScrollViewDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *overlayView;
@property(nonatomic,strong) LCOrbitContext *orbitContext;
@property(nonatomic,strong) UIButton *orb;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,weak) UIColorWell *lightColorWell;
@property(nonatomic,weak) UIColorWell *darkColorWell;
@property(nonatomic,strong) UIView *dismissLayer;
@property(nonatomic,strong) NSMutableArray<UIView*> *manageRows;
@property(nonatomic,weak) UIScrollView *settingsScroll;
@property(nonatomic,weak) UIScrollView *appsScroll;
@property(nonatomic,assign) BOOL appsScrollRestorePending;
@property(nonatomic,assign) BOOL appsRefreshScheduled;
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
@property(nonatomic,copy) NSString *page;
@property(nonatomic,strong) NSArray<NSDictionary*> *apps;
+ (instancetype)shared;
- (void)installIfPossible;
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
- (void)closeSettings;
- (void)populateSettingsCategory:(NSString *)category stack:(UIStackView *)stack;
- (void)updateSettingsContent;
- (void)appendResetStyleRow:(UIStackView *)stack;
- (void)launchApp:(NSDictionary *)app;
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
    FMLog(@"overlay-ready",[NSString stringWithFormat:@"available=%lu context=%@",
        (unsigned long)self.apps.count,FMHostUI()?@"lc-host":@"guest"]);
    [self draw];
    [self scheduleAppearanceCheck];
}
- (CGFloat)orbWidth { return 12*FMOrbScale(); }
- (CGFloat)orbHeight { return BoolPref(@"roundOrb",NO)?self.orbWidth:38*FMOrbScale(); }
- (CGRect)orbFrame {
    CGRect b=self.window.bounds;
    CGFloat w=self.orbWidth,h=self.orbHeight;
    CGFloat x=self.left?-w*.16:b.size.width-w*.84;
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
        // Use the SDK-native UIKit API instead of a dynamically allocated
        // effect with simulated gradient layers obscuring its output.
        // Clear applies to the entire drawer as well as the edge handle.
        UIGlassEffect *glassEffect=[UIGlassEffect effectWithStyle:
            clear?UIGlassEffectStyleClear:UIGlassEffectStyleRegular];
        glassEffect.interactive=!strong;
        glassEffect.tintColor=[(clear?FMAccent():FMThemeColor(FMColorGlass))
                               colorWithAlphaComponent:clear?FMClearGlassTintStrength():FMGlassTintStrength()];
        effect=glassEffect;
        nativeGlass=YES;
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
    self.appsScroll=nil;
    self.appsScrollRestorePending=NO;
    [self.panel removeFromSuperview]; self.panel=nil;
    [self.dismissLayer removeFromSuperview]; self.dismissLayer=nil;
}
- (void)drawOrb {
    [self.orb removeFromSuperview]; self.orb=nil;
    CGRect f=[self orbFrame];
    UIButton *button=[FMHitButton buttonWithType:UIButtonTypeCustom];
    button.frame=f;
    button.layer.shadowColor=FMAccent().CGColor;
    button.layer.shadowOpacity=.24;button.layer.shadowRadius=6;
    button.layer.shadowOffset=CGSizeMake(0,1);
    UIView *bead=[self glass:button.bounds radius:f.size.width*.5 strong:NO];
    bead.userInteractionEnabled=NO;
    bead.tag=9202;
    [button addSubview:bead];
    UIView *line=[[UIView alloc] initWithFrame:CGRectMake(0,0,2.5*FMOrbScale(),14*FMOrbScale())];
    line.center=CGPointMake(f.size.width*.5,f.size.height*.5);
    line.backgroundColor=FMClearGlassEnabled()?FMThemeColor(FMColorText):FMAccent();
    line.layer.cornerRadius=1.25;line.userInteractionEnabled=NO;
    [FMGlassContent(bead) addSubview:line];
    CGFloat alpha=BoolPref([@"override." stringByAppendingString:GuestID()],NO)?
        FloatPref([@"appAlpha." stringByAppendingString:GuestID()],FloatPref(@"idleAlpha",.72)):
        FloatPref(@"idleAlpha",.72);
    button.alpha=self.isOpen?1:Clamp(alpha,.16,1);
    button.accessibilityLabel=@"LC 悬浮菜单";
    button.accessibilityHint=@"轻触展开，拖动移动，长按显示快捷操作";
    button.accessibilityTraits=UIAccessibilityTraitButton;
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
    if(!self.isOpen && BoolPref(@"autoFade",YES)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{
            if(self.orb==button && !self.isOpen && !UIAccessibilityIsReduceMotionEnabled()) {
                [UIView animateWithDuration:.42 animations:^{
                    BOOL stealth=BoolPref([@"override." stringByAppendingString:GuestID()],NO) &&
                                 BoolPref([@"stealth." stringByAppendingString:GuestID()],NO);
                    bead.transform=CGAffineTransformMakeScale(stealth?.18:.32,.88);
                    line.alpha=stealth?.12:.4;
                }];
            }
        });
    }
}
- (void)hold:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan) return;
    if(BoolPref(@"haptic",YES)) [[[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    if(!self.isOpen) {
        [self loadAppsScroll];
        self.isOpen=YES;
    }
    self.page=@"apps";self.apps=InstalledApps();
    [self draw];
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
        [self.overlayView bringSubviewToFront:self.orb];
    }
}
- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint p=[g locationInView:self.overlayView];
    if(g.state==UIGestureRecognizerStateBegan || g.state==UIGestureRecognizerStateChanged) {
        CGFloat w=self.window.bounds.size.width,h=self.window.bounds.size.height;
        CGFloat orbW=self.orbWidth,orbH=self.orbHeight;
        CGFloat minX=orbW*.35, maxX=MAX(minX,w-minX);
        CGFloat minY=60+orbH/2, maxY=MAX(minY,h-36-orbH/2);
        self.orb.center=CGPointMake(Clamp(p.x,minX,maxX),Clamp(p.y,minY,maxY));
        if(g.state==UIGestureRecognizerStateChanged) self.orb.alpha=1;
    } else if(g.state==UIGestureRecognizerStateEnded) {
        self.left=self.orb.center.x < self.window.bounds.size.width*.5;
        self.orbY=Clamp(self.orb.center.y/self.window.bounds.size.height,.1,.9);
        SetPref(@"onLeft",@(self.left)); SetPref(@"orbY",@(self.orbY));
        [UIView animateWithDuration:.36 delay:0 usingSpringWithDamping:.74
             initialSpringVelocity:.35 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.orb.frame=[self orbFrame];
             } completion:^(BOOL done){[self draw];}];
    }
}
- (void)toggle {
    BOOL opening=!self.isOpen;
    if(opening) [self loadAppsScroll];
    else [self persistAppsScroll];
    self.isOpen=opening; self.page=@"apps";
    if(self.isOpen) self.apps=InstalledApps();
    FMLog(self.isOpen?@"menu-open":@"menu-close",nil);
    [self.orbitContext.events publish:@"orbit.floatingMenu.visibility"
                          payload:@{@"open":@(self.isOpen),@"guestID":GuestID()}];
    if(BoolPref(@"haptic",YES)) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    }
    [self draw];
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
    if(current || blocked) {
        CGFloat side=MAX(13,MIN(18,size*.36));
        UIImageView *mark=[[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:current?@"checkmark.circle.fill":@"exclamationmark.circle.fill"]];
        mark.frame=CGRectMake(size-side-1,size-side-1,side,side);
        mark.backgroundColor=FMThemeColor(FMColorSurface);
        mark.tintColor=current?FMAccent():FMThemeColor(FMColorSecondary);
        mark.layer.cornerRadius=side*.5;mark.clipsToBounds=YES;
        mark.userInteractionEnabled=NO;
        [box addSubview:mark];
    }
    return box;
}
- (UIView *)appRow:(NSDictionary *)app {
    // Standard mode extends the drawer without changing its optical material.
    UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,282,60)];
    row.backgroundColor=UIColor.clearColor;
    row.layer.cornerRadius=17;
    // Localized contrast only under list text, not behind the entire glass.
    row.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:
        FMHostUI()?(FMClearGlassEnabled()?.79:.88):FMReadableRowAlpha()];
    UIView *icon=[self iconViewForApp:app size:46];
    icon.frame=CGRectMake(8,7,46,46);icon.userInteractionEnabled=NO;
    [row addSubview:icon];
    UILabel *title=[self label:FMAppCaption(app) size:15 weight:UIFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints=NO;
    title.numberOfLines=1;
    title.lineBreakMode=NSLineBreakByTruncatingTail;
    [row addSubview:title];
    BOOL current=[LCOrbitGuestService isCurrentGuest:app];
    BOOL running=[LCOrbitMultitask isRunningGuest:app];
    UIImageView *arrow=[[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:current?@"checkmark":@"chevron.right"]];
    arrow.translatesAutoresizingMaskIntoConstraints=NO;
    arrow.tintColor=FMThemeColor(FMColorText);
    arrow.contentMode=UIViewContentModeScaleAspectFit;
    arrow.hidden=running;
    [row addSubview:arrow];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [title.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:arrow.leadingAnchor constant:-9],
        [arrow.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [arrow.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [arrow.widthAnchor constraintEqualToConstant:9],
        [arrow.heightAnchor constraintEqualToConstant:13]
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
    row.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [container addSubview:row];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeCustom];
    close.frame=CGRectMake(234,8,44,44);
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
    // Compact drawer is 76pt before scaling; only the icon column scrolls.
    // Its invisible row hit target remains >= 44pt even at 75% scale.
    CGFloat pw=MIN(small?(compact?76:310):346,bounds.size.width-24);
    // A real side drawer: apps and actions share one continuous vertical
    // capsule. Heights depend on the number of visible guests and footer keys.
    NSUInteger appCount=[self visibleApps].count;
    // Host UI has Settings and Collapse, not Home/Restart.
    NSUInteger compactActions=hostUI?([LCOrbitMultitask isEnabled]?4:2):(3+(BoolPref(@"compactRestart",NO)?1:0));
    CGFloat footerHeight=compact?(16+compactActions*63+12):74;
    CGFloat target=small?(compact?MIN(566,20+MAX(1,MIN(appCount,5))*65+footerHeight+12):
        MIN(475,147+65*MIN(appCount,5)+footerHeight)):610;
    if([self.page isEqualToString:@"manage"]) target=620;
    if([self.page isEqualToString:@"diy"]) target=675;
    CGFloat ph=MIN(available,target);
    if(!isfinite(ph) || ph<=0 || !isfinite(pw) || pw<=0) return;
    if(hostUI && small) {
        FMLog(@"panel-layout",[NSString stringWithFormat:@"context=lc-host mode=%@ size=%.0fx%.0f safeBottom=%.0f actions=%lu apps=%lu",
            compact?@"compact":@"normal",pw,ph,safeBottom,
            (unsigned long)(compact?compactActions:2),(unsigned long)appCount]);
    }
    CGFloat desiredScale=small?Clamp(FloatPref(@"panelScale",1.0),.75,1.20):1.0;
    // Cap the visual bounds: transforms also affect UIKit hit testing.
    CGFloat actualScale=MIN(desiredScale,MIN((bounds.size.width-20)/pw,
                                               available/MAX(1,ph)));
    if(!isfinite(actualScale) || actualScale<=0) return;
    actualScale=MAX(.60,actualScale);
    CGFloat visualW=pw*actualScale, visualH=ph*actualScale;
    CGFloat centerX=self.left?(10+visualW*.5):(bounds.size.width-10-visualW*.5);
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
    BOOL night=FMMenuDark();
    UIColor *shadowTint=small?FMAccent():UIColor.blackColor;
    shadow.layer.shadowColor=shadowTint.CGColor;
    shadow.layer.shadowOpacity=small?(night?.52:.24):.18;
    shadow.layer.shadowRadius=small?18:22;
    shadow.layer.shadowOffset=CGSizeMake(0,3);
    CGFloat radius=small?(compact?31:29):32;
    UIView *glass=[self glass:shadow.bounds radius:radius strong:YES];
    [shadow addSubview:glass];
    // On iOS 26+ the UIKit glass material itself renders the edge and
    // depth. Do not obscure it with gradients, strokes or opaque washes.
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:CGRectInset(glass.bounds,14,14)];
    scroll.showsVerticalScrollIndicator=NO;
    scroll.alwaysBounceVertical=NO;
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    scroll.contentInset=UIEdgeInsetsMake(0,0,4,0);
    [FMGlassContent(glass) addSubview:scroll];
    if(small) {
        // Only the central application list scrolls; header and footer never move.
        if(!compact) [self buildAppHeader:glass];
        CGFloat top=compact?12:86, bottom=footerHeight+9;
        scroll.frame=CGRectMake(compact?3:13,top,pw-(compact?6:26),
                                MAX(22,ph-top-bottom));
        scroll.clipsToBounds=YES;
        [self buildAppFooter:glass];
    }
    UIStackView *stack=[self stack];
    stack.spacing=small?(compact?3:7):10;
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
    // Integrate the original edge bead as the drawer's outside pull handle.
    // Preserve its existing drag, tap and accessibility gestures.
    if(small && compact && self.orb) {
        // Use the *scaled* visual perimeter rather than the untransformed
        // shadow bounds to keep the pull-tab attached at every scale.
        CGFloat edgeX=self.left?(centerX-visualW*.5):
                                 (centerX+visualW*.5);
        CGFloat handleX=self.left?edgeX-3:edgeX+3;
        self.orb.center=CGPointMake(Clamp(handleX,6,bounds.size.width-6),
                                     centerY+visualH*.04);
    }
    shadow.alpha=1;
    // Native glass can silently fail to render if its owning view starts
    // at alpha=0. Animate scale only, leaving the effect continuously active.
    shadow.transform=CGAffineTransformMakeScale(actualScale*.965,actualScale*.96);
    NSTimeInterval duration=UIAccessibilityIsReduceMotionEnabled()?.10:.29;
    [UIView animateWithDuration:duration delay:0
        usingSpringWithDamping:.88 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
            shadow.transform=CGAffineTransformMakeScale(actualScale,actualScale);
        } completion:nil];
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
- (NSArray<NSString*> *)favorites {
    NSArray *v=[HostDefaults() arrayForKey:Pref(@"favoritePaths")];
    return [v isKindOfClass:NSArray.class]?v:@[];
}
- (void)appPage:(UIStackView *)stack {
    NSArray<NSDictionary*> *apps=[self visibleApps];
    if(BoolPref(@"compactMode",NO)) {
        for(NSDictionary *app in apps) {
            // 63pt full-width hit area; the visible icon is 50pt square.
            // Minimum 75% panel scale still yields a 47.25pt tap target.
            UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,88,63)];
            row.backgroundColor=FMHostUI()?
                [FMThemeColor(FMColorRow) colorWithAlphaComponent:
                    FMClearGlassEnabled()?.64:.74]:UIColor.clearColor;
            if(FMHostUI()) row.layer.cornerRadius=15;
            row.accessibilityLabel=FMAppCaption(app);
            row.accessibilityTraits=UIAccessibilityTraitButton;
            row.enabled=![LCOrbitGuestService isCurrentGuest:app];
            UIView *icon=[self iconViewForApp:app size:50];
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
                [icon.widthAnchor constraintEqualToConstant:50],
                [icon.heightAnchor constraintEqualToConstant:50]
            ]];
            objc_setAssociatedObject(row,@selector(switchFromRow:),
                                     app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [row addTarget:self action:@selector(switchFromRow:)
                forControlEvents:UIControlEventTouchUpInside];
            if([LCOrbitMultitask isRunningGuest:app]) {
                UIView *container=[[UIView alloc] initWithFrame:row.frame];
                row.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
                [container addSubview:row];
                UIButton *close=[UIButton buttonWithType:UIButtonTypeCustom];
                close.frame=CGRectMake(41,0,44,44);
                close.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
                close.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
                close.contentVerticalAlignment=UIControlContentVerticalAlignmentTop;
                UIImageSymbolConfiguration *symbol=[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
                [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:symbol] forState:UIControlStateNormal];
                close.tintColor=UIColor.systemRedColor;
                close.accessibilityLabel=[@"关闭 " stringByAppendingString:FMAppCaption(app)];
                objc_setAssociatedObject(close,@selector(closeTaskFromButton:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [close addTarget:self action:@selector(closeTaskFromButton:) forControlEvents:UIControlEventTouchUpInside];
                [container addSubview:close];
                [self addRow:container height:63 to:stack];
            } else [self addRow:row height:63 to:stack];
        }
    } else {
        for(NSDictionary *app in apps)
            [self addRow:[self appRow:app] height:60 to:stack];
    }
    if(!apps.count) {
        UILabel *empty=[self label:@"暂无应用" size:13 weight:UIFontWeightMedium];
        empty.textAlignment=NSTextAlignmentCenter;
        empty.textColor=FMClearGlassEnabled()?FMThemeColor(FMColorText):FMThemeColor(FMColorSecondary);
        [self addRow:empty height:68 to:stack];
    }
}
- (void)buildAppHeader:(UIView *)glass {
    CGFloat w=glass.bounds.size.width, inner=w-28;
    // The expanded panel is intentionally icon-and-app-only: no title,
    // description, item count, or duplicate explanatory text.
    NSArray *apps=[self visibleApps];
    NSMutableArray *pinned=[NSMutableArray array];
    for(NSString *path in [self favorites]) for(NSDictionary *item in apps)
        if(([path isEqualToString:FMAppKey(item)] || [path isEqualToString:item[@"path"]]) && pinned.count<4) { [pinned addObject:item]; break; }
    if(!pinned.count) for(NSDictionary *item in apps) {
        if(pinned.count==4) break;
        [pinned addObject:item];
    }
    CGFloat gap=6,cell=(inner-gap*3)/4;
    for(NSUInteger i=0;i<pinned.count;i++) {
        NSDictionary *app=pinned[i];
        BOOL compact=BoolPref(@"compactMode",NO);
        UIControl *tile=[[UIControl alloc] initWithFrame:
            CGRectMake(14+i*(cell+gap),compact?5:8,cell,compact?48:65)];
        tile.backgroundColor=UIColor.clearColor;
        // Favorites share the drawer material; no extra glass behind captions.
        CGFloat iconSize=compact?40:36;
        UIView *icon=[self iconViewForApp:app size:iconSize];
        icon.frame=CGRectMake((cell-iconSize)*.5,compact?4:4,iconSize,iconSize);
        icon.userInteractionEnabled=NO;
        [tile addSubview:icon];
        if(!compact) {
            UILabel *name=[self label:FMAppCaption(app) size:11 weight:UIFontWeightSemibold];
            name.frame=CGRectMake(1,44,cell-2,16);name.textAlignment=NSTextAlignmentCenter;
            name.lineBreakMode=NSLineBreakByTruncatingTail;
            if(FMClearGlassEnabled()) {
                // Shield short captions while preserving clear corners and gaps.
                name.backgroundColor=[FMThemeColor(FMColorRow) colorWithAlphaComponent:.50];
                name.layer.cornerRadius=6;
                name.clipsToBounds=YES;
            }
            [tile addSubview:name];
        }
        objc_setAssociatedObject(tile,@selector(switchFromRow:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [tile addTarget:self action:@selector(switchFromRow:) forControlEvents:UIControlEventTouchUpInside];
        tile.accessibilityLabel=FMAppCaption(app);
        tile.enabled=![LCOrbitGuestService isCurrentGuest:app];
        [FMGlassContent(glass) addSubview:tile];
    }
}
- (void)buildAppFooter:(UIView *)glass {
    BOOL compact=BoolPref(@"compactMode",NO);
    NSMutableArray<NSArray*> *items=[NSMutableArray array];
    if([LCOrbitMultitask isEnabled]) {
        [items addObject:@[@"house.fill",NSStringFromSelector(@selector(goHome)),@"返回 LC，保留运行任务"]];
        [items addObject:@[@"xmark.circle",NSStringFromSelector(@selector(closeMultitaskGuest)),@"关闭当前任务"]];
    }
    // The narrow drawer defaults to three actions, like the reference;
    // restarting can be explicitly opted in under Interaction & Switching.
    if(compact) {
        if(!FMHostUI())
            [items addObject:@[@"house.fill",NSStringFromSelector(@selector(goHome)),@"返回 LiveContainer"]];
        [items addObjectsFromArray:@[
            @[@"gearshape.fill",NSStringFromSelector(@selector(openSettings)),@"设置"],
            @[@"chevron.up",NSStringFromSelector(@selector(toggle)),@"收起菜单"]
        ]];
        if(!FMHostUI() && BoolPref(@"compactRestart",NO))
            [items insertObject:@[@"arrow.clockwise",NSStringFromSelector(@selector(restart)),@"重新启动"] atIndex:0];
    } else {
        if(!FMHostUI()) {
            if(BoolPref(@"showRestart",YES))
                [items addObject:@[@"arrow.clockwise",NSStringFromSelector(@selector(restart)),@"重新启动"]];
            [items addObject:@[@"house.fill",NSStringFromSelector(@selector(goHome)),@"返回 LiveContainer"]];
        }
        [items addObjectsFromArray:@[
            @[@"gearshape.fill",NSStringFromSelector(@selector(openSettings)),@"设置"],
            @[@"chevron.up",NSStringFromSelector(@selector(toggle)),@"收起菜单"]
        ]];
    }
    CGFloat w=glass.bounds.size.width;
    CGFloat height=compact?(16+items.count*63+12):74;
    UIView *footer=[[UIView alloc] initWithFrame:CGRectMake(compact?3:13,
                       glass.bounds.size.height-height-7,w-(compact?6:26),height)];
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
    CGFloat slot=compact?63:footer.bounds.size.width/items.count;
    for(NSUInteger i=0;i<items.count;i++) {
        NSArray *spec=items[i];
        CGRect hit=compact?
            CGRectMake(0,10+i*slot,footer.bounds.size.width,slot):
            CGRectMake(i*slot,3,slot,65);
        UIControl *button=[[UIControl alloc] initWithFrame:hit];
        button.backgroundColor=UIColor.clearColor;
        button.accessibilityLabel=spec[2];
        button.accessibilityTraits=UIAccessibilityTraitButton;
        button.accessibilityHint=@"轻触执行";
        CGFloat tileSize=compact?50:44;
        UIView *tile=[[UIView alloc] initWithFrame:
            CGRectMake((hit.size.width-tileSize)*.5,(hit.size.height-tileSize)*.5,
                       tileSize,tileSize)];
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
           configurationWithPointSize:compact?23:20 weight:UIImageSymbolWeightSemibold];
        UIImageView *glyph=[[UIImageView alloc] initWithImage:
                                     [UIImage systemImageNamed:spec[0] withConfiguration:conf]];
        glyph.frame=CGRectInset(tile.bounds,12,12);
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
        [self section:@"悬浮控件" sub:nil in:s];
        [self settingSwitch:s title:@"静止自动淡化" key:@"autoFade" defaultValue:YES tag:6];
        [self settingSwitch:s title:@"触觉反馈" key:@"haptic" defaultValue:YES tag:1];
        [self spacer:s size:14];
        [self section:@"应用切换" sub:nil in:s];
        [self settingSwitch:s title:@"切换前二次确认" key:@"confirm" defaultValue:YES tag:2];
        [self settingSwitch:s title:@"显示重启按钮" key:@"showRestart" defaultValue:YES tag:3];
        [self settingSwitch:s title:@"精简抽屉显示重启按钮" key:@"compactRestart" defaultValue:NO tag:17];
    } else if([category isEqualToString:@"apps"]) {
        [self perAppPage:s];
        [self spacer:s size:20];
        [self managePage:s];
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
    sw.onTintColor=FMAccent();
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
        [NSString stringWithFormat:@"%.0f%%",100*Clamp(FloatPref(@"panelScale",1.0),.75,1.20)]
        size:13 weight:UIFontWeightSemibold];
    percent.textColor=FMThemeColor(FMColorSecondary);
    percent.textAlignment=NSTextAlignmentRight;
    [heading addArrangedSubview:name];
    [heading addArrangedSubview:percent];
    [percent.widthAnchor constraintEqualToConstant:65].active=YES;
    [self addRow:heading height:29 to:stack];
    UISlider *slider=[UISlider new];
    slider.minimumValue=.75;slider.maximumValue=1.20;
    slider.value=Clamp(FloatPref(@"panelScale",1.0),.75,1.20);
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
    [self settingSwitch:s title:@"静止自动淡化" key:@"autoFade" defaultValue:YES tag:6];
    [self settingSwitch:s title:@"触觉反馈" key:@"haptic" defaultValue:YES tag:1];
    [self settingSwitch:s title:@"切换前二次确认" key:@"confirm" defaultValue:YES tag:2];
    [self spacer:s size:10];
    [self diyPage:s];
    [self spacer:s size:10];
    [self perAppPage:s];
    [self spacer:s size:10];
    [self managePage:s];
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
    [self settingSwitch:s title:@"圆形微珠" key:@"roundOrb" defaultValue:NO tag:5];
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
    [self draw];
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
    UIView *surface=self.settingsNavigation.topViewController.view ?: self.panel;
    if(!surface) return;
    UIView *handle=gesture.view;
    UIView *sourceRow=handle.superview;
    NSDictionary *app=objc_getAssociatedObject(handle,@selector(sortDrag:));
    if(!app) return;
    CGPoint finger=[gesture locationInView:surface];
    static const CGFloat kMaxMotion=260;
    if(gesture.state==UIGestureRecognizerStateBegan) {
        objc_setAssociatedObject(gesture,@selector(sortDrag:),@(finger.y),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(BoolPref(@"haptic",YES))
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
        sourceRow.layer.zPosition=10;
        sourceRow.alpha=.82;
    } else if(gesture.state==UIGestureRecognizerStateChanged) {
        CGFloat initial=[objc_getAssociatedObject(gesture,@selector(sortDrag:)) doubleValue];
        sourceRow.transform=CGAffineTransformMakeTranslation(0,Clamp(finger.y-initial,-kMaxMotion,kMaxMotion));
    } else if(gesture.state==UIGestureRecognizerStateEnded) {
        NSArray *items=[self visibleApps];
        NSUInteger from=[items indexOfObject:app];
        if(from!=NSNotFound && from<items.count) {
            // Use other rows' original centers as insertion boundaries.
            // Including the transformed source row made drop targets unstable.
            NSUInteger insertion=0;
            for(NSUInteger i=0;i<self.manageRows.count;i++) {
                if(i==from) continue;
                UIView *row=self.manageRows[i];
                CGRect rect=[row convertRect:row.bounds toView:surface];
                if(finger.y>CGRectGetMidY(rect)) insertion=i+1;
            }
            NSUInteger to=insertion>from?insertion-1:insertion;
            to=MIN(to,items.count-1);
            if(to!=from) {
                NSMutableArray *order=[NSMutableArray arrayWithCapacity:items.count];
                for(NSDictionary *item in items) [order addObject:FMAppKey(item)];
                NSString *moving=order[from];
                [order removeObjectAtIndex:from];
                [order insertObject:moving atIndex:to];
                SetPref(@"menuOrder",order);
                FMLog(@"menu-reordered",@"drag");
            }
        }
        sourceRow.transform=CGAffineTransformIdentity;
        sourceRow.layer.zPosition=0;
        sourceRow.alpha=1;
        [self refreshUI];
    } else if(gesture.state==UIGestureRecognizerStateCancelled ||
              gesture.state==UIGestureRecognizerStateFailed) {
        sourceRow.transform=CGAffineTransformIdentity;
        sourceRow.layer.zPosition=0;
        sourceRow.alpha=1;
    }
}
- (void)managePage:(UIStackView*)stack {
    [self section:@"收藏与排序" sub:nil in:stack];
    NSArray<NSDictionary*> *apps=[self visibleApps];
    self.manageRows=[NSMutableArray arrayWithCapacity:apps.count];
    UIStackView *group=[UIStackView new];
    group.axis=UILayoutConstraintAxisVertical;
    group.alignment=UIStackViewAlignmentFill;
    group.distribution=UIStackViewDistributionFill;
    group.spacing=0;
    group.backgroundColor=FMThemeColor(FMColorSurface);
    group.layer.cornerRadius=18;
    group.clipsToBounds=YES;
    [stack addArrangedSubview:group];
    for(NSUInteger i=0;i<apps.count;i++) {
        NSDictionary *app=apps[i];
        UIView *row=[[UIView alloc] init];
        row.backgroundColor=UIColor.clearColor;
        [row.heightAnchor constraintEqualToConstant:65].active=YES;
        [group addArrangedSubview:row];
        UIView *icon=[self iconViewForApp:app size:43];
        icon.translatesAutoresizingMaskIntoConstraints=NO;
        icon.userInteractionEnabled=NO;
        [row addSubview:icon];
        UILabel *name=[self label:app[@"title"] size:15 weight:UIFontWeightMedium];
        name.translatesAutoresizingMaskIntoConstraints=NO;
        name.numberOfLines=1;
        name.lineBreakMode=NSLineBreakByTruncatingTail;
        [row addSubview:name];
        UIButton *pin=[UIButton buttonWithType:UIButtonTypeSystem];
        pin.translatesAutoresizingMaskIntoConstraints=NO;
        BOOL favored=[[self favorites] containsObject:FMAppKey(app)] || [[self favorites] containsObject:app[@"path"]];
        UIImageSymbolConfiguration *starConfig=[UIImageSymbolConfiguration
            configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
        [pin setImage:[UIImage systemImageNamed:favored?@"star.fill":@"star"
                              withConfiguration:starConfig] forState:UIControlStateNormal];
        pin.tintColor=favored?(FMMenuDark()?RGBA(1,.77,.30,1):RGBA(.55,.35,.03,1)):
                            FMThemeColor(FMColorSecondary);
        pin.accessibilityLabel=favored?@"取消收藏":@"添加到收藏";
        objc_setAssociatedObject(pin,@selector(pinApp:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [pin addTarget:self action:@selector(pinApp:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:pin];
        UIView *handle=[UIView new];
        handle.translatesAutoresizingMaskIntoConstraints=NO;
        handle.isAccessibilityElement=YES;
        handle.accessibilityLabel=[NSString stringWithFormat:@"拖动排序 %@",app[@"title"]];
        handle.accessibilityTraits=UIAccessibilityTraitButton;
        UIImageView *lines=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
        lines.translatesAutoresizingMaskIntoConstraints=NO;
        lines.contentMode=UIViewContentModeScaleAspectFit;
        lines.tintColor=FMThemeColor(FMColorSecondary);
        [handle addSubview:lines];
        UILongPressGestureRecognizer *drag=[[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(sortDrag:)];
        drag.minimumPressDuration=.30;
        [handle addGestureRecognizer:drag];
        objc_setAssociatedObject(handle,@selector(sortDrag:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [row addSubview:handle];
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
            [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:43],
            [icon.heightAnchor constraintEqualToConstant:43],
            [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:11],
            [name.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:pin.leadingAnchor constant:-6],
            [pin.widthAnchor constraintEqualToConstant:46],
            [pin.heightAnchor constraintEqualToConstant:50],
            [pin.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [pin.trailingAnchor constraintEqualToAnchor:handle.leadingAnchor],
            [handle.widthAnchor constraintEqualToConstant:48],
            [handle.heightAnchor constraintEqualToConstant:60],
            [handle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [handle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-5],
            [lines.widthAnchor constraintEqualToConstant:19],
            [lines.heightAnchor constraintEqualToConstant:17],
            [lines.centerXAnchor constraintEqualToAnchor:handle.centerXAnchor],
            [lines.centerYAnchor constraintEqualToAnchor:handle.centerYAnchor]
        ]];
        if(i+1<apps.count) {
            UIView *divider=[UIView new];
            divider.translatesAutoresizingMaskIntoConstraints=NO;
            divider.backgroundColor=FMThemeColor(FMColorBorder);
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
}
- (void)perAppPage:(UIStackView*)s {
    [self section:FMHostUI()?@"LC 主界面独立设置":@"当前 App 独立设置" sub:GuestID() in:s];
    [self settingSwitch:s title:@"启用独立设置" key:[@"override." stringByAppendingString:GuestID()] defaultValue:NO tag:7];
    [self spacer:s size:4];
    [self section:@"外观与位置" sub:nil in:s];
    [self settingSlider:s title:@"当前 App 微珠透明度" key:[@"appAlpha." stringByAppendingString:GuestID()] min:.20 max:1 def:FloatPref(@"idleAlpha",.72) tag:12];
    [self settingSwitch:s title:@"双击展开（游戏防误触）" key:[@"doubleTap." stringByAppendingString:GuestID()] defaultValue:NO tag:8];
    [self settingSwitch:s title:@"极细边缘提示（保留触摸区）" key:[@"stealth." stringByAppendingString:GuestID()] defaultValue:NO tag:15];
    [self spacer:s size:4];
    [self section:@"单任务切换行为" sub:nil in:s];
    [self settingSwitch:s title:@"当前 App 切换前确认" key:AppPref() defaultValue:BoolPref(@"confirm",YES) tag:4];

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
        case 5:key=@"roundOrb";break;
        case 6:key=@"autoFade";break;
        case 7:key=[@"override." stringByAppendingString:GuestID()];break;
        case 8:key=[@"doubleTap." stringByAppendingString:GuestID()];break;
        case 15:key=[@"stealth." stringByAppendingString:GuestID()];break;
        case 16:key=@"compactMode";break;
        case 17:key=@"compactRestart";break;
        case 18:key=@"clearGlass";break;
        case 4:key=AppPref();break;
        default:return;
    }
    SetPref(key,@(sw.isOn));
    if(sw.tag==3||sw.tag==5||sw.tag==6||sw.tag==7||sw.tag==8||sw.tag==15||sw.tag==18) [self draw];
    if(sw.tag==17) FMLog(@"compact-toolbar",sw.on?@"four-actions":@"three-actions");
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
    row.layer.cornerRadius=13;
    UIControl *button=[[UIControl alloc] initWithFrame:CGRectMake(0,0,280,54)];
    button.translatesAutoresizingMaskIntoConstraints=NO;
    [row addSubview:button];
    UIImageView *symbol=[[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"arrow.counterclockwise"]];
    symbol.translatesAutoresizingMaskIntoConstraints=NO;
    symbol.tintColor=FMAccent();
    [button addSubview:symbol];
    UILabel *label=[self label:@"恢复默认设置" size:14 weight:UIFontWeightMedium];
    label.translatesAutoresizingMaskIntoConstraints=NO;
    [button addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [button.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [button.topAnchor constraintEqualToAnchor:row.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [symbol.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:15],
        [symbol.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [symbol.widthAnchor constraintEqualToConstant:20],
        [symbol.heightAnchor constraintEqualToConstant:20],
        [label.leadingAnchor constraintEqualToAnchor:symbol.trailingAnchor constant:12],
        [label.centerYAnchor constraintEqualToAnchor:button.centerYAnchor]
    ]];
    button.accessibilityLabel=@"恢复默认设置";
    [button addTarget:self action:@selector(resetStyle) forControlEvents:UIControlEventTouchUpInside];
    [self addRow:row height:54 to:stack];
}
- (void)resetStyle {
    SetPref(@"idleAlpha",@(.72));SetPref(@"orbScale",@(1.0));
    SetPref(@"showRestart",@YES);SetPref(@"haptic",@YES);
    SetPref(@"roundOrb",@NO);SetPref(@"glassTint",@(0));SetPref(@"clearGlass",@NO);
    SetPref(@"appearanceMode",@(0));
    SetPref(@"autoFade",@YES);
    for(NSString *key in @[@"accentLight",@"accentDark",@"theme",@"preferDarkIcons",@"orbWidth"]) {
        [HostDefaults() removeObjectForKey:Pref(key)];
    }
    SetPref(@"compactMode",@NO);SetPref(@"panelScale",@(1.0));
    SetPref(@"compactRestart",@NO);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIUserInterfaceStyle skin=FMMenuOverride();
        self.overlayView.overrideUserInterfaceStyle=skin;
        if(self.settingsWindow) self.settingsWindow.overrideUserInterfaceStyle=skin;
        [self refreshUI];
    });
}
- (void)launchApp:(NSDictionary *)app {
    // Persist before launch: classic switching may destroy this Guest process.
    [self persistAppsScroll];
    FMLog(@"switch-request",FMAppKey(app));
    [self.orbitContext.events publish:@"orbit.guest.switchRequested"
        payload:@{@"target":FMAppKey(app),@"guestID":GuestID()}];
    FMSyncSharedTweaks(^{
        NSError *error=nil;
        if(![LCOrbitGuestService launchGuest:app error:&error]) {
            FMLog(@"switch-rejected",error.localizedDescription);
            [self showMessage:@"暂不可切换" details:error.localizedDescription];
            return;
        }
        FMLog(@"switch-accepted",[LCOrbitMultitask isEnabled]?@"host-multitask":@"classic");
        self.isOpen=NO;[self draw];
    });
}
- (void)showMultitaskMenuExpanded:(BOOL)expanded {
    if(![LCOrbitMultitask isEnabled]) return;
    [self installIfPossible];
    if(!self.window || self.settingsWindow) return;
    if([LCOrbitMultitask usesSystemMenu]) { [self draw];return; }
    self.apps=InstalledApps();self.page=@"apps";
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
- (void)goHome {
    if([LCOrbitMultitask isEnabled]) {
        [LCOrbitMultitask showHome];self.isOpen=NO;[self draw];return;
    }
    if(FMHostUI()) { [self toggle]; return; }
    [self confirmTitle:@"返回 LiveContainer？" action:^{[self launchPath:@"ui" uuid:nil];}];
}
- (void)closeTaskFromButton:(UIControl *)sender {
    // The task may disappear synchronously; save the scroll before notifying
    // its window manager, irrespective of compact/normal button layout.
    [self persistAppsScroll];
    NSDictionary *app=objc_getAssociatedObject(sender,@selector(closeTaskFromButton:));
    if(!app || ![LCOrbitMultitask isRunningGuest:app]) {
        FMLog(@"task-close-rejected",@"not-running-or-stale");
        [self showMessage:@"任务未运行" details:@"应用已退出或运行状态已变化，没有关闭其他任务。"];
        return;
    }
    NSError *error=nil;
    if(![LCOrbitMultitask closeGuest:app error:&error]) {
        FMLog(@"task-close-rejected",error.localizedDescription?:@"unknown");
        [self showMessage:@"关闭任务失败" details:error.localizedDescription?:@"请稍后重试。"];
        return;
    }
    sender.enabled=NO;
    FMLog(@"task-close-requested",FMAppKey(app));
}
- (void)closeMultitaskGuest {
    if(![LCOrbitMultitask activeWindow]) {
        [self showMessage:@"没有当前任务" details:@"先从微珠打开或切回一个 App。"];return;
    }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"关闭当前任务？"
        message:@"这会结束当前 App 的运行状态，其他任务继续保留。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭任务" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [LCOrbitMultitask closeCurrentGuest];self.isOpen=NO;[self draw];
    }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
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
                     symbol:(NSString *)symbol action:(SEL)action {
    UIControl *row=[UIControl new];
    row.layer.cornerRadius=16;
    row.backgroundColor=FMThemeColor(FMColorSurface);
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.translatesAutoresizingMaskIntoConstraints=NO;
    icon.tintColor=FMAccent();
    icon.contentMode=UIViewContentModeScaleAspectFit;
    [row addSubview:icon];
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
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:25],
        [icon.heightAnchor constraintEqualToConstant:25],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
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
- (void)openReleases {
    NSURL *url=[NSURL URLWithString:FMReleasesURL];
    if(url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
- (void)presentUpdateResult:(NSString *)title message:(NSString *)message showReleases:(BOOL)showReleases {
    if(!self.view.window) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    if(showReleases) [alert addAction:[UIAlertAction actionWithTitle:@"查看 Releases"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self openReleases];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)checkForUpdates {
    if(self.checkingUpdate) return;
    self.checkingUpdate=YES;
    self.updateStatusLabel.text=@"正在查询 GitHub…";
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:FMUpdateAPI]];
    request.timeoutInterval=12;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"LCFloatingMenu/1.0" forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf=self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf=weakSelf;
            if(!strongSelf) return;
            strongSelf.checkingUpdate=NO;
            strongSelf.updateStatusLabel.text=@"检查最新正式 Release";
            if(error) {
                [strongSelf presentUpdateResult:@"检查更新失败"
                    message:error.localizedDescription?:@"无法连接 GitHub，请检查网络。"
                    showReleases:YES];
                return;
            }
            NSInteger status=[(NSHTTPURLResponse *)response statusCode];
            if(status==401 || status==404) {
                // This repository is private. Never claim "up to date" when
                // the anonymous API cannot reveal its latest commit.
                [strongSelf presentUpdateResult:@"无法自动检查私有仓库"
                    message:@"GitHub 不允许匿名读取该私有仓库的 Release。请使用已登录 GitHub 的浏览器查看 Releases；插件不会保存或索取访问令牌。"
                    showReleases:YES];
                return;
            }
            if(status!=200) {
                [strongSelf presentUpdateResult:@"检查更新失败"
                    message:[NSString stringWithFormat:@"GitHub 返回 HTTP %ld。请稍后重试或前往 Releases 查看。",(long)status]
                    showReleases:YES];
                return;
            }
            NSDictionary *json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            NSString *tag=[json isKindOfClass:NSDictionary.class]?json[@"tag_name"]:nil;
            if(![tag isKindOfClass:NSString.class] || ![tag hasPrefix:@"v"]) {
                [strongSelf presentUpdateResult:@"版本信息无效"
                    message:@"无法读取最新正式 Release 的版本标签。" showReleases:YES];
                return;
            }
            NSString *latest=[tag substringFromIndex:1];
            NSString *installed=FM_MENU_VERSION;
            NSComparisonResult comparison=[installed compare:latest options:NSNumericSearch];
            if(comparison==NSOrderedAscending) {
                [strongSelf presentUpdateResult:@"发现新版本"
                    message:[NSString stringWithFormat:@"当前 v%@，最新正式版 %@。请前往 Releases 下载并在 LC 中替换、重签动态库。",installed,tag]
                    showReleases:YES];
            } else if(comparison==NSOrderedSame) {
                [strongSelf presentUpdateResult:@"已是最新正式版"
                    message:[NSString stringWithFormat:@"当前版本 v%@，与最新正式 Release %@ 一致。",installed,tag]
                    showReleases:NO];
            } else {
                [strongSelf presentUpdateResult:@"当前版本高于正式版"
                    message:[NSString stringWithFormat:@"已安装 v%@，最新正式 Release 为 %@。",installed,tag]
                    showReleases:YES];
            }
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
    UIControl *apps=[self navigationRow:@"应用管理" subtitle:@"每 App 设置、收藏与排序"
                               symbol:@"square.stack.3d.up" action:@selector(openApps)];
    [apps.heightAnchor constraintEqualToConstant:65].active=YES;
    [stack addArrangedSubview:apps];
    if(FMHostUI()) {
        UIControl *shared=[self navigationRow:@"插件管理中心" subtitle:@"按 App 分配、启停、备份和批量共享"
                                   symbol:@"square.stack.3d.up.fill" action:@selector(openSharedTweaks)];
        [shared.heightAnchor constraintEqualToConstant:65].active=YES;
        [stack addArrangedSubview:shared];
    }
    UIControl *logs=[self navigationRow:@"诊断与日志" subtitle:@"查看、导出和清除日志"
                               symbol:@"waveform.path.ecg" action:@selector(openDiagnostics)];
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
        symbol:@"number.circle" action:NULL];
    [versionRow.heightAnchor constraintEqualToConstant:65].active=YES;
    [stack addArrangedSubview:versionRow];
    UIControl *checkRow=[self navigationRow:@"检测更新"
        subtitle:self.checkingUpdate?@"正在查询 GitHub…":@"检查最新正式 Release"
        symbol:@"arrow.clockwise.circle" action:@selector(checkForUpdates)];
    [checkRow.heightAnchor constraintEqualToConstant:65].active=YES;
    [stack addArrangedSubview:checkRow];
    UIControl *repository=[self navigationRow:@"GitHub 仓库"
        subtitle:@"github.com/dompling/LC-SS-widget-export"
        symbol:@"link" action:@selector(openRepository)];
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
}
- (void)orbitDidReceiveLifecycleEvent:(NSString *)event scene:(UIWindowScene *)scene {
    FMManager *manager=[FMManager shared];
    if([event isEqualToString:UIApplicationDidEnterBackgroundNotification] ||
       [event isEqualToString:UIApplicationWillResignActiveNotification] ||
       [event isEqualToString:UISceneWillDeactivateNotification]) {
        if(!scene || scene==manager.window.windowScene) {
            if(manager.appsScroll) [manager persistAppsScroll];
            [manager cancelAppearanceCheck];
        }
        return;
    }
    if([event isEqualToString:UISceneDidDisconnectNotification]) {
        if(scene && scene==manager.window.windowScene) [manager detachFromScene];
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
    [core registerModule:[LCFloatingMenuModule new]];
    [LCOrbitHostSettings installWithOpenSettings:^(UIWindowScene *scene) { [[FMManager shared] openSettingsInScene:scene]; }];
}
