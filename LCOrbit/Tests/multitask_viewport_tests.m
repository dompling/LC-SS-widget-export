#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

typedef NSInteger UIInterfaceOrientation;
enum {
    UIInterfaceOrientationPortrait=1,
    UIInterfaceOrientationLandscapeLeft=3,
    UIInterfaceOrientationLandscapeRight=4
};
typedef struct { CGFloat top,left,bottom,right; } UIEdgeInsets;
static UIEdgeInsets UIEdgeInsetsMake(CGFloat top,CGFloat left,CGFloat bottom,CGFloat right) {
    return (UIEdgeInsets){top,left,bottom,right};
}

static NSMutableDictionary *Preferences;
@interface LCOrbitStorage : NSObject
+ (id)objectForKey:(NSString *)key module:(NSString *)module;
@end
@implementation LCOrbitStorage
+ (id)objectForKey:(NSString *)key module:(NSString *)module {
    return [module isEqual:@"LCFloatingMenu"] ? Preferences[key] : nil;
}
@end

// Geometry functions are extracted independently from production source. The LC
// conversion is not replaced with an alias to the microbead implementation.
#include "viewport.inc"

static NSUInteger Assertions,Failures;
static BOOL SameInsets(UIEdgeInsets a,UIEdgeInsets b) {
    return fabs(a.top-b.top)<0.00001 && fabs(a.left-b.left)<0.00001 &&
        fabs(a.bottom-b.bottom)<0.00001 && fabs(a.right-b.right)<0.00001;
}
static void Expect(BOOL condition,const char *message) {
    Assertions++;
    if(!condition) { Failures++;fprintf(stderr,"FAIL: %s\n",message); }
}
static void ExpectViewport(CGRect safe,CGRect viewport,UIEdgeInsets expected,const char *message) {
    UIEdgeInsets actual={-1,-2,-3,-4};
    Expect(OrbitInsetsInViewport(safe,viewport,&actual),message);
    if(!SameInsets(actual,expected)) {
        fprintf(stderr,"  expected %.0f/%.0f/%.0f/%.0f, got %.0f/%.0f/%.0f/%.0f\n",
            expected.top,expected.left,expected.bottom,expected.right,
            actual.top,actual.left,actual.bottom,actual.right);
    }
    Expect(SameInsets(actual,expected),message);
}
static void ExpectRejected(CGRect safe,CGRect viewport,const char *message) {
    UIEdgeInsets sentinel={-1,-2,-3,-4},actual=sentinel;
    Expect(!OrbitInsetsInViewport(safe,viewport,&actual),message);
    Expect(SameInsets(actual,sentinel),"rejected geometry leaves the output untouched");
}

int main(void) {
    @autoreleasepool {
        CGRect full=CGRectMake(0,0,390,844),safe=CGRectMake(0,59,390,751);
        Preferences=[NSMutableDictionary dictionary];
        for(NSNumber *enabled in @[@YES,@NO]) {
            Preferences[@"guestOwnTopInset.A.app"]=enabled;
            CGRect viewport=GuestViewport(full,(UIEdgeInsets){59,0,34,0},!GuestOwnsTopInset(@"A.app"));
            Expect(CGRectEqualToRect(viewport,enabled.boolValue?CGRectMake(0,59,390,785):full),
                "switch on moves and shrinks viewport; off retains v6 full bounds");
            ExpectViewport(safe,viewport,(UIEdgeInsets){enabled.boolValue?0:59,0,34,0},
                "switch on clears top inset; off retains Guest top safe area");
            Expect(CGRectEqualToRect(GuestViewport(full,(UIEdgeInsets){59,0,34,0},NO),full),
                "both policies preserve full startup bounds before presenter readiness");
        }
        ExpectViewport(safe,full,(UIEdgeInsets){59,0,34,0},
            "a full viewport includes the status bar and home indicator");
        ExpectViewport(safe,CGRectMake(0,59,390,785),(UIEdgeInsets){0,0,34,0},
            "a viewport starting below the status bar has no top inset");
        ExpectViewport(safe,safe,(UIEdgeInsets){0,0,0,0},
            "a viewport wholly inside the safe area has valid zero insets");
        ExpectViewport(CGRectMake(-20,99,390,751),CGRectMake(-20,40,390,844),
            (UIEdgeInsets){59,0,34,0},"translated rectangles retain viewport-local insets");
        ExpectViewport(CGRectMake(11,59,342,751),full,(UIEdgeInsets){59,11,34,37},
            "asymmetric side obstructions stay on their corresponding edges");
        ExpectViewport(CGRectMake(0,118,780,1502),CGRectMake(0,0,780,1688),
            (UIEdgeInsets){118,0,68,0},"geometry converted to doubled local units retains that scale");
        ExpectViewport(CGRectMake(-20,-20,430,884),full,(UIEdgeInsets){0,0,0,0},
            "safe bounds extending beyond the viewport do not create negative insets");
        ExpectViewport(CGRectMake(-10,25,420,790),full,(UIEdgeInsets){25,0,29,0},
            "only the portion of an obstruction intersecting the viewport contributes");

        ExpectRejected(CGRectMake(NAN,59,390,751),full,"non-finite safe bounds are rejected");
        ExpectRejected(safe,CGRectMake(0,0,INFINITY,844),"non-finite viewport bounds are rejected");
        ExpectRejected(safe,CGRectZero,"a zero-sized viewport is rejected");
        ExpectRejected(CGRectMake(0,59,390,0),full,"an empty safe region is rejected");
        ExpectRejected(CGRectMake(500,59,390,751),full,"a disjoint safe region is rejected");
        ExpectRejected(CGRectMake(390,59,-390,751),full,"an inverted safe rectangle is rejected");

        UIEdgeInsets cases[]={{0,59,21,59},{0,11,21,37},{0,0,21,37},{0,0,0,0}};
        UIInterfaceOrientation orientations[]={UIInterfaceOrientationPortrait,
            UIInterfaceOrientationLandscapeLeft,UIInterfaceOrientationLandscapeRight};
        for(NSUInteger c=0;c<sizeof(cases)/sizeof(cases[0]);c++) {
            for(NSUInteger o=0;o<sizeof(orientations)/sizeof(orientations[0]);o++) {
                Expect(SameInsets(PortraitInsets(cases[c],orientations[o]),
                    LCUIEdgeInsetsRotateToOrientation(cases[c],orientations[o])),
                    "microbead and independently extracted LC orientation mappings agree");
            }
        }
        UIEdgeInsets left=PortraitInsets((UIEdgeInsets){0,11,21,37},UIInterfaceOrientationLandscapeLeft);
        UIEdgeInsets right=PortraitInsets((UIEdgeInsets){0,11,21,37},UIInterfaceOrientationLandscapeRight);
        Expect(left.top==11 && left.bottom==37,"left landscape uses LC's asymmetric portrait convention");
        Expect(right.top==37 && right.bottom==11,"right landscape uses LC's asymmetric portrait convention");
        fprintf(stdout,"Multitask viewport geometry: %lu assertions, %lu failures\n",
            (unsigned long)Assertions,(unsigned long)Failures);
        return Failures?1:0;
    }
}
