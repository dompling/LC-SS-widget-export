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
// Flatten a path into rows of numbers so two outlines can be compared segment
// by segment. Zero-length lines are dropped: the bead and the drawer share one
// nine-segment form, and the bead's two straight runs have no length.
static NSArray<NSArray<NSNumber *> *> *PathRows(CGPathRef path) {
    NSMutableArray<NSArray<NSNumber *> *> *rows=[NSMutableArray array];
    __block CGPoint current=CGPointZero;
    CGPathApplyWithBlock(path,^(const CGPathElement *element) {
        switch(element->type) {
            case kCGPathElementMoveToPoint:
                current=element->points[0];
                [rows addObject:@[@0,@(current.x),@(current.y)]];
                break;
            case kCGPathElementAddLineToPoint: {
                CGPoint to=element->points[0];
                if(fabs(to.x-current.x)>1e-9 || fabs(to.y-current.y)>1e-9)
                    [rows addObject:@[@1,@(to.x),@(to.y)]];
                current=to;
                break;
            }
            case kCGPathElementAddCurveToPoint:
                [rows addObject:@[@3,@(element->points[0].x),@(element->points[0].y),
                                  @(element->points[1].x),@(element->points[1].y),
                                  @(element->points[2].x),@(element->points[2].y)]];
                current=element->points[2];
                break;
            case kCGPathElementCloseSubpath:
                [rows addObject:@[@4]];
                break;
            default:
                [rows addObject:@[@9]];
                break;
        }
    });
    return rows;
}
static BOOL RowsMatch(NSArray<NSArray<NSNumber *> *> *a,NSArray<NSArray<NSNumber *> *> *b,CGFloat tolerance) {
    if(a.count!=b.count) return NO;
    for(NSUInteger i=0;i<a.count;i++) {
        if(a[i].count!=b[i].count) return NO;
        for(NSUInteger k=0;k<a[i].count;k++)
            if(fabs(a[i][k].doubleValue-b[i][k].doubleValue)>tolerance) return NO;
    }
    return YES;
}
static BOOL ParamsMatch(FMNotchParams a,FMNotchParams b,CGFloat tolerance) {
    const CGFloat *x=(const CGFloat *)&a,*y=(const CGFloat *)&b;
    for(size_t i=0;i<sizeof(FMNotchParams)/sizeof(CGFloat);i++)
        if(!isfinite(x[i]) || fabs(x[i]-y[i])>tolerance) return NO;
    return YES;
}
// Enclosed area by the shoelace formula, flattening each cubic into 32 chords.
static CGFloat PathArea(CGPathRef path) {
    __block CGPoint start=CGPointZero,current=CGPointZero;
    __block CGFloat twice=0;
    void (^edge)(CGPoint)=^(CGPoint to) { twice+=current.x*to.y-to.x*current.y; current=to; };
    CGPathApplyWithBlock(path,^(const CGPathElement *element) {
        switch(element->type) {
            case kCGPathElementMoveToPoint:
                start=current=element->points[0];
                break;
            case kCGPathElementAddLineToPoint:
                edge(element->points[0]);
                break;
            case kCGPathElementAddCurveToPoint: {
                CGPoint p0=current,c1=element->points[0],c2=element->points[1],p1=element->points[2];
                for(int i=1;i<=32;i++) {
                    CGFloat u=i/32.,a=(1-u)*(1-u)*(1-u),b=3*(1-u)*(1-u)*u,c=3*(1-u)*u*u,d=u*u*u;
                    edge(CGPointMake(a*p0.x+b*c1.x+c*c2.x+d*p1.x,a*p0.y+b*c1.y+c*c2.y+d*p1.y));
                }
                break;
            }
            case kCGPathElementCloseSubpath:
                edge(start);
                break;
            default:
                break;
        }
    });
    return fabs(twice)*.5;
}
// Production bead outline moved into the drawer's coordinates: scaled by unit,
// then placed at (left, top).
static NSArray<NSArray<NSNumber *> *> *BeadRows(CGSize size,CGFloat unit,CGFloat left,CGFloat top) {
    UIBezierPath *bead=FMSideNotchPath(CGRectMake(0,0,size.width,size.height),NO,YES,YES);
    CGAffineTransform place=CGAffineTransformMake(unit,0,0,unit,left,top);
    CGPathRef moved=CGPathCreateCopyByTransformingPath(bead.CGPath,&place);
    NSArray *rows=PathRows(moved);
    CGPathRelease(moved);
    return rows;
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

    for(NSDictionary *option in FMMenuStyleOptions()) {
        NSString *key=option[@"key"];
        Expect(FMMenuStyleValue(key)==[option[@"default"] doubleValue],"menu default preserved");
        stylePreferences[key]=@(NAN);
        Expect(FMMenuStyleValue(key)==[option[@"default"] doubleValue],"menu rejects nonfinite preference");
        stylePreferences[key]=@(-1000);
        Expect(FMMenuStyleValue(key)==[option[@"min"] doubleValue],"menu minimum clamp");
        stylePreferences[key]=@(1000);
        Expect(FMMenuStyleValue(key)==[option[@"max"] doubleValue],"menu maximum clamp");
        [stylePreferences removeObjectForKey:key];
    }
    for(NSNumber *ext in @[@12,@28,@44]) for(NSNumber *radius in @[@8,@26,@36])
    for(NSNumber *curve in @[@.2,@.64,@.9]) for(NSNumber *compact in @[@NO,@YES]) {
        stylePreferences[@"menuExtension"]=ext;stylePreferences[@"menuCornerRadius"]=radius;stylePreferences[@"menuCurveSoftness"]=curve;
        CGFloat w=compact.boolValue?76:240,h=320;
        UIBezierPath *right=FMSideNotchPath(CGRectMake(0,0,w,h),NO,compact.boolValue,NO);
        UIBezierPath *left=FMSideNotchPath(CGRectMake(0,0,w,h),YES,compact.boolValue,NO);
        CGRect box=CGPathGetPathBoundingBox(right.CGPath);
        Expect(isfinite(box.size.width) && CGRectContainsRect(CGRectMake(-.01,-.01,w+.02,h+.02),box),"menu extrema stay bounded");
        Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(w*.5,h*.5),NO),"menu center remains filled");
        for(CGFloat x=3;x<w;x+=11) for(CGFloat y=3;y<h;y+=17)
            Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(x,y),NO)==CGPathContainsPoint(left.CGPath,NULL,CGPointMake(w-x,y),NO),"menu shapes mirror at all settings");
    }
    [stylePreferences removeAllObjects];
    Expect(fabs(FMOrbRootCurveFactor()-.40)<.000001,"legacy default root curve preserved");
    stylePreferences[@"orbCurveSoftness"]=@0;CGFloat shallow=FMOrbRootCurveFactor();
    stylePreferences[@"orbCurveSoftness"]=@.85;
    Expect(fabs(shallow-.05)<.000001 && fabs(FMOrbRootCurveFactor()-.95)<.000001,"orb concavity covers menu-style vertical root range");
    [stylePreferences removeObjectForKey:@"orbCurveSoftness"];
    // The slider must visibly move the shoulder, not merely its control points.
    CGFloat shoulderWidths[2]={0,0};
    for(int endpoint=0;endpoint<2;endpoint++) {
        stylePreferences[@"orbCurveSoftness"]=endpoint?@.85:@0;
        UIBezierPath *outline=FMSideNotchPath(CGRectMake(0,0,14,102),NO,YES,YES);
        for(CGFloat x=0;x<14;x+=.01)
            if(CGPathContainsPoint(outline.CGPath,NULL,CGPointMake(x,12.5),NO)) shoulderWidths[endpoint]+=.01;
    }
    Expect(fabs(shoulderWidths[1]-shoulderWidths[0])>1.4,"orb concavity slider visibly changes shoulder by over 1.4 points");
    [stylePreferences removeObjectForKey:@"orbCurveSoftness"];
    // The exposed outline must follow the visible body's circular caps,
    // regardless of the edge gap or any independent size setting.
    BOOL capsAligned=YES;
    for(NSNumber *scale in @[@.7,@1,@1.9])
    for(NSNumber *bodyWidth in @[@8,@12,@20])
    for(NSNumber *bodyHeight in @[@36,@52,@80])
    for(NSNumber *gap in @[@0,@2,@8])
    for(NSNumber *extension in @[@8,@25,@48])
    for(NSNumber *curve in @[@0,@.33,@.85]) {
        geometryScale=scale.doubleValue;stylePreferences[@"orbCurveSoftness"]=curve;
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
    // ---- Drawer morph: bead and drawer are one family of outlines -------------
    geometryScale=1;[stylePreferences removeAllObjects];
    // Drift guard. The parameter form must keep reproducing the production
    // outlines, so changing FMSideNotchPath without FMDrawerNotchParams or
    // FMBeadNotchParams turns this red instead of making the open jump.
    const CGFloat drawerWidths[3]={76,240,346},drawerHeights[3]={200,320,610};
    for(NSNumber *ext in @[@12,@28,@44]) for(NSNumber *radius in @[@8,@26,@36])
    for(NSNumber *curve in @[@.2,@.64,@.9]) for(NSNumber *compact in @[@NO,@YES])
    for(int size=0;size<3;size++) {
        stylePreferences[@"menuExtension"]=ext;stylePreferences[@"menuCornerRadius"]=radius;stylePreferences[@"menuCurveSoftness"]=curve;
        CGFloat w=drawerWidths[size],h=drawerHeights[size];
        UIBezierPath *family=FMNotchFamilyPath(FMDrawerNotchParams(w,h,compact.boolValue));
        UIBezierPath *production=FMSideNotchPath(CGRectMake(0,0,w,h),NO,compact.boolValue,NO);
        Expect(RowsMatch(PathRows(family.CGPath),PathRows(production.CGPath),1e-9),
               "drawer parameters reproduce the production drawer outline");
    }
    [stylePreferences removeAllObjects];
    for(NSNumber *scale in @[@.7,@1,@1.9]) for(NSNumber *bodyWidth in @[@8,@12,@20])
    for(NSNumber *bodyHeight in @[@36,@52,@80]) for(NSNumber *gap in @[@0,@2,@8])
    for(NSNumber *extension in @[@8,@25,@48]) for(NSNumber *curve in @[@0,@.33,@.85])
    for(NSNumber *unit in @[@1,@2,@.8333333333333334]) {
        geometryScale=scale.doubleValue;stylePreferences[@"orbCurveSoftness"]=curve;
        stylePreferences[@"orbBodyWidth"]=bodyWidth;stylePreferences[@"orbBodyHeight"]=bodyHeight;
        stylePreferences[@"orbEdgeGap"]=gap;stylePreferences[@"orbExtension"]=extension;
        CGSize size=CGSizeMake((bodyWidth.doubleValue+gap.doubleValue)*geometryScale,
                               (bodyHeight.doubleValue+2*extension.doubleValue)*geometryScale);
        UIBezierPath *family=FMNotchFamilyPath(FMBeadNotchParams(size,unit.doubleValue,17.5,63.25));
        Expect(RowsMatch(PathRows(family.CGPath),BeadRows(size,unit.doubleValue,17.5,63.25),1e-9),
               "bead parameters reproduce the docked bead outline at any size, extension and panel scale");
    }
    geometryScale=1;[stylePreferences removeAllObjects];

    // Both ends of the morph are exact, and out-of-range input stays finite.
    FMNotchParams normalBead=FMBeadNotchParams(CGSizeMake(14,102),1,226,155.4);
    FMNotchParams normalDrawer=FMDrawerNotchParams(240,430,NO);
    for(NSNumber *roundness in @[@.65,@1,@1.25,@9]) {
        Expect(ParamsMatch(FMNotchMorphParams(normalBead,normalDrawer,0,roundness.doubleValue),normalBead,1e-9),
               "morph begins as exactly the docked bead");
        Expect(ParamsMatch(FMNotchMorphParams(normalBead,normalDrawer,1,roundness.doubleValue),normalDrawer,1e-9),
               "morph ends as exactly the open drawer");
        Expect(ParamsMatch(FMNotchMorphParams(normalBead,normalDrawer,-3,roundness.doubleValue),normalBead,1e-9) &&
               ParamsMatch(FMNotchMorphParams(normalBead,normalDrawer,7,roundness.doubleValue),normalDrawer,1e-9),
               "progress outside zero to one is clamped");
    }
    Expect(ParamsMatch(FMNotchMorphParams(normalBead,normalDrawer,.5,0),FMNotchMorphParams(normalBead,normalDrawer,.5,.5),1e-12),
           "roundness below the supported range is clamped");
    // A bead rounder than the drawer corner must settle down to it, not snap.
    FMNotchParams roundBead=FMBeadNotchParams(CGSizeMake(28,102),1,212,150);
    FMNotchParams smallCornerDrawer=normalDrawer;smallCornerDrawer.radius=8;smallCornerDrawer.kx=8;smallCornerDrawer.ky=4;
    Expect(ParamsMatch(FMNotchMorphParams(roundBead,smallCornerDrawer,0,1),roundBead,1e-9),
           "a bead rounder than the drawer corner still starts exactly as the bead");
    Expect(ParamsMatch(FMNotchMorphParams(roundBead,smallCornerDrawer,1,1),smallCornerDrawer,1e-9),
           "and still ends as the drawer");

    // Reference frames computed by the geometry model this port was checked against.
    {
        FMNotchParams expected[4]={
            {169.5,129.768558833,240,285.868383175,13.5,25.8246924442,30,0.46,0.7525,23.28427125,16.53427125},
            {90.4,75.4078002306,240,346.245905278,21.2,27.5737516013,30,0.544,0.868,30,16.5},
            {146.9,136.3635,240,278.5435,15.7,25.6125,30,0.484,0.7855,27.09880518,16.51480518},
            {180.8,126.25780835,240,289.767710932,12.4,25.937650954,30,0.448,0.736,21.29641554,16.54441554}};
        const CGFloat steps[4]={.25,.6,.35,.2},rounds[4]={1,1,.65,1.25};
        for(int i=0;i<4;i++)
            Expect(ParamsMatch(FMNotchMorphParams(normalBead,normalDrawer,steps[i],rounds[i]),expected[i],1e-6),
                   "normal drawer morph frames match the validated model");
        FMNotchParams compactBead=FMBeadNotchParams(CGSizeMake(14,102),1,62,174.6);
        FMNotchParams compactDrawer=FMDrawerNotchParams(76,470,YES);
        FMNotchParams compactExpected[2]={
            {40.3,130.000221995,76,326.002045053,14.3,25.2554397366,21.4,0.484,0.7855,19.3304810284,11.7805610284},
            {12.4,43.9644968081,76,421.301639847,22.4,25.7481987583,26,0.592,0.934,26,14.3}};
        const CGFloat compactSteps[2]={.35,.8};
        for(int i=0;i<2;i++)
            Expect(ParamsMatch(FMNotchMorphParams(compactBead,compactDrawer,compactSteps[i],1),compactExpected[i],1e-6),
                   "compact drawer morph frames match the validated model");
        // Half-size panel: the bead is drawn twice as large in the drawer's own coordinates.
        FMNotchParams halfBead=FMBeadNotchParams(CGSizeMake(14,102),2,212,100);
        FMNotchParams halfExpected={106,59.3873801822,240,355.17190097,23,41.8774760364,30,0.52,0.835,30,16.5};
        Expect(ParamsMatch(FMNotchMorphParams(halfBead,normalDrawer,.5,1),halfExpected,1e-6),
               "scaled panel morph frames match the validated model");
    }

    // Every frame stays inside the drawer, stays joined to the docking edge,
    // and a left dock is the exact mirror of a right dock.
    for(NSNumber *compact in @[@NO,@YES]) for(NSNumber *roundness in @[@.65,@1,@1.25]) {
        CGFloat pw=compact.boolValue?76:240,ph=compact.boolValue?470:430;
        CGRect bounds=CGRectMake(0,0,pw,ph);
        FMNotchParams bead=FMBeadNotchParams(CGSizeMake(14,102),1,pw-14,ph*.48-51);
        FMNotchParams drawerParams=FMDrawerNotchParams(pw,ph,compact.boolValue);
        for(int step=0;step<=50;step++) {
            CGFloat t=step/50.;
            UIBezierPath *right=FMDrawerMorphPath(bounds,bead,drawerParams,NO,compact.boolValue,t,roundness.doubleValue);
            UIBezierPath *left=FMDrawerMorphPath(bounds,bead,drawerParams,YES,compact.boolValue,t,roundness.doubleValue);
            CGRect box=CGPathGetPathBoundingBox(right.CGPath);
            Expect(isfinite(box.size.width) && box.origin.x>=-.01 && box.origin.y>=-.01 &&
                   CGRectGetMaxX(box)<=pw+.01 && CGRectGetMaxY(box)<=ph+.01,
                   "morph frames stay inside the drawer bounds");
            Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(pw-.001,ph*.48),NO) &&
                   CGPathContainsPoint(left.CGPath,NULL,CGPointMake(.001,ph*.48),NO),
                   "morph frames stay joined to the docking edge");
            if(step%10==3) for(CGFloat x=.5;x<pw;x+=9.7) for(CGFloat y=.5;y<ph;y+=14.3)
                Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(x,y),NO)==
                       CGPathContainsPoint(left.CGPath,NULL,CGPointMake(pw-x,y),NO),
                       "morph frames mirror exactly between docking edges");
        }
        // First frame is the production bead; last frame is the production drawer.
        UIBezierPath *first=FMDrawerMorphPath(bounds,bead,drawerParams,NO,compact.boolValue,0,roundness.doubleValue);
        Expect(RowsMatch(PathRows(first.CGPath),BeadRows(CGSizeMake(14,102),1,pw-14,ph*.48-51),1e-9),
               "first morph frame is the production bead outline");
        UIBezierPath *last=FMDrawerMorphPath(bounds,bead,drawerParams,NO,compact.boolValue,1,roundness.doubleValue);
        UIBezierPath *drawer=FMSideNotchPath(bounds,NO,compact.boolValue,NO);
        Expect(CGPathEqualToPath(last.CGPath,drawer.CGPath),"last morph frame is byte-for-byte the production drawer outline");
    }

    // The head grows first and the whole outline never shrinks while opening.
    {
        FMNotchParams bead=FMBeadNotchParams(CGSizeMake(14,102),1,226,155.4);
        CGFloat previous=0;BOOL grows=YES;
        for(int step=0;step<=100;step++) {
            UIBezierPath *shape=FMDrawerMorphPath(CGRectMake(0,0,240,430),bead,normalDrawer,NO,NO,step/100.,1);
            CGFloat area=PathArea(shape.CGPath);
            grows &= area>=previous*(1-5e-4);
            previous=area;
        }
        Expect(grows,"drawer area never shrinks while opening");
        for(NSNumber *t in @[@.05,@.1,@.2,@.4]) {
            CGFloat heights[3];int index=0;
            for(NSNumber *roundness in @[@.65,@1,@1.25]) {
                FMNotchParams p=FMNotchMorphParams(bead,normalDrawer,t.doubleValue,roundness.doubleValue);
                heights[index++]=p.bottom-p.top;
            }
            Expect(heights[0]<=heights[1]+1e-9 && heights[1]<=heights[2]+1e-9,
                   "a larger droplet-size setting grows the head taller sooner");
        }
    }

    // Release decisions and the settle spring.
    Expect(FMDrawerCommitDistance(62,1)==28 && fabs(FMDrawerCommitDistance(226,1)-72)<1e-9 &&
           fabs(FMDrawerCommitDistance(100,1)-35)<1e-9 && fabs(FMDrawerCommitDistance(62,2)-56)<1e-9,
           "commit distance is a third of the travel within a thumb-sized range");
    Expect(FMDrawerShouldOpenAfterPull(40,40,0,200,300) && !FMDrawerShouldOpenAfterPull(39.9,40,0,200,300),
           "pulling far enough opens, one point short does not");
    Expect(FMDrawerShouldOpenAfterPull(10,40,181,59,300) && !FMDrawerShouldOpenAfterPull(10,40,180,59,300) &&
           !FMDrawerShouldOpenAfterPull(10,40,181,60,300),
           "an inward flick opens only when fast enough and not drifting sideways");
    Expect(FMDrawerShouldOpenAfterPull(0,40,0,0,5.9) && !FMDrawerShouldOpenAfterPull(0,40,0,0,6),
           "a pan that barely moved counts as a tap");
    Expect(FMDrawerShouldCloseAfterDrag(1,451,226) && !FMDrawerShouldCloseAfterDrag(0,-451,226),
           "a fast flick toward or away from the edge decides alone");
    Expect(!FMDrawerShouldCloseAfterDrag(1,0,226) && !FMDrawerShouldCloseAfterDrag(.62,0,226) &&
           FMDrawerShouldCloseAfterDrag(.61,0,226),
           "a slow release closes below sixty-two percent");
    Expect(FMDrawerShouldCloseAfterDrag(.9,400,100) && !FMDrawerShouldCloseAfterDrag(.9,300,226) &&
           !FMDrawerShouldCloseAfterDrag(.5,-400,226),
           "the projected progress, not just the position, decides a medium-speed release");
    for(int velocity=-449;velocity<=449;velocity+=149) {
        BOOL monotone=YES,previous=YES;
        for(int step=0;step<=100;step++) {
            BOOL closes=FMDrawerShouldCloseAfterDrag(step/100.,velocity,226);
            if(closes && !previous) monotone=NO;
            previous=closes;
        }
        Expect(monotone,"the lower the progress, the more likely the drawer closes");
    }
    {
        CGFloat x=.2,v=1.5;
        FMSpringStep(&x,&v,1,22,1,.3);
        Expect(fabs(x-.9923411279486054)<1e-12 && fabs(v-.14659325972616105)<1e-12,"spring step matches the closed form");
        CGFloat stepped=.2,steppedSpeed=1.5;
        for(int i=0;i<18;i++) FMSpringStep(&stepped,&steppedSpeed,1,22,1,.3/18);
        Expect(fabs(stepped-x)<1e-12 && fabs(steppedSpeed-v)<1e-12,"spring result does not depend on the frame rate");
        CGFloat down=1,downSpeed=-3;
        FMSpringStep(&down,&downSpeed,0,22,1,1/60.);
        Expect(fabs(down-.9125034831138147)<1e-12 && fabs(downSpeed+6.907304846861534)<1e-12,"spring step toward zero matches the closed form");
        CGFloat rest=0,restSpeed=0;BOOL below=YES;double reached=-1;
        for(int i=1;i<=1200;i++) {
            FMSpringStep(&rest,&restSpeed,1,22,1,1/240.);
            if(rest>1+1e-12) below=NO;
            if(reached<0 && rest>=.99) reached=i/240.;
        }
        Expect(below && fabs(rest-1)<1e-9,"a spring released from rest never passes its target");
        Expect(reached>=.2 && reached<=.4,"the settle reaches ninety-nine percent in a restrained 200-400 ms");
    }
    // The springy settle (opening: response .46 s, damping .68) and its rubber band.
    {
        const CGFloat omega=2*M_PI/.46;
        CGFloat x=0,v=0;
        FMSpringStep(&x,&v,1,omega,.68,.1);
        Expect(fabs(x-0.47849774499393627)<1e-12 && fabs(v-6.1982454522070025)<1e-12,"underdamped spring from rest matches the closed form");
        x=.4;v=3;
        FMSpringStep(&x,&v,1,omega,.68,1/60.);
        Expect(fabs(x-0.45663117345130944)<1e-12 && fabs(v-3.7288013745026234)<1e-12,"underdamped spring with initial speed matches the closed form");
        x=1.04;v=0;
        FMSpringStep(&x,&v,1,omega,.68,.2);
        Expect(fabs(x-1.0026418800853087)<1e-12 && fabs(v+0.1055838249155618)<1e-12,"underdamped spring released past the target matches the closed form");
        CGFloat stepped=.4,steppedSpeed=3;
        FMSpringStep(&stepped,&steppedSpeed,1,omega,.68,.3);
        CGFloat fine=.4,fineSpeed=3;
        for(int i=0;i<18;i++) FMSpringStep(&fine,&fineSpeed,1,omega,.68,.3/18);
        Expect(fabs(stepped-fine)<1e-12 && fabs(steppedSpeed-fineSpeed)<1e-12,"underdamped result does not depend on the frame rate");
        // Overshoot is visible, near the textbook exp(-pi*zeta/sqrt(1-zeta^2)), and rings down.
        x=0;v=0;
        double peak=0,arrived=-1;
        for(int i=1;i<=2400;i++) {
            FMSpringStep(&x,&v,1,omega,.68,1/240.);
            peak=fmax(peak,x-1);
            if(arrived<0 && fabs(x-1)<.004 && fabs(v)<.15) arrived=i/240.;
        }
        double theory=exp(-M_PI*.68/sqrt(1-.68*.68));
        Expect(fabs(peak-theory)<.001 && peak>.045 && peak<.065,"opening overshoots by about five percent");
        Expect(arrived>=.4 && arrived<=.6,"the bounce has died down to a point within about half a second");
        // Closing is firmer and reaches the bead quickly.
        x=1;v=0;
        double reached=-1;
        for(int i=1;i<=2400 && reached<0;i++) {
            FMSpringStep(&x,&v,0,2*M_PI/.40,.82,1/240.);
            if(x<=.0015) reached=i/240.;
        }
        Expect(reached>=.2 && reached<=.4,"closing reaches the bead in a quarter to a third of a second");
        // Near critical damping the two branches agree.
        CGFloat a=.2,av=1.5,c=.2,cv=1.5;
        FMSpringStep(&a,&av,1,22,.998,.1);
        FMSpringStep(&c,&cv,1,22,1,.1);
        Expect(fabs(a-c)<2e-3 && fabs(av-cv)<1e-2,"damping just under the critical branch is continuous with it");
        // Rubber band: slope one at the start, monotone, never past the limit.
        Expect(fabs(FMRubberBand(.3,.06)-.05)<1e-12 && FMRubberBand(-1,.06)==0,"rubber band closed form and no pull inside the limit");
        Expect(fabs(FMRubberBand(1e-4,.06)/1e-4-1)<.01,"rubber band starts with the finger one to one");
        BOOL monotone=YES,bounded=YES;CGFloat before=0;
        for(int i=1;i<=400;i++) {
            CGFloat band=FMRubberBand(i*.01,.06);
            if(band<=before) monotone=NO;
            if(band>=.06) bounded=NO;
            before=band;
        }
        Expect(monotone && bounded,"rubber band always increases and never reaches its limit");
        Expect(FMRubberProgress(-.2)==-.2 && FMRubberProgress(.5)==.5 && FMRubberProgress(1)==1,"progress inside zero to one is untouched");
        Expect(fabs(FMRubberProgress(1.3)-1.05)<1e-12 && fabs(FMRubberProgress(2)-1.0566037735849056)<1e-12,"progress past one stretches against resistance");
    }
    // Contents pop in one after another, like the wloc dock icons (response .42 s, damping .62).
    {
        Expect(fabs(FMPopDelay(0,1)-.04)<1e-12 && fabs(FMPopDelay(0,0)-.04)<1e-12,"the first element pops just after the shell is wide enough");
        Expect(fabs(FMPopDelay(5,6)-(.04+5*.07))<1e-12,"a short list pops one element every seventy milliseconds");
        BOOL ordered=YES,bounded=YES;
        for(NSUInteger count=1;count<=40;count++) {
            CGFloat previous=-1;
            for(NSUInteger index=0;index<count;index++) {
                CGFloat delay=FMPopDelay(index,count);
                if(delay<=previous) ordered=NO;
                previous=delay;
            }
            if(previous>.04+.5+1e-12) bounded=NO;
        }
        Expect(ordered,"each element pops later than the one below it");
        Expect(bounded,"a long list finishes its stagger within half a second");
        CGFloat stiffness=FMSpringStiffness(.42),damping=FMSpringDamping(.42,.62);
        Expect(fabs(sqrt(stiffness)*.42-2*M_PI)<1e-9,"stiffness gives a natural period equal to the response");
        Expect(fabs(damping/(2*sqrt(stiffness))-.62)<1e-12,"damping coefficient gives the requested damping fraction");
        Expect(fabs(FMSpringStiffness(0)-FMSpringStiffness(1e-3))<1e-3 && isfinite(FMSpringStiffness(0)),"a zero response stays finite");
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
