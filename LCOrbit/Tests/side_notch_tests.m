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
#include "side_notch_goldens.inc"
// The eight segments of the nine-segment form (M C L C L C L C) from a flat list of
// coordinates, as PathRows reports them: zero-length lines dropped, a Z at the end.
static NSArray<NSArray<NSNumber *> *> *FamilyRows(const double *v) {
    static const char kinds[8]={'M','C','L','C','L','C','L','C'};
    NSMutableArray<NSArray<NSNumber *> *> *rows=[NSMutableArray array];
    CGPoint current=CGPointZero;
    for(int i=0;i<8;i++) {
        if(kinds[i]=='C') {
            [rows addObject:@[@3,@(v[0]),@(v[1]),@(v[2]),@(v[3]),@(v[4]),@(v[5])]];
            current=CGPointMake(v[4],v[5]);
            v+=6;
        } else {
            CGPoint to=CGPointMake(v[0],v[1]);
            if(kinds[i]=='M') [rows addObject:@[@0,@(to.x),@(to.y)]];
            else if(fabs(to.x-current.x)>1e-9 || fabs(to.y-current.y)>1e-9) [rows addObject:@[@1,@(to.x),@(to.y)]];
            current=to;
            v+=2;
        }
    }
    [rows addObject:@[@4]];
    return rows;
}
// The handle settings under test: the style and the four shape sliders.
static void SetHandle(BOOL capsule,double reach,double length,double softness,double corner) {
    stylePreferences[@"orbHandleStyle"]=@(capsule?0:1);
    stylePreferences[@"orbHandleReach"]=@(reach);
    stylePreferences[@"orbHandleLength"]=@(length);
    stylePreferences[@"orbSoftness"]=@(softness);
    stylePreferences[@"orbCapsuleCorner"]=@(corner);
}
// Both handle styles placed around one centre of a drawer by the production placement
// (unit converts screen points into the drawer's own coordinates). The tests that use
// this keep the centre where nothing has to be held back.
static void Handles(BOOL capsuleStyle,CGFloat unit,CGFloat pw,CGFloat ph,CGFloat centre,FMNotchParams *bead,FMNotchParams *droplet) {
    CGFloat shift=0;
    BOOL placed=FMPlaceHandles(FMOrbHandleMetrics(YES),FMOrbHandleMetrics(NO),capsuleStyle,unit,pw,ph,centre,bead,droplet,&shift);
    Expect(placed && fabs(shift)<1e-9,"the handles fit the drawer where the test puts them");
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
    // ---- The handle: its settings, then the wloc dock's own numbers ------------
    {
        const struct { const char *key; double lo,hi,def,step; } want[4]={
            {"orbHandleReach",14,34,22,1},{"orbHandleLength",56,140,80,2},
            {"orbCapsuleCorner",.55,1,.83,.01},{"orbSoftness",.4,1.6,1,.05}};
        for(int i=0;i<4;i++) {
            NSDictionary *found=nil;
            for(NSDictionary *option in FMOrbStyleOptions()) if([option[@"key"] isEqualToString:@(want[i].key)]) found=option;
            Expect(found!=nil && [found[@"min"] doubleValue]==want[i].lo && [found[@"max"] doubleValue]==want[i].hi &&
                   [found[@"default"] doubleValue]==want[i].def && fabs([found[@"step"] doubleValue]-want[i].step)<1e-12,
                   "handle settings carry the wloc dock's range, default and step");
        }
        for(NSString *gone in @[@"orbExtension",@"orbBodyWidth",@"orbBodyHeight",@"orbEdgeGap",@"orbCurveSoftness",@"orbDropletSize"])
            for(NSDictionary *option in FMOrbStyleOptions())
                Expect(![option[@"key"] isEqualToString:gone],"the superseded shape settings are gone");
    }
    Expect(FMOrbHandleIsCapsule(),"the handle is a capsule by default");
    stylePreferences[@"orbHandleStyle"]=@0;
    Expect(FMOrbHandleIsCapsule(),"style 0 is the capsule");
    stylePreferences[@"orbHandleStyle"]=@1;
    Expect(!FMOrbHandleIsCapsule(),"style 1 is the droplet");
    stylePreferences[@"orbHandleStyle"]=@.49;
    Expect(FMOrbHandleIsCapsule(),"a value just under one half still reads as the capsule");
    stylePreferences[@"orbHandleStyle"]=@(NAN);
    Expect(FMOrbHandleIsCapsule(),"a garbled style falls back to the capsule");
    [stylePreferences removeAllObjects];

    // The dock's own handle, from its Swift source: same metrics, same frame, same outline.
    for(size_t index=0;index<sizeof wlocHandles/sizeof wlocHandles[0];index++) {
        const struct WlocHandle *row=&wlocHandles[index];
        FMHandleMetrics m=FMHandleMetricsFor(row->reach,row->length,row->softness,row->capsule,row->corner);
        const double got[9]={m.reach,m.half,m.topLength,m.topDepth,m.bottomLength,m.bottomDepth,m.cornerX,m.cornerY,m.cornerK};
        BOOL same=YES;
        for(int k=0;k<9;k++) same=same && fabs(got[k]-row->metrics[k])<1e-9;
        Expect(same,"handle metrics match the wloc dock's DockLayout.metrics(at: 0)");
        CGSize frame=FMHandleFrameSize(m);
        Expect(fabs(frame.width-row->metrics[0])<1e-9 &&
               fabs(frame.height-(2*row->metrics[1]+2*fmax(0,fmax(row->metrics[2],row->metrics[4]))))<1e-9,
               "handle frame is the reach wide and the body plus the longer flare on each side tall");
        UIBezierPath *outline=FMNotchFamilyPath(FMHandleNotchParams(m,1,0,0));
        Expect(RowsMatch(PathRows(outline.CGPath),FamilyRows(row->outline),1e-9),
               "handle outline matches the wloc dock's DockShape.path control point by control point");
    }

    // Every handle the settings can produce, at every bead size: as wide as asked, inside its own
    // frame, attached to the wall, exactly mirrored on the other dock, the capsule symmetric top to
    // bottom, and the same outline the family parameters describe at any panel scale.
    for(NSNumber *capsule in @[@YES,@NO]) for(NSNumber *reach in @[@14,@22,@34]) for(NSNumber *length in @[@56,@80,@140])
    for(NSNumber *soft in @[@.4,@1,@1.6]) for(NSNumber *corner in @[@.55,@.83,@1]) for(NSNumber *scale in @[@.7,@1,@1.9]) {
        geometryScale=scale.doubleValue;
        SetHandle(capsule.boolValue,reach.doubleValue,length.doubleValue,soft.doubleValue,corner.doubleValue);
        FMHandleMetrics m=FMOrbHandleMetrics(capsule.boolValue);
        CGSize size=FMHandleFrameSize(m);
        Expect(fabs(size.width-reach.doubleValue*geometryScale)<1e-9,"the handle is as wide as the reach setting times the bead size");
        CGRect frame=CGRectMake(0,0,size.width,size.height);
        UIBezierPath *right=FMSideNotchPath(frame,NO,YES,YES),*left=FMSideNotchPath(frame,YES,YES,YES);
        CGRect box=CGPathGetPathBoundingBox(right.CGPath);
        Expect(isfinite(box.size.width) && box.origin.x>=-.01 && box.origin.y>=-.01 &&
               CGRectGetMaxX(box)<=size.width+.01 && CGRectGetMaxY(box)<=size.height+.01,
               "the handle stays inside its own frame");
        CGFloat middle=size.height*.5,bodyTop=middle-m.half,bodyBottom=middle+m.half;
        Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(size.width-.001,middle),NO) &&
               CGPathContainsPoint(right.CGPath,NULL,CGPointMake(size.width*.5,middle),NO),
               "the handle is solid through its middle and attached to the wall");
        // A capsule's wall corners are rounded off, so only the droplet is attached all along its body.
        if(!capsule.boolValue)
            Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(size.width-.001,bodyTop+4),NO) &&
                   CGPathContainsPoint(right.CGPath,NULL,CGPointMake(size.width-.001,bodyBottom-4),NO),
                   "a droplet stays attached to the wall along its whole body");
        Expect(m.topDepth==m.bottomDepth && (m.topLength>=0)==(m.bottomLength>=0),
               "the wall corners are as deep and of the same kind at the top and the bottom, so the outline can share them");
        BOOL cornerFilled=CGPathContainsPoint(right.CGPath,NULL,CGPointMake(size.width-.05,bodyTop+.05),NO);
        Expect(cornerFilled==!capsule.boolValue,"a droplet flares into the wall at the body's corners, a capsule rounds them off");
        if(capsule.boolValue) {
            Expect(fabs(box.origin.x)<1e-6 && fabs(box.origin.y)<1e-6 &&
                   fabs(box.size.width-size.width)<1e-6 && fabs(box.size.height-size.height)<1e-6 &&
                   fabs(size.height-fmax(length.doubleValue*geometryScale,16))<1e-9,
                   "a capsule is exactly its reach by its length");
        } else {
            Expect(size.height>2*m.half+.5,"a droplet's flares make its frame taller than its body");
        }
        for(NSNumber *unit in @[@1,@2,@.8333333333333334])
            Expect(RowsMatch(PathRows(FMNotchFamilyPath(FMHandleNotchParams(m,unit.doubleValue,17.5,63.25)).CGPath),
                             BeadRows(size,unit.doubleValue,17.5,63.25),1e-9),
                   "bead parameters reproduce the docked bead outline at any size and panel scale");
        if(scale.doubleValue==1) for(CGFloat x=.4;x<size.width;x+=1.7) for(CGFloat y=.4;y<size.height;y+=2.9) {
            Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(x,y),NO)==
                   CGPathContainsPoint(left.CGPath,NULL,CGPointMake(size.width-x,y),NO),"the handle mirrors exactly on a left dock");
            if(capsule.boolValue)
                Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(x,y),NO)==
                       CGPathContainsPoint(right.CGPath,NULL,CGPointMake(x,size.height-y),NO),"a capsule is symmetric top to bottom");
        }
    }
    geometryScale=1;[stylePreferences removeAllObjects];

    // Dragged off the wall the handle is the capsule outline, whatever its style, and the same one
    // from either edge; a capsule handle is that already, so it needs no change of shape.
    for(NSNumber *scale in @[@.7,@1,@1.9]) {
        geometryScale=scale.doubleValue;
        SetHandle(NO,22,80,1,.83);
        FMHandleMetrics pill=FMOrbHandleMetrics(YES);
        CGSize body=FMHandleFrameSize(pill);
        Expect(fabs(body.width-22*geometryScale)<1e-9 && fabs(body.height-80*geometryScale)<1e-9,
               "the free pill is the reach by the length, times the bead size");
        UIBezierPath *outline=FMNotchFamilyPath(FMHandleNotchParams(pill,1,0,0));
        for(CGFloat x=.3;x<body.width;x+=.9) for(CGFloat y=.3;y<body.height;y+=1.7) {
            BOOL inside=CGPathContainsPoint(outline.CGPath,NULL,CGPointMake(x,y),NO);
            Expect(inside==CGPathContainsPoint(outline.CGPath,NULL,CGPointMake(body.width-x,y),NO),
                   "the free pill is identical whichever edge it came from");
            Expect(inside==CGPathContainsPoint(outline.CGPath,NULL,CGPointMake(x,body.height-y),NO),
                   "the free pill is symmetric top to bottom");
        }
        stylePreferences[@"orbHandleStyle"]=@0;
        Expect(RowsMatch(PathRows(FMSideNotchPath(CGRectMake(0,0,body.width,body.height),NO,YES,YES).CGPath),
                         PathRows(outline.CGPath),1e-9),"a capsule handle already is the free pill");
    }
    geometryScale=1;[stylePreferences removeAllObjects];
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
    // ---- Drawer morph: handle and drawer are one family of outlines ------------
    geometryScale=1;[stylePreferences removeAllObjects];
    // Drift guard. The parameter form must keep reproducing the production outlines,
    // so changing FMSideNotchPath without FMDrawerNotchParams or FMHandleNotchParams
    // turns this red instead of making the open jump. (The handle's own guard is in
    // the loop over every handle setting above.)
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

    // Reference frames from the geometry model this port was checked against.
    for(size_t index=0;index<sizeof morphFrames/sizeof morphFrames[0];index++) {
        const struct MorphFrame *row=&morphFrames[index];
        geometryScale=1;[stylePreferences removeAllObjects];
        SetHandle(row->capsule,row->reach,row->length,row->softness,row->corner);
        FMNotchParams bead,droplet,want;
        Handles(row->capsule,1,row->width,row->height,row->height*row->centre,&bead,&droplet);
        memcpy(&want,row->frame,sizeof want);
        Expect(ParamsMatch(FMNotchMorphParams(bead,droplet,FMDrawerNotchParams(row->width,row->height,row->compact),row->t),want,1e-9),
               "morph frames match the validated model, for both handle styles");
    }
    geometryScale=1;[stylePreferences removeAllObjects];

    // Both ends of the morph are exact, out-of-range progress is clamped, every frame stays inside
    // the drawer and joined to the docking edge, a left dock mirrors a right dock exactly, the first
    // frame is the production handle and the last the production drawer, and the drawer never shrinks.
    for(NSNumber *capsule in @[@YES,@NO]) for(NSNumber *compact in @[@NO,@YES]) for(NSNumber *soft in @[@.4,@1,@1.6])
    for(NSNumber *corner in @[@.55,@1]) for(NSNumber *unit in @[@1,@2,@.8333333333333334]) {
        CGFloat pw=compact.boolValue?76:240,ph=compact.boolValue?470:430,centre=ph*.48;
        SetHandle(capsule.boolValue,22,80,soft.doubleValue,corner.doubleValue);
        CGRect bounds=CGRectMake(0,0,pw,ph);
        FMNotchParams bead,droplet,drawer=FMDrawerNotchParams(pw,ph,compact.boolValue);
        Handles(capsule.boolValue,unit.doubleValue,pw,ph,centre,&bead,&droplet);
        Expect(ParamsMatch(FMNotchMorphParams(bead,droplet,drawer,0),bead,1e-9),"morph begins as exactly the docked handle");
        Expect(ParamsMatch(FMNotchMorphParams(bead,droplet,drawer,1),drawer,1e-9),"morph ends as exactly the open drawer");
        Expect(ParamsMatch(FMNotchMorphParams(bead,droplet,drawer,-3),bead,1e-9) &&
               ParamsMatch(FMNotchMorphParams(bead,droplet,drawer,7),drawer,1e-9),"progress outside zero to one is clamped");
        CGFloat previous=0;BOOL grows=YES;
        for(int step=0;step<=100;step++) {
            CGFloat t=step/100.;
            UIBezierPath *right=FMDrawerMorphPath(bounds,bead,droplet,drawer,NO,compact.boolValue,t);
            UIBezierPath *left=FMDrawerMorphPath(bounds,bead,droplet,drawer,YES,compact.boolValue,t);
            CGRect box=CGPathGetPathBoundingBox(right.CGPath);
            Expect(isfinite(box.size.width) && box.origin.x>=-.01 && box.origin.y>=-.01 &&
                   CGRectGetMaxX(box)<=pw+.01 && CGRectGetMaxY(box)<=ph+.01,"morph frames stay inside the drawer bounds");
            Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(pw-.001,centre),NO) &&
                   CGPathContainsPoint(left.CGPath,NULL,CGPointMake(.001,centre),NO),"morph frames stay joined to the docking edge");
            if(step%10==3) for(CGFloat x=.5;x<pw;x+=9.7) for(CGFloat y=.5;y<ph;y+=14.3)
                Expect(CGPathContainsPoint(right.CGPath,NULL,CGPointMake(x,y),NO)==
                       CGPathContainsPoint(left.CGPath,NULL,CGPointMake(pw-x,y),NO),"morph frames mirror exactly between docking edges");
            CGFloat area=PathArea(right.CGPath);
            grows=grows && area>=previous*(1-5e-4);
            previous=area;
        }
        Expect(grows,"the outline never shrinks while the drawer opens");
        FMHandleMetrics own=FMOrbHandleMetrics(capsule.boolValue);
        CGSize size=FMHandleFrameSize(own);
        UIBezierPath *first=FMDrawerMorphPath(bounds,bead,droplet,drawer,NO,compact.boolValue,0);
        Expect(RowsMatch(PathRows(first.CGPath),BeadRows(size,unit.doubleValue,pw-size.width*unit.doubleValue,centre-size.height*unit.doubleValue*.5),1e-9),
               "first morph frame is the production handle outline");
        UIBezierPath *last=FMDrawerMorphPath(bounds,bead,droplet,drawer,NO,compact.boolValue,1);
        Expect(CGPathEqualToPath(last.CGPath,FMSideNotchPath(bounds,NO,compact.boolValue,NO).CGPath),
               "last morph frame is byte-for-byte the production drawer outline");
    }
    geometryScale=1;[stylePreferences removeAllObjects];

    // A capsule turns into the droplet within the first fifth of the way, as in the wloc dock, and from
    // there the two styles move alike; softness is what that first stretch shows.
    for(NSNumber *soft in @[@.4,@1,@1.6]) {
        SetHandle(YES,22,80,soft.doubleValue,.83);
        FMNotchParams capsule,droplet,drawer=FMDrawerNotchParams(240,430,NO);
        Handles(YES,1,240,430,206,&capsule,&droplet);
        for(NSNumber *t in @[@.2,@.21,@.3,@.5,@.9])
            Expect(ParamsMatch(FMNotchMorphParams(capsule,droplet,drawer,t.doubleValue),FMNotchMorphParams(droplet,droplet,drawer,t.doubleValue),1e-12),
                   "from a fifth of the way on, a capsule moves exactly like the droplet");
        FMNotchParams early=FMNotchMorphParams(capsule,droplet,drawer,.1),calm=FMNotchMorphParams(droplet,droplet,drawer,.1);
        Expect(fabs(early.ryt-calm.ryt)>.5 && fabs(early.ryb-calm.ryb)>.5,"early on a capsule is still rounder than the droplet");
    }
    {
        const double softnesses[3]={.4,1,1.6};
        CGFloat neck[2][3];
        for(int style=0;style<2;style++) for(int index=0;index<3;index++) {
            SetHandle(style==0,22,80,softnesses[index],.83);
            FMNotchParams bead,droplet;
            Handles(style==0,1,240,430,206,&bead,&droplet);
            neck[style][index]=FMNotchMorphParams(bead,droplet,FMDrawerNotchParams(240,430,NO),.12).ryb;
        }
        Expect(neck[0][0]<neck[0][1] && neck[0][1]<neck[0][2] && neck[1][0]<neck[1][1] && neck[1][1]<neck[1][2],
               "the softness setting lengthens the neck between the handle and the edge while it is pulled out");
    }
    [stylePreferences removeAllObjects];

    // Placement: the centre is held where the taller frame still fits the drawer, both handles stay
    // inside it, and a handle that cannot fit is refused.
    for(NSNumber *capsule in @[@YES,@NO]) {
        SetHandle(capsule.boolValue,22,80,1.6,.83);
        FMHandleMetrics capsuleMetrics=FMOrbHandleMetrics(YES),dropletMetrics=FMOrbHandleMetrics(NO);
        CGFloat tallest=FMHandleFrameSize(dropletMetrics).height;
        for(NSNumber *unit in @[@1,@2]) for(NSNumber *centre in @[@-50,@0,@100,@215,@430,@500]) {
            FMNotchParams bead,droplet;
            CGFloat shift=0,height=tallest*unit.doubleValue;
            Expect(FMPlaceHandles(capsuleMetrics,dropletMetrics,capsule.boolValue,unit.doubleValue,240,430,centre.doubleValue,&bead,&droplet,&shift),
                   "a handle that fits is placed");
            Expect(fabs(centre.doubleValue-shift-Clamp(centre.doubleValue,height*.5,430-height*.5))<1e-9,
                   "the centre is held where the taller frame still fits inside the drawer");
            Expect(droplet.top>=-1e-9 && droplet.bottom<=430+1e-9 && bead.top>=-1e-9 && bead.bottom<=430+1e-9,
                   "both handles stay inside the drawer");
            Expect(fabs(droplet.wall-240)<1e-9 && fabs(bead.wall-240)<1e-9,"both handles stand on the docking wall");
        }
        FMNotchParams bead,droplet;
        CGFloat shift=0;
        Expect(!FMPlaceHandles(capsuleMetrics,dropletMetrics,capsule.boolValue,1,22,430,215,&bead,&droplet,&shift) &&
               FMPlaceHandles(capsuleMetrics,dropletMetrics,capsule.boolValue,1,22.01,430,215,&bead,&droplet,&shift),
               "a drawer no wider than the handle is refused");
        Expect(!FMPlaceHandles(capsuleMetrics,dropletMetrics,capsule.boolValue,1,240,tallest-.01,100,&bead,&droplet,&shift) &&
               FMPlaceHandles(capsuleMetrics,dropletMetrics,capsule.boolValue,1,240,tallest,100,&bead,&droplet,&shift) &&
               fabs(shift-(100-tallest*.5))<1e-9,
               "a drawer shorter than the taller handle is refused, one just as tall holds it in the middle");
    }
    [stylePreferences removeAllObjects];
    // Release decisions and the settle spring.
    Expect(FMDrawerCommitDistance(62,1)==28 && fabs(FMDrawerCommitDistance(226,1)-72)<1e-9 &&
           fabs(FMDrawerCommitDistance(100,1)-35)<1e-9 && fabs(FMDrawerCommitDistance(62,2)-56)<1e-9,
           "commit distance is a third of the travel within a thumb-sized range");
    Expect(FMQuietPullDistance(1)==40 && fabs(FMQuietPullDistance(.7)-28)<1e-12 && fabs(FMQuietPullDistance(1.9)-76)<1e-12,
           "with no drawer to follow the finger, the pull that counts grows with the bead");
    // What a drag on the bead is: clear only after a few points one way.
    Expect(FMBeadPanIntent(0,0)==FMBeadPanUnclear && FMBeadPanIntent(5.999,0)==FMBeadPanUnclear && FMBeadPanIntent(-3,0)==FMBeadPanUnclear,
           "a drag that has hardly moved is neither a pull nor a move");
    Expect(FMBeadPanIntent(6,0)==FMBeadPanPull && FMBeadPanIntent(30,3)==FMBeadPanPull && FMBeadPanIntent(6,5.999)==FMBeadPanPull,
           "a drag that has gone six points inward, more than along the edge, is a pull");
    Expect(FMBeadPanIntent(6,6)==FMBeadPanUnclear && FMBeadPanIntent(10,12)==FMBeadPanUnclear && FMBeadPanIntent(10,9.999)==FMBeadPanPull,
           "between a pull and a move a drag is not decided yet");
    Expect(FMBeadPanIntent(0,8)==FMBeadPanMove && FMBeadPanIntent(-5,8)==FMBeadPanMove && FMBeadPanIntent(3,30)==FMBeadPanMove &&
           FMBeadPanIntent(10,12.001)==FMBeadPanMove && FMBeadPanIntent(0,7.999)==FMBeadPanUnclear,
           "a drag that has gone eight points along the edge, clearly more than inward, is a move");
    Expect(FMBeadPanIntent(7,8.4001)==FMBeadPanMove && FMBeadPanIntent(7,8.4)==FMBeadPanUnclear,
           "a move needs a fifth more along the edge than inward");
    // Sliding toward the end of a long list scrolls it.
    Expect(FMScrubScrollSpeed(300,100,500)==0 && FMScrubScrollSpeed(144,100,500)==0 && FMScrubScrollSpeed(456,100,500)==0,
           "away from the edges the list stays still");
    Expect(fabs(FMScrubScrollSpeed(100,100,500)+560)<1e-9 && fabs(FMScrubScrollSpeed(500,100,500)-560)<1e-9 &&
           fabs(FMScrubScrollSpeed(122,100,500)+280)<1e-9 && fabs(FMScrubScrollSpeed(478,100,500)-280)<1e-9,
           "at the edge the list scrolls at 560 pt/s, half of that halfway into the zone");
    Expect(fabs(FMScrubScrollSpeed(78,100,500)+840)<1e-9 && fabs(FMScrubScrollSpeed(-500,100,500)+840)<1e-9 &&
           fabs(FMScrubScrollSpeed(900,100,500)-840)<1e-9,
           "past the edge it speeds up, to one and a half times and no further");
    Expect(fabs(FMScrubScrollSpeed(110,100,120))<1e-9 && fabs(FMScrubScrollSpeed(105,100,120)-560*(29-39)/44.)<1e-9,
           "in a list shorter than two zones the two edges pull against each other");
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
    // Long-press scrub (after the wloc dock): which row, where the lens sits, when it is a cancel.
    {
        const CGFloat tops[3]={10,80,150},bottoms[3]={70,140,210};
        Expect(FMScrubIndexAtY(10,tops,bottoms,3,2)==0 && FMScrubIndexAtY(69.999,tops,bottoms,3,2)==0,"the finger is over the first row, top edge included");
        Expect(FMScrubIndexAtY(80,tops,bottoms,3,0)==1 && FMScrubIndexAtY(209.999,tops,bottoms,3,0)==2,"the other rows are found too");
        Expect(FMScrubIndexAtY(70,tops,bottoms,3,2)==2 && FMScrubIndexAtY(75,tops,bottoms,3,0)==0,"between rows the current row stays");
        Expect(FMScrubIndexAtY(-50,tops,bottoms,3,1)==1 && FMScrubIndexAtY(500,tops,bottoms,3,2)==2,"off the list the current row stays");
        Expect(FMScrubIndexAtY(40,tops,bottoms,0,-1)==-1,"an empty list keeps whatever it had");
        Expect(FMScrubLensCenter(5,40,200)==40 && FMScrubLensCenter(100,40,200)==100 && FMScrubLensCenter(500,40,200)==200,
               "the lens follows the finger between the first and last row centers");
        Expect(FMScrubLensCenter(10,40,30)==40,"a single row pins the lens to it");
        Expect(!FMScrubIsOutside(0,240) && !FMScrubIsOutside(240,240) && !FMScrubIsOutside(-44,240) && !FMScrubIsOutside(284,240),
               "the margin around the drawer still counts as inside");
        Expect(FMScrubIsOutside(-44.01,240) && FMScrubIsOutside(284.01,240),"past the margin, letting go cancels");
    }
    const char *preview=getenv("FM_GEOMETRY_PREVIEW");
    if(preview) {
        // One row per handle style: the drawer growing out of it, drawn at 60%.
        CGContextRef ctx=CGBitmapContextCreate(NULL,1200,560,8,0,CGColorSpaceCreateDeviceRGB(),(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGContextSetRGBFillColor(ctx,.035,.04,.055,1); CGContextFillRect(ctx,CGRectMake(0,0,1200,560));
        const CGFloat phases[6]={0,.08,.16,.3,.6,1};
        for(int style=0;style<2;style++) {
            geometryScale=1;[stylePreferences removeAllObjects];
            SetHandle(style==0,22,80,1,.83);
            FMNotchParams bead,droplet,drawer=FMDrawerNotchParams(240,430,NO);
            Handles(style==0,1,240,430,206,&bead,&droplet);
            for(int phase=0;phase<6;phase++) {
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx,20+phase*195,style==0?290:20+258); CGContextScaleCTM(ctx,.6,-.6);
                CGContextSetRGBStrokeColor(ctx,.3,.34,.4,1); CGContextSetLineWidth(ctx,.8);
                CGContextMoveToPoint(ctx,240,-10); CGContextAddLineToPoint(ctx,240,440); CGContextStrokePath(ctx);
                UIBezierPath *outline=FMDrawerMorphPath(CGRectMake(0,0,240,430),bead,droplet,drawer,NO,NO,phases[phase]);
                CGContextAddPath(ctx,outline.CGPath); CGContextSetRGBFillColor(ctx,.48,.51,.55,.65);
                CGContextSetRGBStrokeColor(ctx,.85,.88,.94,.8); CGContextSetLineWidth(ctx,.8);
                CGContextDrawPath(ctx,kCGPathFillStroke); CGContextRestoreGState(ctx);
            }
        }
        CGImageRef img=CGBitmapContextCreateImage(ctx);
        NSURL *url=[NSURL fileURLWithPath:@(preview)];
        CGImageDestinationRef dest=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL);
        CGImageDestinationAddImage(dest,img,NULL); CGImageDestinationFinalize(dest);
        CFRelease(dest); CGImageRelease(img); CGContextRelease(ctx);
    }
    printf("Side-notch and handle morph geometry: %d assertions, %d failures\n",passed+failed,failed);
    return failed?1:0;
}}
