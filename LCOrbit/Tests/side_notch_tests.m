#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Run the production UIKit path builder on macOS using its CoreGraphics operations.
@interface UIBezierPath : NSObject
@property(nonatomic,readonly) CGPathRef CGPath;
+ (instancetype)bezierPath;
- (void)moveToPoint:(CGPoint)p;
- (void)addLineToPoint:(CGPoint)p;
- (void)addQuadCurveToPoint:(CGPoint)p controlPoint:(CGPoint)c;
- (void)addCurveToPoint:(CGPoint)p controlPoint1:(CGPoint)a controlPoint2:(CGPoint)b;
- (void)closePath;
- (void)applyTransform:(CGAffineTransform)t;
@end
@implementation UIBezierPath { CGMutablePathRef _path; }
+ (instancetype)bezierPath { return [self new]; }
- (instancetype)init { if((self=[super init])) _path=CGPathCreateMutable(); return self; }
- (void)dealloc { CGPathRelease(_path); }
- (CGPathRef)CGPath { return _path; }
- (void)moveToPoint:(CGPoint)p { CGPathMoveToPoint(_path,NULL,p.x,p.y); }
- (void)addLineToPoint:(CGPoint)p { CGPathAddLineToPoint(_path,NULL,p.x,p.y); }
- (void)addQuadCurveToPoint:(CGPoint)p controlPoint:(CGPoint)c { CGPathAddQuadCurveToPoint(_path,NULL,c.x,c.y,p.x,p.y); }
- (void)addCurveToPoint:(CGPoint)p controlPoint1:(CGPoint)a controlPoint2:(CGPoint)b { CGPathAddCurveToPoint(_path,NULL,a.x,a.y,b.x,b.y,p.x,p.y); }
- (void)closePath { CGPathCloseSubpath(_path); }
- (void)applyTransform:(CGAffineTransform)t {
    CGMutablePathRef next=CGPathCreateMutableCopyByTransformingPath(_path,&t);
    CGPathRelease(_path); _path=next;
}
@end
#include "side-notch.inc"
static int passed,failed;
static void Expect(BOOL condition,const char *message) {
    if(condition) passed++; else { failed++; fprintf(stderr,"FAIL: %s\n",message); }
}
int main(void) { @autoreleasepool {
    for(NSNumber *scale in @[@.7,@1,@1.9]) {
        CGFloat w=16*scale.doubleValue,h=64*scale.doubleValue;
        UIBezierPath *tab=FMSideNotchPath(CGRectMake(0,0,w,h),NO,YES,YES);
        Expect(!CGPathContainsPoint(tab.CGPath,NULL,CGPointMake(w*.12,h*.20),NO),"collapsed upper flare must remain visibly inset from inner body");
        Expect(!CGPathContainsPoint(tab.CGPath,NULL,CGPointMake(w*.12,h*.80),NO),"collapsed lower flare must remain visibly inset from inner body");
    }
    for(NSNumber *width in @[@12,@76,@310]) {
        CGFloat w=width.doubleValue,h=w==12?52:360;
        for(NSNumber *compact in @[@YES,@NO]) {
            UIBezierPath *right=FMSideNotchPath(CGRectMake(0,0,w,h),NO,compact.boolValue,NO);
            UIBezierPath *left=FMSideNotchPath(CGRectMake(0,0,w,h),YES,compact.boolValue,NO);
            Expect(CGRectEqualToRect(CGPathGetBoundingBox(right.CGPath),CGRectMake(0,0,w,h)),"notch reaches full screen-edge attachment bounds");
            Expect(!CGPathContainsPoint(right.CGPath,NULL,CGPointMake(w*.5,1),NO),"upper shoulder curves toward docking edge, not a flat capsule top");
            Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(w-.001,4),NO),"upper docking edge stays attached");
            Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(w-.001,h-4),NO),"lower docking edge stays attached");
            Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(1,h*.5),NO),"inner body remains wide enough for content");
            for(CGFloat x=.5;x<w;x+=3) for(CGFloat y=.5;y<h;y+=7)
                Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(x,y),NO)==
                       CGPathContainsPoint(left.CGPath,NULL,CGPointMake(w-x,y),NO),"left and right outlines mirror exactly");
        }
    }
    printf("Side-notch geometry: %d assertions, %d failures\n",passed+failed,failed);
    return failed?1:0;
}}
