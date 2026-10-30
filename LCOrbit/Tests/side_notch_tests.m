#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

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
static inline CGFloat Clamp(CGFloat x,CGFloat lo,CGFloat hi) { return fmax(lo,fmin(hi,x)); }
static CGFloat geometryScale=1;
static CGFloat FMOrbScale(void) { return geometryScale; }
static NSMutableDictionary *stylePreferences;
static CGFloat FloatPref(NSString *key,CGFloat fallback) { return stylePreferences[key]?[stylePreferences[key] doubleValue]:fallback; }
#include "side-notch.inc"
static int passed,failed;
static void Expect(BOOL condition,const char *message) {
    if(condition) passed++; else { failed++; fprintf(stderr,"FAIL: %s\n",message); }
}
int main(void) { @autoreleasepool {
    stylePreferences=[NSMutableDictionary dictionary];
    for(NSDictionary *option in FMOrbStyleOptions()) {
        NSString *key=option[@"key"];
        Expect(FMOrbStyleValue(key)==[option[@"default"] doubleValue],"style setting preserves default");
        stylePreferences[key]=@(-1000);
        Expect(FMOrbStyleValue(key)==[option[@"min"] doubleValue],"style setting clamps lower limit");
        stylePreferences[key]=@(1000);
        Expect(FMOrbStyleValue(key)==[option[@"max"] doubleValue],"style setting clamps upper limit");
        [stylePreferences removeObjectForKey:key];
    }

    // The exposed outline must follow the visible body's circular caps,
    // regardless of the edge gap or any independent size setting.
    BOOL capsAligned=YES;
    for(NSNumber *scale in @[@.7,@1,@1.9])
    for(NSNumber *bodyWidth in @[@8,@12,@20])
    for(NSNumber *bodyHeight in @[@36,@52,@80])
    for(NSNumber *gap in @[@0,@2,@8])
    for(NSNumber *extension in @[@8,@25,@48]) {
        geometryScale=scale.doubleValue;
        stylePreferences[@"orbEdgeGap"]=gap;stylePreferences[@"orbExtension"]=extension;
        CGFloat bw=bodyWidth.doubleValue*geometryScale,bh=bodyHeight.doubleValue*geometryScale;
        CGFloat top=extension.doubleValue*geometryScale,w=bw+gap.doubleValue*geometryScale,h=bh+2*top;
        CGFloat radius=MIN(bw,bh)*.5;
        UIBezierPath *fill=FMOrbBodyPath(CGRectMake(0,0,bw,bh));
        for(NSNumber *left in @[@NO,@YES]) {
            UIBezierPath *outline=FMSideNotchPath(CGRectMake(0,0,w,h),left.boolValue,YES,YES);
            for(CGFloat fraction=.1;fraction<1;fraction+=.1) {
                CGFloat dy=radius*(1-fraction);
                CGFloat edge=radius-sqrt(radius*radius-dy*dy);
                for(NSNumber *bottom in @[@NO,@YES]) {
                    CGFloat y=bottom.boolValue?h-top-radius*fraction:top+radius*fraction;
                    CGFloat inside=edge+.015*geometryScale,outside=edge-.015*geometryScale;
                    capsAligned &= CGPathContainsPoint(fill.CGPath,NULL,CGPointMake(inside,y-top),NO) &&
                        !CGPathContainsPoint(fill.CGPath,NULL,CGPointMake(outside,y-top),NO);
                    if(left.boolValue) {inside=w-inside;outside=w-outside;}
                    capsAligned &= CGPathContainsPoint(outline.CGPath,NULL,CGPointMake(inside,y),NO) &&
                        !CGPathContainsPoint(outline.CGPath,NULL,CGPointMake(outside,y),NO);
                }
            }
        }
    }
    Expect(capsAligned,"body fill and exposed glass cap must align across size, gap, extension and side settings");
    geometryScale=1;[stylePreferences removeAllObjects];
    for(NSNumber *scale in @[@.7,@1,@1.9]) {
        CGFloat w=16*scale.doubleValue,h=64*scale.doubleValue;
        UIBezierPath *tab=FMSideNotchPath(CGRectMake(0,0,w,h),NO,YES,YES);
        Expect(!CGPathContainsPoint(tab.CGPath,NULL,CGPointMake(w*.12,h*.10),NO),"collapsed upper flare must remain visibly inset from inner body");
        Expect(!CGPathContainsPoint(tab.CGPath,NULL,CGPointMake(w*.12,h*.90),NO),"collapsed lower flare must remain visibly inset from inner body");
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
    for(NSNumber *left in @[@YES,@NO]) {
        CGRect bounds=CGRectMake(0,0,16,64);
        Expect(CGPathEqualToPath(FMDropletPath(bounds,left.boolValue,0,52).CGPath,
                                FMSideNotchPath(bounds,left.boolValue,YES,YES).CGPath),
               "pull starts at the exact docked outline without a shape jump");
        for(CGFloat pull=1;pull<=52;pull+=1) {
            CGFloat w=16+pull*.4;
            UIBezierPath *drop=FMDropletPath(CGRectMake(0,0,w,64),left.boolValue,pull,52);
            CGFloat edge=left.boolValue?.001:w-.001;
            Expect(CGPathContainsPoint(drop.CGPath,NULL,CGPointMake(edge,32),NO),
                   "droplet remains attached to the screen throughout pull");
            CGRect box=CGPathGetPathBoundingBox(drop.CGPath);
            Expect(box.origin.x>=-.01 && box.origin.y>=-.01 &&
                   CGRectGetMaxX(box)<=w+.01 && CGRectGetMaxY(box)<=64.01,
                   "droplet remains inside glass bounds");
        }
    }
    // Repositioning uses the visible body dimensions, not the tall dock backing.
    UIBezierPath *moving=FMOrbDragPath(CGRectMake(0,0,12,52),NO,1);
    UIBezierPath *movingLeft=FMOrbDragPath(CGRectMake(0,0,12,52),YES,1);
    Expect(CGRectEqualToRect(CGPathGetPathBoundingBox(moving.CGPath),CGRectMake(0,0,12,52)),
           "moving capsule keeps only the twelve by fifty-two point body");
    for(CGFloat x=.5;x<12;x+=1) for(CGFloat y=.5;y<52;y+=1)
        Expect(CGPathContainsPoint(moving.CGPath,NULL,CGPointMake(x,y),NO)==
               CGPathContainsPoint(movingLeft.CGPath,NULL,CGPointMake(x,y),NO),
               "moving capsule stays identical when crossing the screen midpoint");
    // Free drag must be a true round-ended capsule without the previous
    // triangular shoulders. It must look the SAME when crossing the midline.
    for(NSNumber *scale in @[@.7,@1,@1.9]) {
        CGFloat w=16*scale.doubleValue,h=64*scale.doubleValue;
        CGRect b=CGRectMake(0,0,w,h);
        UIBezierPath *neutral=FMOrbDragPath(b,NO,1);
        UIBezierPath *neutralLeft=FMOrbDragPath(b,YES,1);
        Expect(CGPathContainsPoint(neutral.CGPath,NULL,CGPointMake(w*.5,.10),NO),"capsule upper arc is round, reaching the true top");
        Expect(CGPathContainsPoint(neutral.CGPath,NULL,CGPointMake(w*.5,h-.10),NO),"capsule lower arc is round, reaching the true bottom");
        Expect(!CGPathContainsPoint(neutral.CGPath,NULL,CGPointMake(w*.04,.04),NO),"capsule upper outer corner is clipped");
        Expect(!CGPathContainsPoint(neutral.CGPath,NULL,CGPointMake(w*.96,h-.04),NO),"capsule lower outer corner is clipped");
        for(CGFloat x=.25;x<w;x+=.5) for(CGFloat y=.25;y<h;y+=.7) {
            BOOL right=CGPathContainsPoint(neutral.CGPath,NULL,CGPointMake(x,y),NO);
            BOOL left=CGPathContainsPoint(neutralLeft.CGPath,NULL,CGPointMake(x,y),NO);
            Expect(right==left,"changing docking direction must not flip or distort the free capsule");
        }
        // The final interpolated path must exactly match the original docked
        // silhouette so redrawing after the animation cannot produce a jump.
        for(NSNumber *left in @[@YES,@NO]) {
            UIBezierPath *originalPath=FMSideNotchPath(b,left.boolValue,YES,YES);
            UIBezierPath *dockedPath=FMOrbDragPath(b,left.boolValue,0);
            CGPathRef original=originalPath.CGPath,docked=dockedPath.CGPath;
            Expect(CGPathEqualToPath(original,docked),"docked path is byte-for-byte identical to existing side notch");
        }
        for(NSNumber *phase in @[@0,@.25,@.5,@.75,@1]) {
            UIBezierPath *transitionPath=FMOrbDragPath(b,NO,phase.doubleValue);
            CGPathRef transitioning=transitionPath.CGPath;
            CGRect controlBounds=CGPathGetBoundingBox(transitioning);
            // Bezier controls may sit just outside the rendered capsule's
            // upper/lower arc, but the rasterized silhouette must not leak.
            Expect(isfinite(controlBounds.origin.x) && isfinite(controlBounds.origin.y) &&
                   controlBounds.origin.x>=-.01 &&
                   CGRectGetMaxX(controlBounds)<=w+.01 &&
                   controlBounds.origin.y>=-w/6-.01 &&
                   CGRectGetMaxY(controlBounds)<=h+w/6+.01 &&
                   !CGPathContainsPoint(transitioning,NULL,CGPointMake(w*.5,-.4),NO) &&
                   !CGPathContainsPoint(transitioning,NULL,CGPointMake(w*.5,h+.4),NO),
                   "all morph phases stay within rendered bead bounds");
        }
    }
    UIBezierPath *fullDrop=FMDropletPath(CGRectMake(0,0,36.8,64),NO,52,52);
    Expect(!CGPathContainsPoint(fullDrop.CGPath,NULL,CGPointMake(1,20),NO),
           "pulled head must round inward above its center, never a flat trapezoid front");
    Expect(CGPathContainsPoint(fullDrop.CGPath,NULL,CGPointMake(1,32),NO),
           "round head reaches the inward-most tip at its center");
    Expect(CGPathContainsPoint(fullDrop.CGPath,NULL,CGPointMake(36.79,32),NO),
           "liquid pull remains joined at its pointed root");
    Expect(!CGPathContainsPoint(fullDrop.CGPath,NULL,CGPointMake(36.6,30),NO) &&
           !CGPathContainsPoint(fullDrop.CGPath,NULL,CGPointMake(36.6,34),NO),
           "full pull tapers to a sharp root instead of a broad edge");
    // Smaller head and shorter travel preserve the scale of the original tab.
    // Every vertical slice must remain one connected piece of glass.
    for(CGFloat pull=4;pull<=52;pull+=4) {
        CGFloat w=16+pull*.4;
        UIBezierPath *right=FMDropletPath(CGRectMake(0,0,w,64),NO,pull,52);
        UIBezierPath *left=FMDropletPath(CGRectMake(0,0,w,64),YES,pull,52);
        for(CGFloat x=.5;x<w;x+=1) {
            BOOL entered=NO,exited=NO;
            for(CGFloat y=.5;y<64;y+=1) {
                BOOL inside=CGPathContainsPoint(right.CGPath,NULL,CGPointMake(x,y),NO);
                Expect(inside==CGPathContainsPoint(left.CGPath,NULL,CGPointMake(w-x,y),NO),
                       "liquid pull mirrors exactly on either docking edge");
                Expect(!(inside && exited),"liquid pull has no disconnected lobes or holes");
                if(inside) entered=YES;
                else if(entered) exited=YES;
            }
        }
    }
    const char *preview=getenv("FM_GEOMETRY_PREVIEW");
    if(preview) {
        CGContextRef ctx=CGBitmapContextCreate(NULL,960,400,8,0,CGColorSpaceCreateDeviceRGB(),(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGContextSetRGBFillColor(ctx,.035,.04,.055,1); CGContextFillRect(ctx,CGRectMake(0,0,960,400));
        for(int phase=0;phase<4;phase++) {
            CGFloat pull=phase==0?0:phase==1?12:phase==2?32:52;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx,220+phase*240,320); CGContextScaleCTM(ctx,3,-3);
            CGContextSetRGBStrokeColor(ctx,.3,.34,.4,1); CGContextSetLineWidth(ctx,.4);
            CGContextMoveToPoint(ctx,0,-12); CGContextAddLineToPoint(ctx,0,84); CGContextStrokePath(ctx);
            CGContextTranslateCTM(ctx,-16-pull*.4,0);
            UIBezierPath *outline=phase==0?FMSideNotchPath(CGRectMake(0,0,16,64),NO,YES,YES):
                FMDropletPath(CGRectMake(0,0,16+pull*.4,64),NO,pull,52);
            CGContextAddPath(ctx,outline.CGPath); CGContextSetRGBFillColor(ctx,.48,.51,.55,.65);
            CGContextSetRGBStrokeColor(ctx,.85,.88,.94,.8); CGContextSetLineWidth(ctx,.45);
            CGContextDrawPath(ctx,kCGPathFillStroke); CGContextRestoreGState(ctx);
        }
        CGImageRef img=CGBitmapContextCreateImage(ctx);
        NSURL *url=[NSURL fileURLWithPath:@(preview)];
        CGImageDestinationRef dest=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL);
        CGImageDestinationAddImage(dest,img,NULL); CGImageDestinationFinalize(dest);
        CFRelease(dest); CGImageRelease(img); CGContextRelease(ctx);
    }
    printf("Side-notch and capsule morph geometry: %d assertions, %d failures\n",passed+failed,failed);
    return failed?1:0;
}}
