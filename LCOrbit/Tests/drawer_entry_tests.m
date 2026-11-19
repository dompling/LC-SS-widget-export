#import <Foundation/Foundation.h>
static BOOL Adaptive;
static NSUInteger Scans, Presents, Draws, Refreshes, Depth;
static dispatch_semaphore_t ScanStarted,ScanReleased;
static NSArray *InventoryResult;
static void FMBeginPreferenceSnapshot(void) { Depth++; }
static void FMEndPreferenceSnapshot(void) { Depth--; }
static NSArray *InstalledApps(void) {
    if(NSThread.isMainThread) Scans++;
    if(ScanStarted) {dispatch_semaphore_signal(ScanStarted);dispatch_semaphore_wait(ScanReleased,DISPATCH_TIME_FOREVER);}
    return InventoryResult?:@[@{@"identity":@"new-scan"}];
}
static NSArray *InstalledAppsCached(void) {
    return InventoryResult?:@[@{@"identity":@"cached"}];
}
typedef NSObject UIWindow;
@interface LCOrbitStorage : NSObject
+ (void)beginReadSnapshot:(NSDictionary *)values;
+ (void)endReadSnapshot;
@end
@implementation LCOrbitStorage
+ (void)beginReadSnapshot:(NSDictionary *)values {}
+ (void)endReadSnapshot {}
@end
@interface EntryOrb : NSObject
@property(nonatomic) double alpha;
@end
@implementation EntryOrb @end
@interface FMManager : NSObject {
    BOOL _morphActive;
}
@property(nonatomic) BOOL isOpen,orbFaded;
@property(nonatomic) double orbNormalAlpha;
@property(nonatomic,strong) EntryOrb *orb;
@property(nonatomic,strong) id panel;
@property(nonatomic,copy) NSString *page;
@property(nonatomic,copy) NSArray *apps;
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic) BOOL inventoryRefreshPending;
- (void)toggle;
- (BOOL)usesAdaptiveDrawer;
- (void)presentAdaptiveDrawer;
- (void)refreshInventoryInBackground;
@end
@implementation FMManager
- (BOOL)usesAdaptiveDrawer { return Adaptive; }
- (void)presentAdaptiveDrawer { Presents++;self.isOpen=NO; }
- (void)requestAppsRefresh { Refreshes++; }
- (void)stopDropletPull {}
- (void)endScrubAnimated:(BOOL)animated {}
- (void)cancelOrbFade {}
- (void)loadAppsScroll {}
- (void)persistAppsScroll {}
- (void)rememberCurrentApp {}
- (void)announceDrawerState {}
- (void)scheduleOrbFade {}
- (void)draw { Draws++;if(self.isOpen)self.panel=[NSObject new];else self.panel=nil; }
- (void)morphDrawerOpen:(BOOL)open { if(!open)self.panel=nil; }
#include "entry.inc"
@end
int main(void) {
    @autoreleasepool {
        FMManager *menu=[FMManager new];menu.orb=[EntryOrb new];menu.apps=@[@{@"identity":@"cached"}];
        Adaptive=YES;[menu toggle];
        if(Presents!=1||Draws!=0||Scans!=0||menu.isOpen) {fprintf(stderr,"FAIL: original bead must directly present adaptive deck using cached inventory, without legacy drawer or synchronous scan\n");return 1;}
        Adaptive=NO;Presents=Draws=Scans=Refreshes=0;[menu toggle];
        if(Presents||!menu.isOpen||!menu.panel||Draws!=1||Scans||![menu.apps.firstObject[@"identity"] isEqual:@"cached"]) {fprintf(stderr,"FAIL: legacy drawer must still open immediately using cached inventory\n");return 2;}
        [menu toggle];
        if(menu.isOpen||menu.panel||Presents||Depth) {fprintf(stderr,"FAIL: legacy close and scoped event balance\n");return 3;}
        menu.window=[UIWindow new];InventoryResult=@[@{@"identity":@"background"}];
        ScanStarted=dispatch_semaphore_create(0);ScanReleased=dispatch_semaphore_create(0);
        [menu refreshInventoryInBackground];
        if(dispatch_semaphore_wait(ScanStarted,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)))return 4;
        NSArray *newer=@[@{@"identity":@"user-updated"}];menu.apps=newer;
        dispatch_semaphore_signal(ScanReleased);
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
        while(menu.inventoryRefreshPending && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        if(menu.inventoryRefreshPending || menu.apps!=newer){fprintf(stderr,"FAIL: stale background scan must not overwrite a newer user inventory\n");return 5;}
        [menu refreshInventoryInBackground];
        if(dispatch_semaphore_wait(ScanStarted,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)))return 6;
        dispatch_semaphore_signal(ScanReleased);deadline=[NSDate dateWithTimeIntervalSinceNow:2];
        while(menu.inventoryRefreshPending && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        if(menu.apps!=InventoryResult || Scans){fprintf(stderr,"FAIL: unchanged inventory receives background refresh without main-thread scanning\n");return 7;}
        [menu refreshInventoryInBackground];
        if(dispatch_semaphore_wait(ScanStarted,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)))return 8;
        menu.window=[UIWindow new];menu.apps=newer;dispatch_semaphore_signal(ScanReleased);deadline=[NSDate dateWithTimeIntervalSinceNow:2];
        while(menu.inventoryRefreshPending && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        if(menu.apps!=newer){fprintf(stderr,"FAIL: detached window cannot receive an old inventory result\n");return 9;}
        puts("Drawer entry and background refresh: 6 assertions, 0 failures");
    }
    return 0;
}
