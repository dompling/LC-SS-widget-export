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
            NSString *line=[NSString stringWithFormat:@"%@ event=%@ detail=%@\n",
                NSDate.date,event?:@"unknown",detail?:@""];
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
                              @"bundle":info[@"CFBundleIdentifier"] ?: @""}];
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
- (CGFloat)orbWidth {return Clamp(FloatPref(@"orbWidth",27),20,55);}
- (CGFloat)orbHeight {return BoolPref(@"roundOrb",NO)?self.orbWidth:self.orbWidth*1.68;}
- (CGRect)orbFrame {
    CGRect b=self.window.bounds;
    CGFloat w=self.orbWidth,h=self.orbHeight;
    CGFloat x=self.left ? -w*.15 : b.size.width-w*.85;
    return CGRectMake(x,Clamp(b.size.height*self.orbY-h*.5,60,b.size.height-h-36),w,h);
}
- (UIView *)glass:(CGRect)frame radius:(CGFloat)radius strong:(BOOL)strong {
    UIView *v=[[UIView alloc] initWithFrame:frame];
    v.layer.cornerRadius=radius; v.clipsToBounds=YES;
    UIBlurEffectStyle style=strong?UIBlurEffectStyleSystemMaterial:UIBlurEffectStyleSystemUltraThinMaterial;
    UIVisualEffectView *blur=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:style]];
    blur.frame=v.bounds; blur.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [v addSubview:blur];
    UIView *wash=[[UIView alloc] initWithFrame:v.bounds];
    wash.backgroundColor=RGBA(.73,.82,1,Clamp(FloatPref(@"glassTint",strong?.20:.12),.03,.36));
    wash.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [v addSubview:wash];
    v.layer.borderWidth=.75; v.layer.borderColor=RGBA(1,1,1,.70).CGColor;
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
}
- (void)drawOrb {
    [self.orb removeFromSuperview]; self.orb=nil;
    CGRect f=[self orbFrame];
    UIButton *button=[FMHitButton buttonWithType:UIButtonTypeCustom];
    button.frame=f;
    button.layer.cornerRadius=f.size.width*.5;
    button.layer.shadowColor=RGBA(.32,.50,1,1).CGColor;
    button.layer.shadowOpacity=.27;
    button.layer.shadowRadius=8;
    button.layer.shadowOffset=CGSizeMake(0,2);
    UIView *glass=[self glass:button.bounds radius:f.size.width*.5 strong:NO];
    glass.userInteractionEnabled=NO;
    [button addSubview:glass];
    UIView *core=[[UIView alloc] initWithFrame:CGRectMake(0,0,8,8)];
    core.center=CGPointMake(f.size.width*.5,f.size.height*.5);
    core.backgroundColor=UIColor.whiteColor; core.layer.cornerRadius=4;
    core.layer.shadowColor=RGBA(.19,.53,1,1).CGColor;
    core.layer.shadowOpacity=.9; core.layer.shadowRadius=6;
    core.userInteractionEnabled=NO;
    [button addSubview:core];
    button.alpha=self.isOpen?1:Clamp(FloatPref([@"appAlpha." stringByAppendingString:GuestID()],FloatPref(@"idleAlpha",.68)),.22,1);
    button.accessibilityLabel=@"展开或收起悬浮菜单";
    button.accessibilityTraits=UIAccessibilityTraitButton;
    [button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [button addGestureRecognizer:pan];
    [self.window.rootViewController.view addSubview:button];
    self.orb=button;
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
    UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,280,height)];
    row.backgroundColor=RGBA(1,1,1,.20);
    row.layer.cornerRadius=17;
    UIImageView *symbol=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    symbol.tintColor=RGBA(.24,.49,1,1);
    symbol.frame=CGRectMake(15,(height-23)/2,23,23);
    [row addSubview:symbol];
    UILabel *name=[self label:title size:15 weight:UIFontWeightMedium];
    name.frame=CGRectMake(51,0,216,height);
    [row addSubview:name];
    if(action) [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return row;
}
- (UIView *)appRow:(NSDictionary *)app {
    UIControl *row=[[UIControl alloc] initWithFrame:CGRectMake(0,0,280,55)];
    row.backgroundColor=RGBA(1,1,1,.19); row.layer.cornerRadius=17;
    UIView *icon=[[UIView alloc] initWithFrame:CGRectMake(9,7,41,41)];
    icon.backgroundColor=TintFor(app[@"bundle"]);
    icon.layer.cornerRadius=13;
    [row addSubview:icon];
    UILabel *letter=[self label:[[app[@"title"] substringToIndex:MIN(1,[app[@"title"] length])] uppercaseString] size:21 weight:UIFontWeightBold];
    letter.textColor=UIColor.whiteColor; letter.textAlignment=NSTextAlignmentCenter;
    letter.frame=icon.bounds;
    [icon addSubview:letter];
    UILabel *name=[self label:app[@"title"] size:15 weight:UIFontWeightSemibold];
    name.frame=CGRectMake(60,5,175,28);
    [row addSubview:name];
    UILabel *subtitle=[self label:@"单任务切换" size:10 weight:UIFontWeightRegular];
    subtitle.textColor=UIColor.secondaryLabelColor;
    subtitle.frame=CGRectMake(60,29,175,17);
    [row addSubview:subtitle];
    UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor=UIColor.tertiaryLabelColor;
    chevron.frame=CGRectMake(251,21,9,13); [row addSubview:chevron];
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
    CGFloat totalWidth=self.window.bounds.size.width;
    CGFloat pw=MIN(325,totalWidth-35),ph=MIN(self.window.bounds.size.height-115,560);
    CGFloat x=self.left?15:totalWidth-pw-15;
    CGFloat y=Clamp(CGRectGetMidY(self.orb.frame)-ph*.50,55,self.window.bounds.size.height-ph-36);
    UIView *shadow=[[UIView alloc] initWithFrame:CGRectMake(x,y,pw,ph)];
    shadow.layer.shadowColor=UIColor.blackColor.CGColor;
    shadow.layer.shadowOpacity=.21; shadow.layer.shadowRadius=22;
    shadow.layer.shadowOffset=CGSizeMake(0,10);
    UIView *glass=[self glass:shadow.bounds radius:29 strong:YES];
    [shadow addSubview:glass];
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:CGRectInset(glass.bounds,13,12)];
    scroll.showsVerticalScrollIndicator=NO; scroll.alwaysBounceVertical=YES;
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [glass addSubview:scroll];
    UIStackView *s=[self stack];
    [scroll addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [s.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [s.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [s.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [s.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    if([self.page isEqualToString:@"apps"]) [self appPage:s];
    else if([self.page isEqualToString:@"settings"]) [self settingsPage:s];
    else if([self.page isEqualToString:@"diy"]) [self diyPage:s];
    else [self perAppPage:s];
    [self.window.rootViewController.view addSubview:shadow];
    self.panel=shadow; shadow.alpha=0; shadow.transform=CGAffineTransformMakeScale(.94,.94);
    [UIView animateWithDuration:.30 delay:0 usingSpringWithDamping:.83 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
            shadow.alpha=1; shadow.transform=CGAffineTransformIdentity;
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
