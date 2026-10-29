// Runs the production restore hook and LC's geometry methods. UIKit's view,
// constraint and animation boundaries are represented by small geometry objects.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

typedef struct { CGFloat top,left,bottom,right; } UIEdgeInsets;
static const UIEdgeInsets UIEdgeInsetsZero={0,0,0,0};
static CGRect UIEdgeInsetsInsetRect(CGRect rect,UIEdgeInsets insets) {
    return CGRectMake(rect.origin.x+insets.left,rect.origin.y+insets.top,
        rect.size.width-insets.left-insets.right,rect.size.height-insets.top-insets.bottom);
}
static BOOL UIInterfaceOrientationIsLandscape(NSInteger orientation) { return orientation==3 || orientation==4; }
@interface NSValue (OrbitGeometry)
- (CGRect)CGRectValue;
- (CGAffineTransform)CGAffineTransformValue;
@end
@implementation NSValue (OrbitGeometry)
- (CGRect)CGRectValue { CGRect value;[self getValue:&value size:sizeof(value)];return value; }
- (CGAffineTransform)CGAffineTransformValue { CGAffineTransform value;[self getValue:&value size:sizeof(value)];return value; }
@end
@interface OrbitView : NSObject
@property CGRect frame;
@property NSUInteger autoresizingMask;
@property(nonatomic,strong) CALayer *layer;
@property BOOL hidden;
@property CGFloat alpha;
@property CGAffineTransform transform;
@property(nonatomic,strong) OrbitView *window;
@property UIEdgeInsets safeAreaInsets;
@property CGPoint center;
@property(readonly) CGRect bounds;
- (void)layoutIfNeeded;
+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))animations;
@end
@implementation OrbitView
- (instancetype)init { if((self=[super init])) {_layer=[CALayer layer];_alpha=1;}return self; }
- (CGPoint)center {return CGPointMake(CGRectGetMidX(self.frame),CGRectGetMidY(self.frame));}
- (CGRect)bounds {return (CGRect){CGPointZero,self.frame.size};}
- (void)layoutIfNeeded {}
- (void)setCenter:(CGPoint)center {CGRect f=self.frame;f.origin=CGPointMake(center.x-f.size.width/2,center.y-f.size.height/2);self.frame=f;}
+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))animations {animations();}
@end
@compatibility_alias UIView OrbitView;
@compatibility_alias UINavigationBar OrbitView;

@interface OrbitSettings : NSObject <NSCopying,NSMutableCopying>
@property NSInteger userInterfaceStyle,interfaceOrientation,deviceOrientation;
@property BOOL foreground;
@property CGRect frame;
@property UIEdgeInsets peripheryInsets,safeAreaInsetsPortrait;
@end
@implementation OrbitSettings
- (id)copyWithZone:(NSZone *)zone {return self;}
- (id)mutableCopyWithZone:(NSZone *)zone {return self;}
@end
@compatibility_alias UIMutableApplicationSceneSettings OrbitSettings;
@interface OrbitScene : NSObject
@property(nonatomic,strong) UIView *view,*contentView;
@property CGFloat scaleRatio;
@property BOOL shouldIgnoreSceneUpdates;
@property(nonatomic,strong) OrbitScene *presenter,*scene;
@property(nonatomic,strong) OrbitSettings *settings;
- (void)updateSettingsWithBlock:(void (^)(OrbitSettings *))block;
@end
@implementation OrbitScene
- (instancetype)init {
    if((self=[super init])) {_view=[UIView new];_contentView=[UIView new];_settings=[OrbitSettings new];_settings.interfaceOrientation=1;}
    return self;
}
- (void)updateSettingsWithBlock:(void (^)(OrbitSettings *))block {block(self.settings);self.contentView.frame=self.settings.frame;}
@end
@compatibility_alias AppSceneViewController OrbitScene;

@interface OrbitWindow : NSObject
@property(nonatomic,strong) UIView *view,*resizeHandle;
@property(nonatomic,strong) UINavigationBar *navigationBar;
@property(nonatomic,strong) OrbitScene *appSceneVC;
@property(nonatomic,strong) NSArray *activatedVerticalConstraints;
@property BOOL isMaximized;
@property CGFloat scaleRatio;
@property CGRect originalFrame;
- (void)updateOriginalFrame;
- (void)updateWindowedFrameWithSettings:(OrbitSettings *)settings;
- (void)updateMaximizedFrameWithSettings:(OrbitSettings *)settings;
- (void)appSceneVCWillActivateScene:(OrbitScene *)scene;
- (void)appSceneVC:(OrbitScene *)vc didUpdateFromSettings:(OrbitSettings *)settings transitionContext:(id)context lifecycleActionType:(uint32_t)action;
@end
@compatibility_alias UIViewController OrbitWindow;
@interface OrbitConstraint : NSObject
+ (void)deactivateConstraints:(NSArray *)constraints;
@end
@implementation OrbitConstraint
+ (void)deactivateConstraints:(NSArray *)constraints {}
@end
@compatibility_alias NSLayoutConstraint OrbitConstraint;

static char SnapshotKey,ConstraintsKey;
static IMP OriginalVertical;
static IMP OriginalPiPStopped;
static NSUInteger NativePiPStops,PiPRestores;
static OrbitWindow *PiPRestoreWindow;
@interface LCOrbitMultitask : NSObject
+ (void)refreshPresentation;
@end
static OrbitScene *SceneController(UIViewController *window) {return window.appSceneVC;}
static BOOL OrbitPiPProtectedWindow(UIViewController *window) {return window.appSceneVC.shouldIgnoreSceneUpdates;}
static void PositionHostingView(UIViewController *window,BOOL fullscreen) {}
#include "restore.inc"
#include "pip-stopped.inc"
@implementation LCOrbitMultitask
+ (void)refreshPresentation {PiPRestores++;RestoreAppearance(PiPRestoreWindow);}
@end
static void NativePiPStopped(id object,SEL selector,id controller) {
    NativePiPStops++;
    PiPRestoreWindow.appSceneVC.shouldIgnoreSceneUpdates=NO;
}

@implementation OrbitWindow
// These three methods are extracted verbatim from LC's source by the runner.
#include "native.inc"
- (void)updateMaximizedFrameWithSettings:(OrbitSettings *)settings {}
@end
static void NativeVertical(id object,SEL selector) {
    OrbitWindow *window=object;
    // Native constraints reserve the 44pt bar. They do not resize the remote
    // content until the native scene-settings path is requested.
    window.appSceneVC.view.frame=CGRectMake(0,44,window.view.frame.size.width,window.view.frame.size.height-44);
    window.navigationBar.frame=CGRectMake(0,0,window.view.frame.size.width,44);
}
static NSValue *BoxRect(CGRect value) {return [NSValue valueWithBytes:&value objCType:@encode(CGRect)];}
static NSValue *Transform(CGAffineTransform value) {return [NSValue valueWithBytes:&value objCType:@encode(CGAffineTransform)];}
int main(void) {
    @autoreleasepool {
        OrbitWindow *window=[OrbitWindow new];window.view=[UIView new];window.resizeHandle=[UIView new];window.navigationBar=[UIView new];
        window.appSceneVC=[OrbitScene new];window.appSceneVC.presenter=[OrbitScene new];window.appSceneVC.presenter.scene=[OrbitScene new];
        window.view.window=[UIView new];window.view.window.frame=CGRectMake(0,0,390,844);
        window.view.frame=CGRectMake(0,0,390,844);window.isMaximized=YES;window.scaleRatio=1;
        window.appSceneVC.contentView.frame=CGRectMake(0,0,390,844);
        NSDictionary *snapshot=@{@"frame":BoxRect(CGRectMake(35,100,320,524)),@"autoresizing":@0,@"radius":@10,@"border":@1,
            @"hidden":@NO,@"maximized":@NO,@"scale":@1,@"barHidden":@NO,@"barAlpha":@1,@"handleHidden":@NO,@"handleAlpha":@1,
            @"contentTransform":Transform(CGAffineTransformIdentity),@"contentSublayer":[NSValue valueWithCATransform3D:CATransform3DIdentity]};
        objc_setAssociatedObject(window,&SnapshotKey,snapshot,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        OriginalVertical=(IMP)NativeVertical;
        unsigned failures=0,assertions=0;
#define EXPECT(condition,message) do {assertions++;if(!(condition)){failures++;fprintf(stderr,"FAIL: %s\n",message);}}while(0)
        window.appSceneVC.shouldIgnoreSceneUpdates=YES;
        window.appSceneVC.scaleRatio=.5;
        RestoreAppearance(window);
        EXPECT(CGRectEqualToRect(window.view.frame,CGRectMake(0,0,390,844)),"active PiP defers decorated-window geometry restoration");
        EXPECT(window.appSceneVC.scaleRatio==.5,"active PiP content scale is not overwritten");
        EXPECT(objc_getAssociatedObject(window,&SnapshotKey)!=nil,"active PiP retains snapshot for later restoration");
        PiPRestoreWindow=window;OriginalPiPStopped=(IMP)NativePiPStopped;
        PiPStopped(nil,NSSelectorFromString(@"pictureInPictureControllerDidStopPictureInPicture:"),nil);
        EXPECT(NativePiPStops==1 && PiPRestores==0,"native PiP callback completes before deferred presentation restoration");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        EXPECT(PiPRestores==1 && objc_getAssociatedObject(window,&SnapshotKey)==nil,"ending manual PiP completes the retained snapshot restoration");
        EXPECT(CGSizeEqualToSize(window.originalFrame.size,CGSizeMake(320,524)),"disable initializes LC's saved window dimensions");
        EXPECT(fabs(window.originalFrame.origin.x-35.0/390)<0.00001 && fabs(window.originalFrame.origin.y-100.0/844)<0.00001,"disable restores normalized window position for rotation");
        EXPECT(CGSizeEqualToSize(window.appSceneVC.contentView.frame.size,CGSizeMake(320,480)),"disable resizes remote content after restoring native control bar");
        // The next LC scene update must retain useful dimensions rather than
        // deriving a zero-size frame from an uninitialized originalFrame.
        [window appSceneVC:window.appSceneVC didUpdateFromSettings:window.appSceneVC.settings transitionContext:nil lifecycleActionType:0];
        EXPECT(CGSizeEqualToSize(window.view.frame.size,CGSizeMake(320,524)),"later native scene updates keep the restored window visible");
        fprintf(stdout,"Multitask restore geometry: %u assertions, %u failures\n",assertions,failures);
        return failures?1:0;
    }
}
