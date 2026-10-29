from pathlib import Path
src=(Path(__file__).resolve().parents[2]/"LCFloatingMenu/LCFloatingMenu.m").read_text()
row=src[src.index("- (UIView *)appRow:(NSDictionary *)app {"):src.index("- (UIStackView *)stack {",src.index("- (UIView *)appRow:(NSDictionary *)app {"))]
compact=src[src.index("- (void)appPage:(UIStackView *)stack {"):src.index("- (void)buildAppHeader:",src.index("- (void)appPage:(UIStackView *)stack {"))]
assert "isRunningGuest:" in row and "closeTaskFromButton:" in row, "normal list must show close button only for running apps"
assert "isRunningGuest:" in compact and "closeTaskFromButton:" in compact, "compact tiles must overlay per-running-app close button"
assert "@selector(closeTaskFromButton:)" in row and "@selector(closeTaskFromButton:)" in compact, "separate close action required"
assert "closeGuest:target error:&error" in src, "close must use the exact app identity"
assert "close.frame=CGRectMake(41,0,44,44)" not in compact, "compact close button must not be outside clipped viewport"
assert "[close.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-2]" in compact, "compact badge must stay inside the upper-right viewport edge"
assert "[close.widthAnchor constraintEqualToConstant:closeSize]" in compact, "compact close target must follow effective scale"
assert "48/MAX(.50,self.panelContentScale?:1)" in src, "enlarged normal close targets must preserve 48 screen points independently of switching"
assert "[close.topAnchor constraintEqualToAnchor:container.topAnchor]" in compact, "compact badge must sit at the top-right corner"
assert "height:63+closeSize" not in compact, "running apps must not add a close row"
close=src[src.index("- (void)closeApp:"):src.index("- (void)restart {",src.index("- (void)closeApp:"))]
assert "UIAlertController" not in close, "task close must not ask for confirmation"
assert "[row.trailingAnchor constraintEqualToAnchor:container.trailingAnchor]" in compact, "compact app row must fill actual scroll width"
footer=src[src.index("- (void)buildAppFooter:(UIView *)glass {"):src.index("    CGFloat w=glass.bounds.size.width;",src.index("- (void)buildAppFooter:(UIView *)glass {"))]
compact_footer=footer[footer.index("if(compact) {"):footer.index("} else {",footer.index("if(compact) {"))]
assert "返回首页" in compact_footer and "@selector(compactReturnHome)" in compact_footer, "compact footer must use dedicated home action"
for forbidden in ["@selector(openSettings)", "@selector(toggle)", "@selector(goHome)", "@selector(restart)", "@selector(closeMultitaskGuest)"]:
    assert forbidden not in compact_footer, "compact footer must not contain "+forbidden
home=src[src.index("- (void)compactReturnHome {"):src.index("- (void)goHome {")]
assert "[LCOrbitMultitask showHome]" in home and '[self launchPath:@"ui" uuid:nil]' in home, "compact Home must navigate to LC in both task modes"
assert "confirmTitle:" not in home, "compact Home must not ask for confirmation"
assert "NSUInteger compactActions=1;" in src, "compact footer height must reserve one control"
assert "@selector(openSettings)" in footer, "normal footer must keep settings"
assert "self.orb.center=CGPointMake(Clamp(handleX" not in src, "compact open must not relocate the saved orb"
assert "CGFloat radius=small?(compact?MIN(25,pw*.33):29):32;" in src, "compact corners must be softer than capsule radius"
assert src.count("10+compactActions*63+3") == 1, "compact panel footer height must reserve the smaller inset"
assert "CGFloat height=self.panelFooterHeight;" in src, "footer must use fitted panel height"
assert "action:@selector(holdPanel:)" in src, "drawer long press opens settings"
hold=src[src.index("- (void)hold:(UILongPressGestureRecognizer *)gesture {"):src.index("- (void)draw {",src.index("- (void)hold:(UILongPressGestureRecognizer *)gesture {"))]
assert "[self openSettings];" in hold, "bead long press must open settings"
assert "CGFloat width=MAX(44.,CGRectGetWidth(self.bounds));" in src, "collapsed bead must have a 44pt-wide logical hit region"
assert "self.docksLeft?0:CGRectGetWidth(self.bounds)-width" in src, "hit region must expand inward rather than offscreen"
assert "button.docksLeft=self.left;" in src, "touch region must match the dock side"
assert "FMApplySideNotch(glass,shadow.layer,self.left,compact,NO)" in src, "both app drawer layouts use mirrored side notch"
assert "glass.layer.mask=clip" in src, "notch must clip native glass material"
assert "bead.transform=CGAffineTransformMakeScale(stealth?.18:.32,.88)" not in src, "idle must not squash the glass handle"
assert '@"roundOrb"' not in src and '@"autoFade"' not in src, "removed orb/fade modes must not reappear"
assert "destination.x+(self.left?-travel:travel)" in src and "drawer.center=destination" in src, "drawer must slide from docking side"
assert "drawer.transform=CGAffineTransformMakeScale(sx,sy)" not in src, "drawer must retain full-sized content during motion"
assert "(self.left?safe.left:safe.right)+(small?0:10)" in src, "drawer must dock to visible safe edge"
assert "button.userInteractionEnabled=!self.isOpen" in src, "hidden bead must not intercept drawer taps"
assert "self.dismissLayer.userInteractionEnabled=NO" in src, "closing transition must not accept duplicate taps"
assert 'recentAppsFirst' in src and 'recentOpenedAppKeys' in src, "opt-in recently opened ordering must persist separate from manual order"
assert 'if(BoolPref(@"recentAppsFirst",NO)) return;' in src, "recent-mode must not save old scroll"
assert 'self.appsScrollOffset=0;' in src, "recent-mode opening should reset saved scroll"
assert '[self orderedAppsForMenu]' in src, "only launcher should use recent sort"
assert 'slider.minimumValue=.50;slider.maximumValue=1.20;' in src, "menu scale must allow 50%"
assert 'Clamp(FloatPref(@"panelScale",1.0),.50,1.20)' in src, "50% menu scale must not get clamped up"
assert 'if(actualScale<=.50) break;' in src, "panel fit must accommodate 50% scale"
assert '[backing.widthAnchor constraintEqualToConstant:54]' in compact, "compact icon backing must be smaller than row"
assert '[icon.widthAnchor constraintEqualToConstant:46]' in compact, "compact icon should have more breathing room"
print("Running-task controls, compact tiles and 50% menu scale: PASS")
