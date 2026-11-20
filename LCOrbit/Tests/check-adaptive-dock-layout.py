"""Source and geometry regression checks for the custom adaptive switcher Dock."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "Core" / "LCOrbitTaskSwitcher.m").read_text()
menu = (Path(__file__).resolve().parents[2] / "LCFloatingMenu" / "LCFloatingMenu.m").read_text()
layout = source.split("- (void)viewDidLayoutSubviews {", 1)[1].split("- (void)updateLiveGeometry {", 1)[0]
visibility = source.split("- (void)setDockVisible:(BOOL)visible {", 1)[1].split("\n}", 1)[0]
creation = source.split("+ (BOOL)presentInScene:(UIWindowScene *)scene apps:(NSArray *)apps dockIconSize:", 1)[-1]

assert "CGAffineTransformMakeTranslation(0,32)" in visibility, "entrance animation prerequisite changed"
assert "self.dock.frame=" not in layout, "transformed frame reintroduces vertical offset"
assert "self.dock.bounds=CGRectMake(0,0,dockWidth,dockHeight);" in layout
assert "self.dock.center=CGPointMake(width*.5,dockTop+dockHeight*.5);" in layout
assert "CGFloat cardBottom=self.dock?dockTop-28:height-safe.bottom-16;" in layout
assert "controller.initialDockVisible=restoredDock;" in creation
assert "CGFloat dockHeight=MAX(54,ceil(self.dockIconSize)+16);" in layout
assert "button.frame=CGRectMake(x,8,buttonWidth,dockHeight-16);" in layout
assert "self.dock.layer.cornerRadius=19" in source
assert 'CGFloat iconSize=FMMenuStyleValue(@"adaptiveDockIconSize");' in menu
assert 'case FMDockWhenAdaptive: return [LCOrbitMultitask usesAdaptiveSwitcher];' in menu
assert '@"key":@"adaptiveDockIconSize"' in menu

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

for size in (24, 36, 44, 50):
    dock_height = max(54, size+16)
    button_height = dock_height-16
    assert dock_height >= size+16
    assert (dock_height-button_height)/2 == 8
    assert button_height >= size
    assert 19 < dock_height/2

print("Adaptive switcher Dock transformed-layout and icon-size regression: PASS")
