#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

typedef NSInteger UIInterfaceOrientation;
enum { UIInterfaceOrientationUnknown=0, UIInterfaceOrientationPortrait=1,
    UIInterfaceOrientationPortraitUpsideDown=2,UIInterfaceOrientationLandscapeLeft=3,UIInterfaceOrientationLandscapeRight=4 };
static BOOL UIInterfaceOrientationIsLandscape(NSInteger value) { return value==3 || value==4; }
typedef struct { CGFloat top,left,bottom,right; } UIEdgeInsets;
static UIEdgeInsets UIEdgeInsetsMake(CGFloat top,CGFloat left,CGFloat bottom,CGFloat right) { return (UIEdgeInsets){top,left,bottom,right}; }
@interface OrbitHostScene : NSObject
@property UIInterfaceOrientation interfaceOrientation;
@end
@implementation OrbitHostScene @end
@compatibility_alias UIWindowScene OrbitHostScene;
@interface OrbitLayer : NSObject
@property CGFloat cornerRadius;
@end
@implementation OrbitLayer @end
@interface OrbitView : NSObject
@property CGRect frame;
@property(readonly) CGRect bounds;
@property(nonatomic,strong) OrbitView *window;
@property(nonatomic,strong) UIWindowScene *windowScene;
@property UIEdgeInsets safeAreaInsets;
@property(nonatomic,strong) OrbitView *superview;
@property CGAffineTransform transform;
@property(nonatomic,strong) OrbitLayer *layer;
- (void)layoutIfNeeded;
@end
@implementation OrbitView
- (CGRect)bounds { return (CGRect){CGPointZero,self.frame.size}; }
- (void)layoutIfNeeded {}
@end
@compatibility_alias UIView OrbitView;
@compatibility_alias UIWindow OrbitView;
@compatibility_alias _UISceneHostingView OrbitView;
@interface OrbitHostingController : NSObject
@property(nonatomic,strong) UIView *sceneView;
@end
@implementation OrbitHostingController @end
@compatibility_alias _UISceneHostingController OrbitHostingController;
@interface OrbitSettings : NSObject
@property CGRect frame;
@property UIInterfaceOrientation interfaceOrientation;
@property NSInteger userInterfaceStyle,deviceOrientation;
@property BOOL foreground,canShowAlerts,statusBarDisabled;
@property NSInteger level,statusBarStyle;
@property(nonatomic,strong) id cornerRadiusConfiguration,displayConfiguration;
@property(nonatomic,copy) NSString *persistenceIdentifier;
@property UIEdgeInsets peripheryInsets,safeAreaInsetsPortrait,safeAreaEdgeInsets;
@end
@implementation OrbitSettings @end
@compatibility_alias UIMutableApplicationSceneSettings OrbitSettings;
@compatibility_alias UIMutableApplicationSceneClientSettings OrbitSettings;
@interface OrbitCornerRadius : NSObject
- (instancetype)initWithTopLeft:(CGFloat)a bottomLeft:(CGFloat)b bottomRight:(CGFloat)c topRight:(CGFloat)d;
@end
@implementation OrbitCornerRadius
- (instancetype)initWithTopLeft:(CGFloat)a bottomLeft:(CGFloat)b bottomRight:(CGFloat)c topRight:(CGFloat)d { return [super init]; }
@end
@compatibility_alias BSCornerRadiusConfiguration OrbitCornerRadius;
#define PrivClass(name) name.class
@interface OrbitScreen : NSObject
+ (instancetype)mainScreen;
@property(nonatomic,strong) id displayConfiguration;
@end
@implementation OrbitScreen
+ (instancetype)mainScreen { return [self new]; }
@end
@compatibility_alias UIScreen OrbitScreen;
@interface OrbitParameters : NSObject
@property(nonatomic,strong) OrbitSettings *settings;
- (void)updateSettingsWithBlock:(void (^)(id))block;
- (void)updateClientSettingsWithBlock:(void (^)(id))block;
@end
@compatibility_alias FBSMutableSceneParameters OrbitParameters;
@interface FBSSceneTransitionContext : NSObject @end
@interface OrbitController : NSObject
@property(nonatomic,strong) UIView *view;
@property(nonatomic,strong) OrbitController *parentViewController,*appSceneVC;
@property(nonatomic,weak) id delegate;
@property(nonatomic,strong) OrbitSettings *settings;
@property(nonatomic,strong) OrbitController *presenter,*scene;
@property(nonatomic,strong) OrbitSettings *initialSettings;
@property(nonatomic,copy) NSString *dataUUID;
@property BOOL usesHostingControllerAPI,isNativeWindow,throwDuringSetup;
- (void)nativePresenterSetup;
- (void)configureParameters:(void (^)(FBSMutableSceneParameters *))block;
- (id)ui_viewServiceComponent;
- (void)hook__performUpdateWithoutActivation:(void (^)(id,id))block;
- (void)updateSettingsWithBlock:(void (^)(id))block;
@end
@compatibility_alias UIViewController OrbitController;
@compatibility_alias FBScene OrbitController;
@interface OrbitDecorated : OrbitController @end
@implementation OrbitDecorated @end
@interface OrbitDevice : NSObject
+ (instancetype)currentDevice;
@property NSInteger orientation;
@end
@implementation OrbitDevice
+ (instancetype)currentDevice { return [self new]; }
@end
@compatibility_alias UIDevice OrbitDevice;
static BOOL Enabled=YES;
static NSUInteger Updates,Assertions,Failures;
static Class WindowClass;
static IMP OriginalSceneSettings,OriginalFinalSettings,OriginalInitialSettings,OriginalPresenter;
static UIViewController *InitialSceneWindow;
static NSArray *ManagedWindows;
static BOOL LCHasRemoteSheetProviderSelector=YES;
@interface LCOrbitMultitask : NSObject @end
@implementation LCOrbitMultitask
+ (NSArray *)windows { return ManagedWindows; }
@end
static BOOL Fullscreen(void) { return Enabled; }
static UIViewController *SceneController(UIViewController *window) { return window.appSceneVC; }
static BOOL OrbitPiPProtectedWindow(UIViewController *window) { return NO; }
static void LayoutFullscreen(UIViewController *window) {}
static void NativeSettings(id object,SEL selector,void (^block)(id)) {
    OrbitController *scene=object;Updates++;if(block) block(scene.settings);
}
static void InstallFinalSceneHook(void) {}
static void NativeParameterSettings(id object,SEL selector,void (^block)(id)) {
    if(block) block([(OrbitParameters *)object settings]);
}
static void NativePresenter(id object,SEL selector) { [(OrbitController *)object nativePresenterSetup]; }
static void NativeRemoteSettings(id object,SEL selector,void (^block)(id,id)) {
    OrbitController *remote=object;if(block) block(remote.settings,nil);
}
static UIEdgeInsets LCUIEdgeInsetsRotateToOrientation(UIEdgeInsets insets,NSInteger orientation);
#include "scene.inc"
@implementation OrbitParameters
- (instancetype)init { self=[super init];if(self) { _settings=[OrbitSettings new];_settings.frame=CGRectMake(0,0,320,480);_settings.interfaceOrientation=UIInterfaceOrientationPortrait; }return self; }
- (void)updateSettingsWithBlock:(void (^)(id))block { InitialSceneSettings(self,_cmd,block); }
- (void)updateClientSettingsWithBlock:(void (^)(id))block { if(block) block([OrbitSettings new]); }
@end
@implementation OrbitController
- (void)nativePresenterSetup {
    if(self.throwDuringSetup) [NSException raise:@"SetupFixture" format:@"original setup failed"];
#include "initial-settings.inc"
    if(self.usesHostingControllerAPI) {
        FBScene *scene=self.presenter.scene;
#include "hosting-parameters.inc"
        self.initialSettings=scene.initialSettings;
    } else {
        FBSMutableSceneParameters *parameters=[FBSMutableSceneParameters new];
#include "legacy-parameters.inc"
        self.initialSettings=parameters.settings;
    }
}
- (void)configureParameters:(void (^)(FBSMutableSceneParameters *))block {
    FBSMutableSceneParameters *parameters=[FBSMutableSceneParameters new];
    block(parameters);
    // This captures the values at the remote configure/create boundary, before
    // PresenterReady can issue its post-setup UpdateScene.
    self.initialSettings=parameters.settings;
}
- (void)updateSettingsWithBlock:(void (^)(id))block { SceneSettings(self,_cmd,block); }
- (id)ui_viewServiceComponent { return nil; }
- (void)hook__performUpdateWithoutActivation:(void (^)(id,id))block { FinalSceneSettings(self,_cmd,block); }
@end
static UIEdgeInsets LCUIEdgeInsetsRotateToOrientation(UIEdgeInsets insets,NSInteger orientation) {return PortraitInsets(insets,orientation);}
static void Expect(BOOL result,NSString *message) {
    Assertions++;if(!result) {Failures++;fprintf(stderr,"FAIL: %s\n",message.UTF8String);}
}
static void NativeResize(OrbitController *scene) {
    [scene updateSettingsWithBlock:^(OrbitSettings *settings) {
        settings.frame=CGRectMake(10,-44,320,480);
        settings.interfaceOrientation=UIInterfaceOrientationPortrait;
        settings.peripheryInsets=(UIEdgeInsets){0,0,0,0};
    }];
}
int main(void) {
    @autoreleasepool {
        WindowClass=OrbitDecorated.class;OriginalSceneSettings=(IMP)NativeSettings;
        OriginalInitialSettings=(IMP)NativeParameterSettings;OriginalPresenter=(IMP)NativePresenter;
        OrbitController *window=[OrbitDecorated new],*scene=[OrbitController new];
        window.view=[UIView new];window.view.frame=CGRectMake(0,0,390,844);
        UIWindow *host=[UIWindow new];host.frame=CGRectMake(0,0,390,844);
        host.windowScene=[UIWindowScene new];host.windowScene.interfaceOrientation=UIInterfaceOrientationPortrait;
        host.safeAreaInsets=(UIEdgeInsets){59,0,34,0};window.view.window=host;
        window.appSceneVC=scene;scene.delegate=window;scene.settings=[OrbitSettings new];
        UpdateScene(window,nil);
        Expect(CGRectEqualToRect(scene.settings.frame,CGRectMake(0,0,390,844)),@"normal fullscreen scene uses complete host dimensions");
        NativeResize(scene);
        Expect(CGRectEqualToRect(scene.settings.frame,CGRectMake(0,0,390,844)),@"LC delayed resize cannot replace fullscreen frame or introduce a negative origin");
        Expect(scene.settings.peripheryInsets.top==59 && scene.settings.peripheryInsets.bottom==34,@"LC delayed resize cannot erase host safe area");
        NSUInteger before=Updates;
        host.frame=CGRectZero;window.view.frame=CGRectZero;UpdateScene(window,nil);
        Expect(Updates==before,@"transient zero host geometry never reaches remote settings");
        host.frame=CGRectMake(0,0,NAN,844);window.view.frame=host.frame;UpdateScene(window,nil);
        Expect(Updates==before,@"non-finite geometry never reaches remote settings");
        host.frame=CGRectMake(0,0,390,844);window.view.frame=host.frame;
        host.windowScene.interfaceOrientation=UIInterfaceOrientationUnknown;UpdateScene(window,nil);
        Expect(Updates==before,@"unknown orientation does not mix new dimensions with invalid direction");
        host.frame=CGRectMake(0,0,844,390);window.view.frame=host.frame;
        host.windowScene.interfaceOrientation=UIInterfaceOrientationLandscapeLeft;
        host.safeAreaInsets=(UIEdgeInsets){0,59,21,59};NativeResize(scene);
        Expect(scene.settings.interfaceOrientation==UIInterfaceOrientationLandscapeLeft &&
            CGRectEqualToRect(scene.settings.frame,CGRectMake(0,0,390,844)),@"final settings keep host landscape direction and LC portrait-normalized frame together");
        Enabled=NO;NativeResize(scene);
        Expect(CGRectEqualToRect(scene.settings.frame,CGRectMake(10,-44,320,480)),@"disabled takeover preserves native LC scene updates");
        Enabled=YES;OrbitController *unmanaged=[OrbitController new];scene.delegate=unmanaged;NativeResize(scene);
        Expect(CGRectEqualToRect(scene.settings.frame,CGRectMake(10,-44,320,480)),@"unmanaged scene delegates retain native behavior");
        scene.delegate=window;host.frame=CGRectMake(0,0,390,844);
        host.windowScene.interfaceOrientation=UIInterfaceOrientationPortrait;host.safeAreaInsets=(UIEdgeInsets){59,0,34,0};
        OrbitController *remote=[OrbitController new];remote.settings=[OrbitSettings new];
        scene.presenter=[OrbitController new];scene.presenter.scene=remote;ManagedWindows=@[window];
        OrbitHostingController *hosting=[OrbitHostingController new];hosting.sceneView=[UIView new];
        hosting.sceneView.transform=CGAffineTransformIdentity;hosting.sceneView.superview=[UIView new];remote.delegate=hosting;
        OriginalFinalSettings=(IMP)NativeRemoteSettings;
        void (^lateUpdate)(id,id)=^(OrbitSettings *settings,id context) {
            settings.frame=CGRectMake(0,0,320,480);settings.interfaceOrientation=UIInterfaceOrientationPortrait;
            settings.userInterfaceStyle=2;
        };
        hook_FBScene_performUpdateWithoutActivation(remote,NSSelectorFromString(@"_performUpdateWithoutActivation:"),lateUpdate);
        Expect(remote.settings.safeAreaEdgeInsets.top==59 && remote.settings.safeAreaEdgeInsets.bottom==34,
            @"remote settings preserve host safe area after LC derives zero insets from its hosting view");
        Expect(CGRectEqualToRect(remote.settings.frame,CGRectMake(0,0,390,844)) && remote.settings.userInterfaceStyle==2,
            @"remote boundary corrects dimensions without dropping the native appearance update");
        ManagedWindows=@[];
        hook_FBScene_performUpdateWithoutActivation(remote,NSSelectorFromString(@"_performUpdateWithoutActivation:"),lateUpdate);
        Expect(remote.settings.safeAreaEdgeInsets.top==0 && remote.settings.frame.size.width==320,
            @"remote scenes outside the managed registry retain LC settings");
        // Initial scene parameters must be correct before the real LC setup
        // block reaches configureParameters (hosting) or scene creation (legacy).
        Enabled=YES;scene.delegate=window;scene.dataUUID=@"guest-container";
        scene.view=[UIView new];scene.view.safeAreaInsets=(UIEdgeInsets){0,0,0,0};
        scene.presenter=[OrbitController new];scene.presenter.scene=[OrbitController new];
        host.frame=CGRectMake(0,0,390,844);host.windowScene.interfaceOrientation=UIInterfaceOrientationPortrait;
        host.safeAreaInsets=(UIEdgeInsets){59,0,34,0};
        for(NSNumber *hostingAPI in @[@YES,@NO]) {
            scene.usesHostingControllerAPI=hostingAPI.boolValue;
            PresenterReady(scene,NSSelectorFromString(@"setUpAppPresenter"));
            OrbitSettings *first=scene.initialSettings;
            Expect(CGRectEqualToRect(first.frame,CGRectMake(0,0,390,844)) && first.interfaceOrientation==1,
                hostingAPI.boolValue?@"hosting initial parameters have full portrait dimensions before configure":@"legacy initial parameters have full portrait dimensions before create");
            Expect(first.safeAreaInsetsPortrait.top==59 && first.safeAreaInsetsPortrait.bottom==34 &&
                first.peripheryInsets.top==59 && first.safeAreaEdgeInsets.bottom==34,
                hostingAPI.boolValue?@"hosting initial parameters reserve statusbar and home indicator":@"legacy initial parameters reserve statusbar and home indicator");
            Expect(first.canShowAlerts && first.foreground && first.statusBarDisabled && first.level==1 &&
                [first.persistenceIdentifier isEqualToString:@"guest-container"],@"initial geometry preserves LC lifecycle and container fields");
        }
        host.frame=CGRectMake(0,0,844,390);host.windowScene.interfaceOrientation=UIInterfaceOrientationLandscapeLeft;
        host.safeAreaInsets=(UIEdgeInsets){0,59,21,59};
        for(NSNumber *hostingAPI in @[@YES,@NO]) {
            scene.usesHostingControllerAPI=hostingAPI.boolValue;
            PresenterReady(scene,NSSelectorFromString(@"setUpAppPresenter"));
            OrbitSettings *first=scene.initialSettings;
            Expect(CGRectEqualToRect(first.frame,CGRectMake(0,0,390,844)) && first.interfaceOrientation==3,
                @"both initial API paths keep landscape orientation with LC portrait-normalized bounds");
            Expect(first.peripheryInsets.left==59 && first.peripheryInsets.right==59 && first.peripheryInsets.bottom==21 &&
                first.safeAreaInsetsPortrait.top==59 && first.safeAreaInsetsPortrait.bottom==59,
                @"both initial API paths preserve landscape cutout and home-indicator insets");
        }
        FBSMutableSceneParameters *outside=[FBSMutableSceneParameters new];
        [outside updateSettingsWithBlock:^(OrbitSettings *settings) {settings.frame=CGRectMake(7,8,222,333);}];
        Expect(CGRectEqualToRect(outside.settings.frame,CGRectMake(7,8,222,333)),@"presenter setup restores scope before unrelated parameter updates");
        Enabled=NO;scene.usesHostingControllerAPI=NO;PresenterReady(scene,NSSelectorFromString(@"setUpAppPresenter"));
        Expect(CGRectEqualToRect(scene.initialSettings.frame,CGRectMake(0,0,320,480)) && scene.initialSettings.safeAreaInsetsPortrait.top==0,
            @"disabled fullscreen preserves LC initial configuration");
        Enabled=YES;scene.delegate=unmanaged;PresenterReady(scene,NSSelectorFromString(@"setUpAppPresenter"));
        Expect(CGRectEqualToRect(scene.initialSettings.frame,CGRectMake(0,0,320,480)),@"unmanaged delegate initial configuration passes through");
        scene.delegate=window;host.frame=CGRectZero;PresenterReady(scene,NSSelectorFromString(@"setUpAppPresenter"));
        Expect(CGRectEqualToRect(scene.initialSettings.frame,CGRectMake(0,0,320,480)) && scene.initialSettings.foreground,
            @"invalid host geometry preserves native initialization without sending invalid override");
        host.frame=CGRectMake(0,0,390,844);host.windowScene.interfaceOrientation=UIInterfaceOrientationPortrait;
        host.safeAreaInsets=(UIEdgeInsets){59,0,34,0};
        scene.throwDuringSetup=YES;
        @try { PresenterReady(scene,NSSelectorFromString(@"setUpAppPresenter")); }
        @catch(NSException *exception) { Expect([exception.name isEqualToString:@"SetupFixture"],@"native setup exceptions remain visible"); }
        scene.throwDuringSetup=NO;
        outside=[FBSMutableSceneParameters new];
        [outside updateSettingsWithBlock:^(OrbitSettings *settings) {settings.frame=CGRectMake(1,2,123,234);}];
        Expect(CGRectEqualToRect(outside.settings.frame,CGRectMake(1,2,123,234)),@"exception unwinding restores the initial scene scope");
        fprintf(stdout,"Multitask scene geometry: %lu assertions, %lu failures\n",(unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
