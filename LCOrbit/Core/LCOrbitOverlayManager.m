#import "LCOrbitOverlayManager.h"
#import <math.h>

// Transparent regions must not steal interaction from the active Guest.
@interface LCOrbitPassThroughView : UIView @end
@implementation LCOrbitPassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *target=[super hitTest:point withEvent:event];
    return target==self?nil:target;
}
@end
@interface LCOrbitPassThroughWindow : UIWindow @end
@implementation LCOrbitPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if(!event || event.type==UIEventTypeTouches) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOrbitScreenTouchedNotification" object:nil];
    }
    UIView *target=[super hitTest:point withEvent:event];
    return target==self || target==self.rootViewController.view?nil:target;
}
@end

@interface LCOrbitOverlayViewController : UIViewController
@property(nonatomic,weak) LCOrbitOverlayManager *manager;
@end
@implementation LCOrbitOverlayViewController
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    __weak typeof(self) weakSelf=self;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        [weakSelf.manager updateFrame];
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOrbitOverlayLayoutDidChangeNotification" object:nil];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        [weakSelf.manager updateFrame];
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOrbitOverlayLayoutDidChangeNotification" object:nil];
    }];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.manager updateFrame];
}
@end

@implementation LCOrbitOverlayManager {
    UIWindow *_window;
    NSMutableDictionary<NSString *,UIView *> *_modules;
}
- (instancetype)init {
    if((self=[super init])) _modules=[NSMutableDictionary dictionary];
    return self;
}
- (UIWindow *)window { return _window; }
- (void)clearScene {
    for(UIView *layer in _modules.allValues) [layer removeFromSuperview];
    [_modules removeAllObjects];
    _window.hidden=YES;
    _window.rootViewController=nil;
    _window=nil;
}
- (UIView *)mountModule:(NSString *)identifier inScene:(UIWindowScene *)scene {
    NSAssert(NSThread.isMainThread,@"Overlay UI must be used on the main thread");
    if(!identifier.length || !scene) return nil;
    if(_window && _window.windowScene!=scene) [self clearScene];
    BOOL created=NO;
    if(!_window) {
        CGRect frame=scene.coordinateSpace.bounds;
        if(!isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
           !isfinite(frame.size.width) || !isfinite(frame.size.height) ||
           frame.size.width<=0 || frame.size.height<=0) return nil;
        LCOrbitPassThroughWindow *window=[[LCOrbitPassThroughWindow alloc] initWithWindowScene:scene];
        window.frame=frame;
        window.backgroundColor=UIColor.clearColor;
        window.windowLevel=UIWindowLevelNormal+75;
        LCOrbitOverlayViewController *vc=[LCOrbitOverlayViewController new];
        vc.manager=self;
        vc.view.backgroundColor=UIColor.clearColor;
        window.rootViewController=vc;
        // Publish the reference before the visibility notification can fire.
        _window=window;
        created=YES;
    }
    [self updateFrame];
    UIView *layer=_modules[identifier];
    if(!layer) {
        layer=[[LCOrbitPassThroughView alloc] initWithFrame:_window.rootViewController.view.bounds];
        layer.backgroundColor=UIColor.clearColor;
        layer.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [_window.rootViewController.view addSubview:layer];
        _modules[identifier]=layer;
    }
    // Mount the module before displaying. Never make the overlay the key window.
    if(created) _window.hidden=NO;
    return layer;
}
- (void)updateFrame {
    if(!_window) return;
    CGRect frame=_window.windowScene.coordinateSpace.bounds;
    if(!isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
       !isfinite(frame.size.width) || !isfinite(frame.size.height) ||
       frame.size.width<=0 || frame.size.height<=0) return;
    _window.frame=frame;
    for(UIView *layer in _modules.allValues) layer.frame=_window.rootViewController.view.bounds;
}
- (void)unmountModule:(NSString *)identifier {
    UIView *layer=_modules[identifier];
    [layer removeFromSuperview];
    [_modules removeObjectForKey:identifier];
    if(_modules.count==0) [self clearScene];
}
- (void)setModule:(NSString *)identifier visible:(BOOL)visible {
    _modules[identifier].hidden=!visible;
}
@end
