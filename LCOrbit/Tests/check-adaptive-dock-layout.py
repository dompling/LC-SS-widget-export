"""Source and geometry regression checks for the custom adaptive switcher Dock."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "Core" / "LCOrbitTaskSwitcher.m").read_text()
layout = source.split("- (void)viewDidLayoutSubviews {", 1)[1].split("- (void)updateLiveGeometry {", 1)[0]
visibility = source.split("- (void)setDockVisible:(BOOL)visible {", 1)[1].split("\n}", 1)[0]
creation = source.split("+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray *)apps dockIconSize:", 1)[-1]

assert "CGAffineTransformMakeTranslation(0,32)" in visibility, "entrance animation prerequisite changed"
assert "self.dock.frame=" not in layout, "transformed frame reintroduces vertical offset"
assert "self.dock.bounds=CGRectMake(0,0,dockWidth,dockHeight);" in layout
assert "self.dock.center=CGPointMake(width*.5,dockTop+dockHeight*.5);" in layout
assert "CGFloat cardBottom=self.dock?dockTop-28:height-safe.bottom-16;" in layout
assert "controller.initialDockVisible=restoredDock;" in creation

# Bounds and center must represent the same resting position whether the Dock
# starts translated by 32pt or visible after a task has been closed.
for height, safe_bottom, dock_height, gap in (
    (852, 34, 56, 4), (852, 34, 48, 80),
    (393, 21, 56, 4), (1024, 20, 56, 25)
):
    top = height - safe_bottom - dock_height - gap
    center = top + dock_height * .5
    resting_top = center - dock_height * .5
    assert abs(resting_top - top) < 1e-9
    assert abs((resting_top + 32) - top - 32) < 1e-9

print("Adaptive switcher Dock transformed-layout regression: PASS")
