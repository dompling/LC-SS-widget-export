from pathlib import Path
src=(Path(__file__).resolve().parents[2]/"LCFloatingMenu/LCFloatingMenu.m").read_text()
row=src[src.index("- (UIView *)appRow:(NSDictionary *)app {"):src.index("- (UIStackView *)stack {",src.index("- (UIView *)appRow:(NSDictionary *)app {"))]
compact=src[src.index("- (void)appPage:(UIStackView *)stack {"):src.index("- (void)buildAppHeader:",src.index("- (void)appPage:(UIStackView *)stack {"))]
assert "isRunningGuest:" in row and "closeTaskFromButton:" in row, "normal list must show close button only for running apps"
assert "isRunningGuest:" in compact and "closeTaskFromButton:" in compact, "compact tiles must overlay per-running-app close button"
assert "@selector(closeTaskFromButton:)" in row and "@selector(closeTaskFromButton:)" in compact, "separate close action required"
assert "closeGuest:app error:&error" in src, "close must target exact app, not current running window"
print("Running-task close controls: PASS")
