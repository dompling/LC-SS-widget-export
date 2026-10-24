// LCFloatingMenu 1.0 | LC+SS classic single-task overlay
// This tweak does not hook SpringBoard or start a second guest process.
// UI is rendered by UIKit in the current LC guest process.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>

static NSString *const kPrefix = @"LCFloatingMenu.";
static inline CGFloat Clamp(CGFloat x, CGFloat a, CGFloat b) { return fmax(a,fmin(b,x)); }
static UIColor *RGBA(CGFloat r,CGFloat g,CGFloat b,CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
static id LCClassCall(Class c, NSString *name) {
    SEL s=NSSelectorFromString(name);
    if(!c || ![c respondsToSelector:s]) return nil;
    return ((id (*)(id,SEL))objc_msgSend)(c,s);
}
static NSUserDefaults *HostDefaults(void) {
    return LCClassCall(NSUserDefaults.class,@"lcUserDefaults") ?: NSUserDefaults.standardUserDefaults;
}
static NSString *GroupPath(void) { return LCClassCall(NSUserDefaults.class,@"lcAppGroupPath"); }
static NSDictionary *GuestInfo(void) { return LCClassCall(NSUserDefaults.class,@"guestAppInfo"); }
static NSString *GuestID(void) {
    return LCClassCall(NSUserDefaults.class,@"lcGuestAppId") ?: NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
}
static NSString *Pref(NSString *key) {return [kPrefix stringByAppendingString:key];}
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
}
static NSString *AppPref(void) {return [NSString stringWithFormat:@"appEnabled.%@", GuestID()];}

// Local diagnostics: bounded rotation, no app content, certificates or secrets.
static NSString *FMLogFile(void) {
    NSString *root=GroupPath();
    if(root.length) root=[root stringByAppendingPathComponent:@"LiveContainer/LCFloatingMenu"];
    else {
        const char *home=getenv("LC_HOME_PATH");
        if(!home || !home[0]) return nil;
        root=[[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"Documents/LCFloatingMenu"];
    }
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    return [root stringByAppendingPathComponent:@"diagnostics.log"];
}
static void FMLog(NSString *event, NSString *detail) {
    @try {
        @synchronized(NSFileManager.class) {
            NSString *file=FMLogFile();
            if(!file) return;
            NSUInteger size=[[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil] fileSize];
            if(size>262144) {
                NSString *old=[file stringByAppendingString:@".old"];
                [NSFileManager.defaultManager removeItemAtPath:old error:nil];
                [NSFileManager.defaultManager moveItemAtPath:file toPath:old error:nil];
            }
            NSString *line=[NSString stringWithFormat:@"%@ guest=%@ event=%@ detail=%@\n",
                NSDate.date,GuestID(),event?:@"unknown",detail?:@""];
            NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
            if(![NSFileManager.defaultManager fileExistsAtPath:file])
                [NSFileManager.defaultManager createFileAtPath:file contents:nil attributes:nil];
            NSFileHandle *out=[NSFileHandle fileHandleForWritingAtPath:file];
            [out seekToEndOfFile];[out writeData:data];[out closeFile];
        }
    } @catch(NSException *ex) {
        NSLog(@"[LCFloatingMenu] diagnostics unavailable: %@",ex.name);
    }
}

static NSArray<NSDictionary*> *InstalledApps(void) {
    NSMutableArray<NSDictionary*> *list=[NSMutableArray array];
    NSMutableSet<NSString*> *seen=[NSMutableSet set];
    const char *hostHome=getenv("LC_HOME_PATH");
    if(!hostHome || !hostHome[0]) return @[];
    NSString *home=[NSString stringWithUTF8String:hostHome];
    NSMutableArray<NSString*> *roots=[NSMutableArray arrayWithObject:
        [home stringByAppendingPathComponent:@"Documents/Applications"]];
    NSString *shared=GroupPath();
    if(shared.length) [roots addObject:[shared stringByAppendingPathComponent:@"LiveContainer/Applications"]];
    NSFileManager *fm=NSFileManager.defaultManager;
    for(NSString *root in roots) {
        for(NSString *entry in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
            if(![entry hasSuffix:@".app"] || [seen containsObject:entry]) continue;
            NSString *folder=[root stringByAppendingPathComponent:entry];
            NSDictionary *lc=[NSDictionary dictionaryWithContentsOfFile:
                [folder stringByAppendingPathComponent:@"LCAppInfo.plist"]];
            NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:
                [folder stringByAppendingPathComponent:@"Info.plist"]];
            if(!lc || !info) continue;
            [seen addObject:entry];
            if([lc[@"isHidden"] boolValue] || [lc[@"isLocked"] boolValue] ||
               [lc[@"isJITNeeded"] boolValue] || [lc[@"is32bit"] boolValue]) continue;
            // LC can require an app re-sign, authentication, or JIT acquisition.
            // For v1, launch only already-patched ordinary guests.
            if([lc[@"LCPatchRevision"] integerValue] < 7) continue;
    if([lc[@"dontSign"] boolValue] || [lc[@"LCTweakLoaderCantInject"] boolValue]) continue;
    if([lc[@"dontLoadTweakLoader"] boolValue] || [lc[@"dontInjectTweakLoader"] boolValue]) continue;
    NSString *exec=info[@"CFBundleExecutable"];
    if(![exec isKindOfClass:NSString.class] || !exec.length ||
       ![fm fileExistsAtPath:[folder stringByAppendingPathComponent:exec]]) continue;
            NSString *title=info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: entry.stringByDeletingPathExtension;
            NSString *uuid=lc[@"LCDataUUID"];
            if(!uuid.length) continue;
            [list addObject:@{@"path":entry,@"title":title,@"uuid":uuid,
                              @"bundle":info[@"CFBundleIdentifier"] ?: @"",
                              @"folder":folder}];
        }
    }
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        return [a[@"title"] localizedStandardCompare:b[@"title"]];
    }];
    return list;
}
static UIColor *TintFor(NSString *s) {
    static NSArray<UIColor*> *colors;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        colors=@[RGBA(.25,.51,1,1),RGBA(.55,.36,1,1),RGBA(.98,.39,.54,1),
                 RGBA(.17,.72,.64,1),RGBA(1,.58,.20,1)];
    });
    return colors[(NSUInteger)(s.hash & 0x7fffffff)%colors.count];
}

static UIColor *FMAccent(void) {
    switch ([HostDefaults() integerForKey:Pref(@"theme")]) {
        case 1: return RGBA(.80,.84,.91,1); // minimalist
        case 2: return RGBA(.36,.52,1,1); // deep sapphire
        case 3: return RGBA(.58,.36,.95,1); // aurora
        default: return RGBA(.34,.69,1,1); // native glass
    }
}
static UIImage *FMGuestIcon(NSDictionary *app) {
    NSString *folder=app[@"folder"];
    if(![folder isKindOfClass:NSString.class] || !folder.length) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once,^{ cache=[NSCache new];cache.countLimit=90; });
    id saved=[cache objectForKey:folder];
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
    NSString *cached=[folder stringByAppendingPathComponent:
        BoolPref(@"preferDarkIcons",NO)?@"LCAppIconDark.png":@"LCAppIconLight.png"];
    UIImage *result=[UIImage imageWithContentsOfFile:cached];
    if(!result) result=[UIImage imageWithContentsOfFile:
        [folder stringByAppendingPathComponent:@"LCAppIconLight.png"]];
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
    [cache setObject:result?:NSNull.null forKey:folder];
    return result;
}

@interface FMHitButton : UIButton @end
@implementation FMHitButton
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds,-14,-10),p);
}
@end
@interface FMGlassWindow : UIWindow @end
@implementation FMGlassWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:p withEvent:event];
    if(hit==self || hit==self.rootViewController.view) return nil;
    return hit;
}
@end

@interface FMManager : NSObject
@property(nonatomic,strong) FMGlassWindow *window;
@property(nonatomic,strong) UIButton *orb;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIView *dismissLayer;
@property(nonatomic,assign) CGFloat orbY;
@property(nonatomic,assign) BOOL left;
@property(nonatomic,assign) BOOL isOpen;
@property(nonatomic,copy) NSString *page;
@property(nonatomic,strong) NSArray<NSDictionary*> *apps;
+ (instancetype)shared;
- (void)installIfPossible;
- (void)draw;
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
    if(!scene || !GuestInfo()) return;
    SEL sideSel=NSSelectorFromString(@"isSideStore");
    SEL procSel=NSSelectorFromString(@"isLiveProcess");
    if(![NSUserDefaults respondsToSelector:sideSel] || ![NSUserDefaults respondsToSelector:procSel]) return;
    if(((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,sideSel) ||
       ((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,procSel)) return;
    if(self.window && self.window.windowScene != scene) {
        self.window.hidden=YES; self.window=nil; self.orb=nil; self.panel=nil;
    }
    if(self.window) {
        CGRect nextFrame=scene.coordinateSpace.bounds;
        if(!CGRectEqualToRect(self.window.frame,nextFrame)) {
            self.window.frame=nextFrame;
            [self draw];
        }
        return;
    }
    self.window=[[FMGlassWindow alloc] initWithWindowScene:scene];
    self.window.frame=self.window.windowScene.coordinateSpace.bounds;
    self.window.backgroundColor=UIColor.clearColor;
    self.window.windowLevel=UIWindowLevelNormal+75;
    UIViewController *vc=[UIViewController new];
    vc.view.backgroundColor=UIColor.clearColor;
    vc.view.userInteractionEnabled=YES;
    self.window.rootViewController=vc;
    self.window.hidden=NO; // Do not replace the guest's key window.
    self.orbY=Clamp(FloatPref(@"orbY",.50),.10,.90);
    self.left=BoolPref(@"onLeft",NO);
    self.page=@"apps";
    self.apps=InstalledApps();
    FMLog(@"overlay-ready",[NSString stringWithFormat:@"available=%lu",(unsigned long)self.apps.count]);
    [self draw];
}
- (CGFloat)orbWidth { return Clamp(FloatPref(@"orbWidth",12),9,28); }
- (CGFloat)orbHeight { return BoolPref(@"roundOrb",NO)?self.orbWidth:Clamp(FloatPref(@"orbHeight",38),26,48); }
- (CGRect)orbFrame {
    CGRect b=self.window.bounds;
    CGFloat w=self.orbWidth,h=self.orbHeight;
    CGFloat x=self.left?-w*.16:b.size.width-w*.84;
    CGFloat top=MAX(25,self.window.safeAreaInsets.top+6);
    CGFloat bottom=MAX(24,self.window.safeAreaInsets.bottom+8);
    return CGRectMake(x,Clamp(b.size.height*self.orbY-h*.5,top,b.size.height-h-bottom),w,h);
}
- (UIView *)glass:(CGRect)frame radius:(CGFloat)radius strong:(BOOL)strong {
    UIView *v=[[UIView alloc] initWithFrame:frame];
    v.layer.cornerRadius=radius;v.clipsToBounds=YES;
    UIVisualEffect *effect=nil;
    // Public UIKit glass API exists from iOS 26; resolve at runtime so the
    // same signed tweak safely runs on older iOS with regular blur.
    if(@available(iOS 26.0,*)) {
        Class cls=NSClassFromString(@"UIGlassEffect");
        if(cls && [cls isSubclassOfClass:UIVisualEffect.class]) {
            effect=[[cls alloc] init];
        }
    }
    if(!effect) {
        effect=[UIBlurEffect effectWithStyle:strong?UIBlurEffectStyleSystemThinMaterial:UIBlurEffectStyleSystemUltraThinMaterial];
    }
    UIVisualEffectView *blur=[[UIVisualEffectView alloc] initWithEffect:effect];
    blur.frame=v.bounds;
    blur.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [v addSubview:blur];
    CGFloat alpha=Clamp(FloatPref(@"glassTint",strong?.08:.04),0,.30);
    UIView *wash=[[UIView alloc] initWithFrame:v.bounds];
    UIColor *t=FMAccent();
    wash.backgroundColor=[t colorWithAlphaComponent:alpha];
    wash.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [v addSubview:wash];
    v.layer.borderWidth=.65;
    v.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:.48].CGColor;
    return v;
}
- (UIButton *)symbolButton:(NSString *)symbol title:(NSString *)title {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *image=[UIImage systemImageNamed:symbol];
    [b setImage:image forState:UIControlStateNormal];
    [b setTitle:title forState:UIControlStateNormal];
    b.tintColor=UIColor.labelColor;
    b.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    b.semanticContentAttribute=UISemanticContentAttributeForceLeftToRight;
    b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    b.imageEdgeInsets=UIEdgeInsetsMake(0,12,0,12);
    b.layer.cornerRadius=16;
    b.backgroundColor=RGBA(1,1,1,.24);
    return b;
}
- (void)removePanel {
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
    UIView *line=[[UIView alloc] initWithFrame:CGRectMake(0,0,2.5,14)];
    line.center=CGPointMake(f.size.width*.5,f.size.height*.5);
    line.backgroundColor=[UIColor.whiteColor colorWithAlphaComponent:.85];
    line.layer.cornerRadius=1.25;line.userInteractionEnabled=NO;
    [button addSubview:line];
    CGFloat alpha=FloatPref([@"appAlpha." stringByAppendingString:GuestID()],
                            FloatPref(@"idleAlpha",.72));
    button.alpha=self.isOpen?1:Clamp(alpha,.16,1);
    button.accessibilityLabel=@"LC 悬浮菜单";
    button.accessibilityHint=@"轻触展开，拖动移动，长按显示快捷操作";
    button.accessibilityTraits=UIAccessibilityTraitButton;
    if(BoolPref([@"doubleTap." stringByAppendingString:GuestID()],NO)) {
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        tap.numberOfTapsRequired=2;[button addGestureRecognizer:tap];
    } else [button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
    hold.minimumPressDuration=.55;
    [button addGestureRecognizer:hold];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [button addGestureRecognizer:pan];
    [self.window.rootViewController.view addSubview:button];
    self.orb=button;
    if(!self.isOpen && BoolPref(@"autoFade",YES)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{
            if(self.orb==button && !self.isOpen && !UIAccessibilityIsReduceMotionEnabled()) {
                [UIView animateWithDuration:.42 animations:^{
                    bead.transform=CGAffineTransformMakeScale(.32,.88);
                    line.alpha=.4;
                }];
            }
        });
    }
}
- (void)hold:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan) return;
    if(BoolPref(@"haptic",YES)) [[[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    if(!self.isOpen) self.isOpen=YES;
    self.page=@"apps";self.apps=InstalledApps();
    [self draw];
}
- (void)draw {
    if(!self.window) return;
    [self removePanel];
    [self drawOrb];
    if(self.isOpen) {
        [self buildPanel];
        [self.window.rootViewController.view bringSubviewToFront:self.orb];
    }
}
- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint p=[g locationInView:self.window.rootViewController.view];
    if(g.state==UIGestureRecognizerStateBegan || g.state==UIGestureRecognizerStateChanged) {
        CGFloat w=self.window.bounds.size.width,h=self.window.bounds.size.height;
        CGFloat orbW=self.orbWidth,orbH=self.orbHeight;
        self.orb.center=CGPointMake(Clamp(p.x,orbW*.35,w-orbW*.35),
            Clamp(p.y,60+orbH/2,h-36-orbH/2));
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
    self.isOpen=!self.isOpen; self.page=@"apps";
    if(self.isOpen) self.apps=InstalledApps();
    FMLog(self.isOpen?@"menu-open":@"menu-close",nil);
    if(BoolPref(@"haptic",YES)) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    }
    [self draw];
}
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l=[UILabel new]; l.text=text; l.font=[UIFont systemFontOfSize:size weight:weight];
    l.textColor=UIColor.labelColor; l.numberOfLines=0; return l;
}
- (UIView *)rowForTitle:(NSString *)title icon:(NSString *)icon height:(CGFloat)height action:(SEL)action {
    UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,278,height)];
    row.backgroundColor=[UIColor.secondarySystemGroupedBackgroundColor colorWithAlphaComponent:.23];
    row.layer.cornerRadius=MIN(18,height*.38);
    row.layer.borderWidth=.4;
    row.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:.24].CGColor;
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
    box.backgroundColor=[UIColor.secondarySystemFillColor colorWithAlphaComponent:.50];
    UIImage *real=FMGuestIcon(app);
    if(real) {
        UIImageView *iv=[[UIImageView alloc] initWithImage:real];
        iv.frame=box.bounds;iv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        iv.contentMode=UIViewContentModeScaleAspectFill;
        [box addSubview:iv];
    } else {
        UIImageView *fallback=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"app.fill"]];
        fallback.tintColor=FMAccent();fallback.contentMode=UIViewContentModeScaleAspectFit;
        fallback.frame=CGRectInset(box.bounds,size*.26,size*.26);
        [box addSubview:fallback];
    }
    return box;
}
- (UIView *)appRow:(NSDictionary *)app {
    CGFloat w=275,h=52;
    UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,w,h)];
    row.backgroundColor=[UIColor.secondarySystemGroupedBackgroundColor colorWithAlphaComponent:.16];
    row.layer.cornerRadius=17;
    UIView *icon=[self iconViewForApp:app size:37];
    icon.frame=CGRectMake(7,7.5,37,37);
    icon.userInteractionEnabled=NO;[row addSubview:icon];
    UILabel *name=[self label:app[@"title"] size:14 weight:UIFontWeightSemibold];
    name.frame=CGRectMake(54,5,190,25);name.lineBreakMode=NSLineBreakByTruncatingTail;
    [row addSubview:name];
    UILabel *subtitle=[self label:@"轻触切换 · 单任务" size:10 weight:UIFontWeightRegular];
    subtitle.textColor=UIColor.secondaryLabelColor;subtitle.frame=CGRectMake(54,29,190,15);
    [row addSubview:subtitle];
    UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor=UIColor.tertiaryLabelColor;
    chevron.frame=CGRectMake(251,21,8,11);[row addSubview:chevron];
    objc_setAssociatedObject(row,@selector(switchFromRow:),app,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [row addTarget:self action:@selector(switchFromRow:) forControlEvents:UIControlEventTouchUpInside];
    return row;
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
    CGFloat available=bounds.size.height-safeTop-safeBottom;
    BOOL small=[self.page isEqualToString:@"apps"];
    CGFloat pw=MIN(small?304:346,bounds.size.width-28);
    CGFloat target=small?MIN(550,228+72*MIN(self.apps.count,5)):610;
    if([self.page isEqualToString:@"manage"]) target=620;
    if([self.page isEqualToString:@"diy"]) target=675;
    CGFloat ph=MIN(available,target);
    CGFloat x=self.left?15:bounds.size.width-pw-15;
    CGFloat y=small?Clamp(CGRectGetMidY(self.orb.frame)-ph*.48,
                          safeTop,bounds.size.height-safeBottom-ph)
                   :safeTop+(available-ph)*.5;
    UIControl *under=[[UIControl alloc] initWithFrame:bounds];
    under.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:.06];
    [under addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.window.rootViewController.view addSubview:under];
    self.dismissLayer=under;
    UIView *shadow=[[UIView alloc] initWithFrame:CGRectMake(x,y,pw,ph)];
    shadow.layer.shadowColor=UIColor.blackColor.CGColor;
    shadow.layer.shadowOpacity=.15;shadow.layer.shadowRadius=24;
    shadow.layer.shadowOffset=CGSizeMake(0,9);
    UIView *glass=[self glass:shadow.bounds radius:small?28:32 strong:YES];
    [shadow addSubview:glass];
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:CGRectInset(glass.bounds,14,14)];
    scroll.showsVerticalScrollIndicator=NO;
    scroll.alwaysBounceVertical=NO;
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    scroll.contentInset=UIEdgeInsetsMake(0,0,4,0);
    [glass addSubview:scroll];
    UIStackView *stack=[self stack];
    stack.spacing=small?7:10;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    if([self.page isEqualToString:@"apps"]) [self appPage:stack];
    else if([self.page isEqualToString:@"settings"]) [self settingsPage:stack];
    else if([self.page isEqualToString:@"diy"]) [self diyPage:stack];
    else if([self.page isEqualToString:@"manage"]) [self managePage:stack];
    else [self perAppPage:stack];
    [self.window.rootViewController.view addSubview:shadow];
    self.panel=shadow;
    shadow.alpha=0;
    shadow.transform=CGAffineTransformMakeScale(.965,.96);
    NSTimeInterval duration=UIAccessibilityIsReduceMotionEnabled()?.10:.29;
    [UIView animateWithDuration:duration delay:0
        usingSpringWithDamping:.88 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
            shadow.alpha=1;shadow.transform=CGAffineTransformIdentity;
        } completion:nil];
}
- (void)header:(UIStackView *)stack title:(NSString *)title sub:(NSString *)sub {
    UILabel *a=[self label:title size:22 weight:UIFontWeightBold]; [stack addArrangedSubview:a];
    UILabel *b=[self label:sub size:12 weight:UIFontWeightRegular]; b.textColor=UIColor.secondaryLabelColor;
    [stack addArrangedSubview:b]; [self spacer:stack size:8];
}
- (void)appPage:(UIStackView *)s {
    [self header:s title:@"快速切换" sub:@"LC+SS · 经典全屏单任务"];
    [self addRow:[self rowForTitle:@"收起菜单" icon:@"xmark.circle.fill" height:42 action:@selector(toggle)] height:42 to:s];
    [self addRow:[self rowForTitle:@"返回 LiveContainer" icon:@"square.grid.2x2.fill" height:49 action:@selector(goHome)] height:49 to:s];
    if(BoolPref(@"showRestart",YES))
        [self addRow:[self rowForTitle:@"重新启动当前应用" icon:@"arrow.clockwise" height:45 action:@selector(restart)] height:45 to:s];
    [self spacer:s size:4];
    UILabel *appsTitle=[self label:@"我的应用" size:12 weight:UIFontWeightSemibold];
    appsTitle.textColor=UIColor.secondaryLabelColor; [s addArrangedSubview:appsTitle];
    for(NSDictionary *app in self.apps) {
        if([app[@"bundle"] isEqualToString:GuestID()]) continue;
        [self addRow:[self appRow:app] height:55 to:s];
    }
    if(self.apps.count<2) {
        UILabel *empty=[self label:@"暂无可快捷切换的应用；加锁或需要 JIT 的应用请从 LC 打开。" size:12 weight:UIFontWeightRegular];
        empty.textColor=UIColor.secondaryLabelColor; [s addArrangedSubview:empty];
    }
    [self spacer:s size:5];
    [self addRow:[self rowForTitle:@"外观与菜单设置" icon:@"slider.horizontal.3" height:45 action:@selector(openSettings)] height:45 to:s];
}
- (void)openSettings {self.page=@"settings";[self draw];}
- (void)openDIY {self.page=@"diy";[self draw];}
- (void)openPerApp {self.page=@"perapp";[self draw];}
- (void)backToSettings {self.page=@"settings";[self draw];}
- (void)backToApps {self.page=@"apps";[self draw];}
- (void)settingSwitch:(UIStackView*)s title:(NSString*)title key:(NSString*)key defaultValue:(BOOL)def tag:(NSInteger)tag {
    UIView *row=[[UIView alloc] initWithFrame:CGRectMake(0,0,280,48)];
    UILabel *l=[self label:title size:14 weight:UIFontWeightMedium];
    l.frame=CGRectMake(6,0,211,48); [row addSubview:l];
    UISwitch *sw=[UISwitch new]; sw.on=BoolPref(key,def); sw.tag=tag;
    sw.onTintColor=RGBA(.27,.53,1,1);
    sw.frame=CGRectMake(221,8,51,31);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw]; [self addRow:row height:48 to:s];
}
- (void)settingSlider:(UIStackView*)s title:(NSString*)title key:(NSString*)key min:(float)min max:(float)max def:(float)def tag:(NSInteger)tag {
    UILabel *l=[self label:title size:14 weight:UIFontWeightMedium];
    [s addArrangedSubview:l];
    UISlider *slider=[UISlider new];slider.minimumValue=min;slider.maximumValue=max;
    slider.value=FloatPref(key,def);slider.tag=tag;
    slider.tintColor=RGBA(.29,.52,1,1);
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addRow:slider height:28 to:s];
}
- (void)settingsPage:(UIStackView*)s {
    [self addRow:[self rowForTitle:@"返回切换菜单" icon:@"chevron.left" height:40 action:@selector(backToApps)] height:40 to:s];
    [self header:s title:@"悬浮菜单设置" sub:@"实时预览 · 不影响 LC+SS 主程序"];
    [self settingSwitch:s title:@"轻触震动反馈" key:@"haptic" defaultValue:YES tag:1];
    [self settingSwitch:s title:@"切换应用前确认" key:@"confirm" defaultValue:YES tag:2];
    [self settingSlider:s title:@"收起态透明度" key:@"idleAlpha" min:.25 max:1 def:.68 tag:10];
    [self settingSlider:s title:@"收起态尺寸" key:@"orbWidth" min:20 max:50 def:27 tag:11];
    [self addRow:[self rowForTitle:@"DIY 外观与菜单" icon:@"paintbrush.pointed.fill" height:48 action:@selector(openDIY)] height:48 to:s];
    [self addRow:[self rowForTitle:@"当前 App 独立设置" icon:@"square.on.square" height:48 action:@selector(openPerApp)] height:48 to:s];
    [self addRow:[self rowForTitle:@"导出诊断日志" icon:@"square.and.arrow.up" height:48 action:@selector(exportLogs)] height:48 to:s];
    [self addRow:[self rowForTitle:@"清空日志" icon:@"trash" height:48 action:@selector(clearLogs)] height:48 to:s];
}
- (void)diyPage:(UIStackView*)s {
    [self addRow:[self rowForTitle:@"返回设置" icon:@"chevron.left" height:40 action:@selector(backToSettings)] height:40 to:s];
    [self header:s title:@"DIY 编辑" sub:@"液态玻璃 · 自定义触感与可见项"];
    UILabel *intro=[self label:@"收起态：贴边玻璃胶囊\n展开态：可滚动磨砂应用面板" size:13 weight:UIFontWeightRegular];
    intro.textColor=UIColor.secondaryLabelColor;[s addArrangedSubview:intro];
    [self settingSlider:s title:@"透明度" key:@"idleAlpha" min:.25 max:1 def:.68 tag:10];
    [self settingSlider:s title:@"胶囊大小" key:@"orbWidth" min:20 max:50 def:27 tag:11];
    [self settingSwitch:s title:@"显示重新启动" key:@"showRestart" defaultValue:YES tag:3];
    [self settingSwitch:s title:@"圆形玻璃按钮" key:@"roundOrb" defaultValue:NO tag:5];
    [self settingSlider:s title:@"玻璃着色强度" key:@"glassTint" min:.03 max:.36 def:.16 tag:13];
    [self settingSwitch:s title:@"轻触震动" key:@"haptic" defaultValue:YES tag:1];
    [self addRow:[self rowForTitle:@"恢复默认样式" icon:@"arrow.counterclockwise" height:44 action:@selector(resetStyle)] height:44 to:s];
}
- (void)perAppPage:(UIStackView*)s {
    [self addRow:[self rowForTitle:@"返回设置" icon:@"chevron.left" height:40 action:@selector(backToSettings)] height:40 to:s];
    [self header:s title:@"当前 App" sub:GuestID()];
    [self settingSwitch:s title:@"当前 App 切换前确认" key:AppPref() defaultValue:BoolPref(@"confirm",YES) tag:4];
    [self settingSlider:s title:@"当前 App 收起态透明度" key:[@"appAlpha." stringByAppendingString:GuestID()] min:.25 max:1 def:FloatPref(@"idleAlpha",.68) tag:12];
    UILabel *note=[self label:@"仅覆盖当前 App 的行为；不影响其他 Guest。所有配置保存在 LC 宿主偏好设置中。" size:12 weight:UIFontWeightRegular];
    note.textColor=UIColor.secondaryLabelColor;
    [s addArrangedSubview:note];
}
- (void)switchChanged:(UISwitch*)sw {
    NSString *key= sw.tag==1?@"haptic":sw.tag==2?@"confirm":sw.tag==3?@"showRestart":sw.tag==5?@"roundOrb":AppPref();
    SetPref(key,@(sw.isOn));
    if(sw.tag==3 || sw.tag==5) [self draw];
}
- (void)sliderChanged:(UISlider*)slider {
    NSString *key=slider.tag==10?@"idleAlpha":slider.tag==11?@"orbWidth":slider.tag==13?@"glassTint":[@"appAlpha." stringByAppendingString:GuestID()];
    SetPref(key,@(slider.value));
    if(slider.tag==10 || slider.tag==12) self.orb.alpha=slider.value;
    else if(slider.tag==13) [self draw];
    else { [self drawOrb]; if(self.isOpen) [self.window.rootViewController.view bringSubviewToFront:self.orb]; }
}
- (void)exportLogs {
    FMLog(@"diagnostics-export",@"user-requested");
    NSString *file=FMLogFile();
    if(!file) { [self showMessage:@"无法导出" details:@"诊断目录不可用"];return; }
    NSMutableData *content=[NSMutableData data];
    for(NSString *p in @[[file stringByAppendingString:@".old"],file]) {
        NSData *part=[NSData dataWithContentsOfFile:p];
        if(part) [content appendData:part];
    }
    if(!content.length) { [self showMessage:@"暂无日志" details:@"尚未产生诊断记录"];return; }
    NSString *out=[NSTemporaryDirectory() stringByAppendingPathComponent:@"LCFloatingMenu-Diagnostics.log"];
    if(![content writeToFile:out atomically:YES]) {
        [self showMessage:@"导出失败" details:@"无法准备诊断文件"];
        return;
    }
    if(self.window.rootViewController.presentedViewController) return;
    UIActivityViewController *share=[[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:out]] applicationActivities:nil];
    UIPopoverPresentationController *popover=share.popoverPresentationController;
    if(popover) {
        popover.sourceView=self.panel ?: self.orb;
        popover.sourceRect=CGRectMake(10,10,25,25);
    }
    [self.window.rootViewController presentViewController:share animated:YES completion:nil];
}
- (void)clearLogs {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清空诊断日志？"
        message:@"只会清除悬浮菜单日志，不影响 App 或设置。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        NSString *f=FMLogFile();
        if(!f) return;
        [NSFileManager.defaultManager removeItemAtPath:f error:nil];
        [NSFileManager.defaultManager removeItemAtPath:[f stringByAppendingString:@".old"] error:nil];
        FMLog(@"diagnostics-reset",@"user-requested");
    }]];
    if(!self.window.rootViewController.presentedViewController)
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)resetStyle {
    SetPref(@"idleAlpha",@(.68));SetPref(@"orbWidth",@(27));
    SetPref(@"showRestart",@YES);SetPref(@"haptic",@YES);
    SetPref(@"roundOrb",@NO);SetPref(@"glassTint",@(.16));
    [self draw];
}
- (void)launchPath:(NSString*)path uuid:(NSString*)uuid {
    if(!path.length) {FMLog(@"switch-rejected",@"empty-target");return;}
    FMLog(@"switch-request",[path isEqualToString:@"ui"]?@"return-home":@"new-guest");
    if(![path isEqualToString:@"ui"]) {
        BOOL exists=NO;
        for(NSDictionary *item in InstalledApps()) {
            if([item[@"path"] isEqualToString:path] && [item[@"uuid"] isEqualToString:uuid]) {exists=YES;break;}
        }
        if(!exists) { FMLog(@"switch-rejected",@"guest-ineligible"); [self showMessage:@"不可安全切换" details:@"目标 App 不存在、已锁定、需要 JIT，或补丁需要在 LC 中重新签名。请先返回 LC 启动。"]; return; }
    }
    Class utils=NSClassFromString(@"LCSharedUtils");
    SEL sel=NSSelectorFromString(@"launchToGuestAppWithURL:");
    if(![utils respondsToSelector:sel]) {
        [self showMessage:@"切换不可用" details:@"当前 LC 版本不提供启动接口。"];
        return;
    }
    NSUserDefaults *host=HostDefaults();
    if([path isEqualToString:@"ui"]) {
        SEL home=NSSelectorFromString(@"launchToGuestAppWithClassicMode:");
        if(![utils respondsToSelector:home]) return;
        [host setObject:@"ui" forKey:@"selected"];
        [host removeObjectForKey:@"selectedContainer"];
        [host setBool:NO forKey:@"LCOpenSideStore"];
        BOOL ok=((BOOL(*)(id,SEL,NSUInteger))objc_msgSend)(utils,home,0);
        if(!ok) [host removeObjectForKey:@"selected"];
        return;
    }
    // SideStore and pending deep links must not intercept a guest switch.
    [host setBool:NO forKey:@"LCOpenSideStore"];
    [host removeObjectForKey:@"launchAppUrlScheme"];
    NSURLComponents *url=[NSURLComponents new];
    url.scheme=LCClassCall(NSUserDefaults.class,@"lcAppUrlScheme");
    if(!url.scheme.length) {
        [self showMessage:@"切换不可用" details:@"无法确认当前 LC 的 URL Scheme。"];
        return;
    }
    url.host=@"livecontainer-launch";
    NSMutableArray *qs=[NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"bundle-name" value:path]];
    if(uuid.length) [qs addObject:[NSURLQueryItem queryItemWithName:@"container-folder-name" value:uuid]];
    url.queryItems=qs;
    if(!url.URL) {
        [self showMessage:@"切换失败" details:@"目标 URL 不合法。未发起切换。"];
        return;
    }
    BOOL accepted=((BOOL(*)(id,SEL,NSURL*))objc_msgSend)(utils,sel,url.URL);
    FMLog(accepted?@"switch-accepted":@"switch-rejected",@"LCSharedUtils");
    if(!accepted) {
        [host removeObjectForKey:@"selected"];
        [host removeObjectForKey:@"selectedContainer"];
        [self showMessage:@"切换失败" details:@"LC 未能接受启动请求。已清理待启动状态，请返回 LC 检查签名。"];
    }
}
- (void)showMessage:(NSString *)title details:(NSString *)detail {
    FMLog(@"ui-warning",title);
    if(!self.window.rootViewController.presentedViewController) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
    }
}
- (void)confirmTitle:(NSString*)title action:(void(^)(void))action {
    if(!BoolPref(AppPref(),BoolPref(@"confirm",YES))) {action();return;}
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title
        message:@"经典单任务切换会结束当前 App 的内存状态；请先保存进度。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){action();}]];
    if(!self.window.rootViewController.presentedViewController)
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)goHome {
    [self confirmTitle:@"返回 LiveContainer？" action:^{[self launchPath:@"ui" uuid:nil];}];
}
- (void)restart {
    NSString *current=GuestID();
    for(NSDictionary *app in self.apps) {
        if([app[@"bundle"] isEqualToString:current]) {
            NSDictionary *target=app;
            [self confirmTitle:@"重新启动当前 App？" action:^{
                [self launchPath:target[@"path"] uuid:target[@"uuid"]];
            }];
            return;
        }
    }
}
- (void)switchFromRow:(UIControl *)sender {
    NSDictionary *app=objc_getAssociatedObject(sender,@selector(switchFromRow:));
    if(!app) return;
    [self confirmTitle:[NSString stringWithFormat:@"切换到 %@？",app[@"title"]] action:^{
        [self launchPath:app[@"path"] uuid:app[@"uuid"]];
    }];
}
@end

__attribute__((constructor)) static void LCFloatingMenuEntry(void) {
    // UIWindow/UIApplication are not necessarily ready when a dylib constructor executes.
    dispatch_async(dispatch_get_main_queue(), ^{
        FMLog(@"dylib-loaded",@"constructor");
        NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
        for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UIWindowDidBecomeVisibleNotification,UIApplicationDidChangeStatusBarOrientationNotification]) {
            [nc addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                [[FMManager shared] installIfPossible];
            }];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.7*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{ [[FMManager shared] installIfPossible]; });
    });
}
