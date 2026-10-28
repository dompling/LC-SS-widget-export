from pathlib import Path
src=(Path(__file__).resolve().parents[2]/"LCFloatingMenu/LCFloatingMenu.m").read_text()
row=src[src.index("- (UIView *)appRow:(NSDictionary *)app {"):src.index("- (UIStackView *)stack {",src.index("- (UIView *)appRow:(NSDictionary *)app {"))]
compact=src[src.index("- (void)appPage:(UIStackView *)stack {"):src.index("- (void)buildAppHeader:",src.index("- (void)appPage:(UIStackView *)stack {"))]
assert "isRunningGuest:" in row and "closeTaskFromButton:" in row, "normal list must show close button only for running apps"
assert "isRunningGuest:" in compact and "closeTaskFromButton:" in compact, "compact tiles must overlay per-running-app close button"
assert "@selector(closeTaskFromButton:)" in row and "@selector(closeTaskFromButton:)" in compact, "separate close action required"
assert "closeGuest:app error:&error" in src, "close must target exact app, not current running window"
footer=src[src.index("- (void)buildAppFooter:(UIView *)glass {"):src.index("    CGFloat w=glass.bounds.size.width;",src.index("- (void)buildAppFooter:(UIView *)glass {"))]
compact_footer=footer[footer.index("if(compact) {"):footer.index("} else {",footer.index("if(compact) {"))]
assert "收起菜单" in compact_footer and "@selector(toggle)" in compact_footer, "compact footer must offer collapse"
for forbidden in ["@selector(openSettings)", "@selector(goHome)", "@selector(restart)", "@selector(closeMultitaskGuest)"]:
    assert forbidden not in compact_footer, "compact footer must not contain "+forbidden
assert "NSUInteger compactActions=1;" in src, "compact footer height must reserve one control"
assert "@selector(openSettings)" in footer, "normal footer must keep settings"
assert "self.orb.center=CGPointMake(Clamp(handleX" not in src, "compact open must not relocate the saved orb"
assert "CGFloat radius=small?(compact?MIN(25,pw*.33):29):32;" in src, "compact corners must be softer than capsule radius"
assert src.count("10+compactActions*63+3") == 1, "compact panel footer height must reserve the smaller inset"
assert src.count("10+items.count*63+3") == 1, "compact footer sizing must match panel layout"
assert "action:@selector(holdPanel:)" in src, "drawer long press opens settings"
hold=src[src.index("- (void)hold:(UILongPressGestureRecognizer *)gesture {"):src.index("- (void)draw {",src.index("- (void)hold:(UILongPressGestureRecognizer *)gesture {"))]
assert "[self openSettings];" in hold, "bead long press must open settings"
print("Running-task close, compact geometry, and long-press settings: PASS")
