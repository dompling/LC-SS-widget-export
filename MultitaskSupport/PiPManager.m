//
//  PiPManager.m
//  LiveContainer
//
//  Created by s s on 2025/6/3.
//
#include "PiPManager.h"
#include <math.h>
#include "AppSceneViewController.h"
#include "DecoratedAppSceneViewController.h"
#include "../LiveContainer/utils.h"

API_AVAILABLE(ios(16.0))
@interface PiPManager()
@property(nonatomic, strong) UIView *pipVideoCallContentView;
@property(nonatomic, strong) AVPictureInPictureVideoCallViewController *pipVideoCallViewController;
@property(nonatomic, strong) AVPictureInPictureController *pipController;
@property(nonatomic) AppSceneViewController* displayingVC;
@property(nonatomic) BOOL observingPiPBounds;
@end


@implementation PiPManager
API_AVAILABLE(ios(16.0))
static PiPManager* sharedInstance = nil;

+ (instancetype)shared {
    if(!sharedInstance)
        sharedInstance = [[self alloc] init];
    return sharedInstance;
}

- (DecoratedAppSceneViewController *)displayingDecoratedVC {
    return (id)self.displayingVC.delegate;
}

- (BOOL)isPiP {
    return self.pipController.isPictureInPictureActive;
}

- (BOOL)isPiPWithVC:(AppSceneViewController*)vc {
    return self.pipController.isPictureInPictureActive && self.displayingVC == vc;
}

- (BOOL)isPiPWithDecoratedVC:(UIViewController*)vc {
    return self.pipController.isPictureInPictureActive && self.displayingDecoratedVC == vc;
}

- (instancetype)init {
    NSError* error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    [[AVAudioSession sharedInstance] setActive:YES withOptions:1 error:&error];
    return self;
}

- (void)startPiPWithVC:(AppSceneViewController*)vc {
    if(!vc || !vc.isAppRunning || !vc.contentView || !vc.view.window ||
       !isfinite(vc.view.bounds.size.width) || !isfinite(vc.view.bounds.size.height) ||
       vc.view.bounds.size.width<=0 || vc.view.bounds.size.height<=0) {
        NSLog(@"[LC-PiP] rejected: scene has no live render surface");
        return;
    }
    [self.pipController stopPictureInPicture];
    if(self.displayingVC) {
        [self.displayingDecoratedVC unminimizeWindowPiP];
        [self pictureInPictureControllerDidStopPictureInPicture:self.pipController];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([self.pipController isPictureInPictureActive] * 0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if(!vc.isAppRunning || !vc.contentView || !vc.view.window) return;
        self.displayingVC = vc;
        self.pipVideoCallViewController = [AVPictureInPictureVideoCallViewController new];
        self.pipVideoCallViewController.preferredContentSize = vc.view.bounds.size;
        if(vc.usesHostingControllerAPI) {
            // AVKit's new view may still be CGRectZero before its first layout.
            self.pipVideoCallContentView = [[UIView alloc] initWithFrame:(CGRect){CGPointZero,vc.view.bounds.size}];
            //self.pipVideoCallContentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            self.pipVideoCallContentView.layer.anchorPoint = CGPointMake(0, 0);
            self.pipVideoCallContentView.layer.position = CGPointMake(0, 0);
            [self.pipVideoCallViewController.view addSubview:self.pipVideoCallContentView];
        } else {
            self.pipVideoCallContentView = vc.contentView;
        }
        AVPictureInPictureControllerContentSource* contentSource =  [[AVPictureInPictureControllerContentSource alloc] initWithActiveVideoCallSourceView:vc.view contentViewController:self.pipVideoCallViewController];
        self.pipController = [[AVPictureInPictureController alloc] initWithContentSource:contentSource];
        self.pipController.canStartPictureInPictureAutomaticallyFromInline = YES;
        self.pipController.delegate = self;
        [self.pipController setValue:@1 forKey:@"controlsStyle"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.pipController startPictureInPicture];
        });
    });

}

- (void)stopPiP {
    [self.pipController stopPictureInPicture];
}

// PIP delegate
- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    CGSize sourceSize=self.displayingVC.view.bounds.size;
    if(!self.displayingVC.contentView || !isfinite(sourceSize.width) ||
       !isfinite(sourceSize.height) || sourceSize.width<=0 || sourceSize.height<=0) {
        NSLog(@"[LC-PiP] willStart rejected: no drawable guest content");
        [pictureInPictureController stopPictureInPicture];
        return;
    }
    if(self.observingPiPBounds) {
        [self.pipVideoCallViewController.view.layer removeObserver:self forKeyPath:@"bounds"];
        self.observingPiPBounds=NO;
    }
    if(self.displayingVC.usesHostingControllerAPI) {
        self.pipVideoCallContentView.frame = CGRectMake(0, 0, self.displayingVC.view.bounds.size.width, self.displayingVC.view.bounds.size.height);
        self.pipVideoCallViewController.additionalSafeAreaInsets = self.displayingVC.view.safeAreaInsets;
        [self.pipVideoCallContentView addSubview:self.displayingVC.contentView];
    } else {
        self.displayingVC.contentView.frame = CGRectMake(0, 0, self.displayingVC.view.bounds.size.width, self.displayingVC.view.bounds.size.height);
    }
    [self.pipVideoCallViewController.view addSubview:self.pipVideoCallContentView];
    [self.pipVideoCallViewController.view layoutIfNeeded];
    NSLog(@"[LC-PiP] mounted guest: source=%@ content=%@ pip=%@",
          NSStringFromCGRect(self.displayingVC.view.bounds),
          NSStringFromCGRect(self.displayingVC.contentView.bounds),
          NSStringFromCGRect(self.pipVideoCallViewController.view.bounds));
    [self.pipVideoCallViewController.view.layer addObserver:self
                                forKeyPath:@"bounds"
                                   options:NSKeyValueObservingOptionNew
                                   context:NULL];
    self.observingPiPBounds=YES;
    [self.displayingDecoratedVC minimizeWindowPiP];
    self.pipVideoCallViewController.preferredContentSize = self.displayingVC.view.bounds.size;
    [self.displayingVC setBackgroundNotificationEnabled:false];
    self.displayingVC.shouldIgnoreSceneUpdates = YES;
}



- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    
}

- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    if(self.observingPiPBounds) {
        [self.pipVideoCallViewController.view.layer removeObserver:self forKeyPath:@"bounds"];
        self.observingPiPBounds=NO;
    }
    self.displayingVC.shouldIgnoreSceneUpdates = NO;
    [self.displayingDecoratedVC unminimizeWindowPiP];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    if(self.observingPiPBounds) {
        [self.pipVideoCallViewController.view.layer removeObserver:self forKeyPath:@"bounds"];
        self.observingPiPBounds=NO;
    }
    [self.displayingVC.view insertSubview:self.displayingVC.contentView atIndex:0];
    [self.displayingVC setBackgroundNotificationEnabled:true];
    // resize if needed (eg orientation differs)
    [self.displayingDecoratedVC updateVerticalConstraints];
    
    self.pipVideoCallContentView.transform = CGAffineTransformIdentity;
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCAutoEndPiP"]) {
        self.pipController = nil;
        self.pipVideoCallViewController = nil;
    }
    // FIXME: HostingController path causes a tiny flicker during transition to and from PiP.
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
    NSLog(@"%@", error.description);
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(NSObject*)object change:(NSDictionary<NSString *,id> *) change context:(void *) context {
    if(![keyPath isEqualToString:@"bounds"] || object!=self.pipVideoCallViewController.view.layer) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    CGRect rect = [change[@"new"] CGRectValue];
    CGSize contentSize=self.displayingVC.contentView.bounds.size;
    CGFloat scale=self.displayingVC.usesHostingControllerAPI ? self.displayingVC.scaleRatio : 1;
    // Never assign NaN/Inf to the hosted scene's transform when AVKit lays
    // out its PiP surface at zero size during start/restore transitions.
    if(!isfinite(rect.size.width) || !isfinite(rect.size.height) ||
       !isfinite(contentSize.width) || !isfinite(contentSize.height) ||
       !isfinite(scale) || rect.size.width<=0 || rect.size.height<=0 ||
       contentSize.width<=0 || contentSize.height<=0 || scale<=0) return;
    CGFloat sx=rect.size.width/contentSize.width/scale;
    CGFloat sy=rect.size.height/contentSize.height/scale;
    if(!isfinite(sx) || !isfinite(sy) || sx<=0 || sy<=0) return;
    self.pipVideoCallContentView.transform=CGAffineTransformMakeScale(sx,sy);
}

@end
